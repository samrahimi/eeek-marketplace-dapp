pragma solidity ^0.4.23;
library MathUtils {
    function removeElement(uint[] array, uint index) pure internal returns(uint[] value) {
        if (index >= array.length) return;

        uint[] memory arrayNew = new uint[](array.length-1);
        for (uint i = 0; i<arrayNew.length; i++){
            if(i != index && i<index){
                arrayNew[i] = array[i];
            } else {
                arrayNew[i] = array[i+1];
            }
        }
        delete array;
        return arrayNew;
    }
    //Integer approximation of log2(b)
    function log2simple(uint b) pure public returns (uint){
        for(uint i=0;2**i<=b;i++){}
        return i-1;
    }
    //Integer approximation of log10(b)
    function log10simple(uint b) pure public returns (uint){
        for(uint i=0;10**i<=b;i++){}
        return i-1;
    }
}

/* Some basic permissions for ur contracts */
contract Administered {
    address public creator;
    
    struct AdminRights {
        bool isSuperUser;
        bool isAdmin; 
    }
    
    mapping (address => AdminRights) public admins;
    
    constructor()  public {
        creator = msg.sender;
        admins[creator] = AdminRights({isSuperUser: true, isAdmin: true});
    }

    //Restrict to the current owner. There may be only 1 owner at a time, but 
    //ownership can be transferred.
    modifier onlyOwner {
        require(creator == msg.sender);
        _;
    }
    
    //Restrict to any admin. Not sufficient for highly sensitive methods
    //since basic admin can be granted programatically regardless of msg.sender
    modifier onlyAdmin {
        require(admins[msg.sender].isAdmin || creator == msg.sender);
        _;
    }

    //Restrict to an admin with superuser privileges. SU can only be granted by 
    //the owner, so onlySU methods are secure.
    modifier onlySU {
        require((admins[msg.sender].isAdmin && admins[msg.sender].isSuperUser)
                || creator == msg.sender);
        _;
    }

    //Add an admin with basic privileges. Can be done by any superuser (or the owner)
    function grantAdmin(address newAdmin) onlySU  public {
        admins[newAdmin] = AdminRights({isSuperUser: false, isAdmin: true});
    }
    
    //Add an admin with basic privileges. May only be called from a derived contract, does not check msg.sender
    //Note that the caller is responsible for implementing its own security logic. 
    function autoGrantBasicAdminPrivileges(address newAdmin) internal
    {
        admins[newAdmin] = AdminRights({isSuperUser: false, isAdmin: true });
    }
    //Sets the admin and superuser privileges for a given address.
    //To revoke all privileges, call setAdminStatus(address, false, false)
    //Owner only.
    function setAdminStatus(address admin, bool isAdmin, bool isSU) onlyOwner public {
        //Note that it's impossible to delete items from a mapping in Solidity
        //Therefore: to revoke admin privileges, call updateAdminStatus(address, false, false)
        admins[admin] = AdminRights({isSuperUser: isSU, isAdmin: isAdmin });
    }
    //Transfer ownership of this contract
    function changeOwner(address newOwner) onlyOwner public {
        creator = newOwner;
    }
    //Gets admin status for an address
    function getAdminStatus(address user) public view returns (bool, bool)  {
        return (admins[user].isSuperUser, admins[user].isAdmin);
    }
}

//Generic user reputation functionality, for any marketplace app
contract Reputable {
    mapping(address => uint256) public completedTransactionCount;
    mapping(address => uint256) public negativeFeedbackCount;
    
    function addCompletedTransaction(address user) internal {
        completedTransactionCount[user]++;
    }
    
    function addNegativeFeedback(address user) internal {
        negativeFeedbackCount[user]++;
    }
    
    function getPctPositive(address user) public view returns(uint256)  {
        uint256 pctPositive = 100- (100 * negativeFeedbackCount[user] / (completedTransactionCount[user]+1));
        return pctPositive;
    }
    
    function getCompletedTransactionCount(address user) public view returns(uint256)  {
        return completedTransactionCount[user];
    }


    function getReputationScore(address user) public view returns(uint256)  {
        //pctPositive * scaledTransactionCount
        //scaledTransactionCount is: 1 for <10 transactions, 2 for <100 transactions, etc.
        uint256 pctPositive = 100- (100 * negativeFeedbackCount[user] / (completedTransactionCount[user]+1));
        uint256 scaledTransactionCount = MathUtils.log10simple(completedTransactionCount[user]+1) + 1;
        return pctPositive * scaledTransactionCount;
    }
}

contract EEEK is Administered, Reputable
{
    uint8 public commissionPercent = 5;             //Marketplace owner gets 5% of each transaction; the rest goes to whoever does the work.
                                                    //This is way better than any existing, centralized marketplace for writers / creatives. 
                                                    //Proceeds go towards paying engineers who build EEEK (via GitCoin), paying community
                                                    //members who assist us by arbitrating disputes, and of course paying everyone who 
                                                    //creates content for EEEK (writers / designers) or distributes it (social media marketers).
                                                    
    uint256 public minGigValue = 0.001 ether;       //Less than this would be non-cost-effective in terms of gas
    uint256 public maxGigValue = 100 ether;         //Approx. $50000
    
    uint256 arbitratorPayoutPerItem = 0.0025 ether; //Submissions rejected by the requester go into an arbitration queue.
                                                    //any user meeting the reputation criteria may review these cases
                                                    //and adjudicate them in favor of the requester OR the contractor.
                                                    //The losing party gets negative feedback on their reputation.
    

    
    uint256 maxReviewTime = 24 hours;               //If a completed gig is not approved or rejected within this timespan,
                                                    //it is automatically approved by the system. Requesters must review 
                                                    //promptly if they are to exercise their privilege to reject
    
    /* Update app-wide values */
    function setGlobalThresholds(uint8 commission, uint256 minValue, uint256 maxValue, uint256 arbitratorPayout, uint256 reviewTime) onlyOwner public  {
        commissionPercent = commission;
        minGigValue = minValue;
        maxGigValue = maxValue;
        arbitratorPayoutPerItem = arbitratorPayout;
        maxReviewTime = reviewTime;
    }
    
    
    /* Quality Thresholds for requesters, contractors, and arbitrators.
       Note that negative feedback is only given once an arbitrator has ruled against the community member
       These values will need tweaking, see setReputationThresholds */
       
    uint256 minPctPositiveToArbitrate = 80;             //Arbitrators must be at least this % positive 
    uint256 minCompletedTransactionsToArbitrate = 0;    //This will change...
    uint256 minPctPositiveToFreelance = 0;         //Contractors must maintain at least this % positive
    uint256 minPctPositiveToPostGigs = 0;          //Requesters must maintain at least this % positive

    function setReputationThresholds(uint arbitrationPct, uint arbitrationCount, uint freelancePct, uint gigPct) onlyOwner public {
        minPctPositiveToArbitrate = arbitrationPct;
        minCompletedTransactionsToArbitrate = arbitrationCount;
        minPctPositiveToFreelance = freelancePct;
        minPctPositiveToPostGigs = gigPct;
    }

    //Restrict access to users meeting arbitration thresholds
    modifier onlyQualifiedArbitrator {
        require(getPctPositive(msg.sender) >= minPctPositiveToArbitrate);
        require(getCompletedTransactionCount(msg.sender) >= minCompletedTransactionsToArbitrate);
        _;
    }
    
    //Restrict based on min. requester thresholds 
    modifier onlyQualifiedRequester 
    {
        require(getPctPositive(msg.sender) >= minPctPositiveToPostGigs);
        _;
    }
    
    //Restrict based on min. requester thresholds 
    modifier onlyQualifiedContractor 
    {
        require(getPctPositive(msg.sender) >= minPctPositiveToFreelance);
        _;
    }



    enum GigStatus {OPEN,IN_PROGRESS,COMPLETED,APPROVED,ARBITRATION_PENDING,IN_ARBITRATION,REJECTED,CANCELLED}

    struct Gig {
        address requester;              //The client who needs work done posts valueInWei
        address contractor;             //The worker, gets valueInWei - (valueInWei * commissionPercent/100)
        address arbitrator;             //The arbitrator who resolves a disputed gig. Paid arbitratorPayoutPerItem
        
        GigStatus status;               //Tracks the flow from posting to payout (or rejection / disputes)
        string gigRequestHash;          //Hash of the request content. If using a centralized database, 
                                        //the front end should hash the JSON representing the gig request 
                                        //as it will serve to verify that content has not been altered.
                                        //If using IPFS or Swarm, the hash should point to the content itself.
                                        
        string gigResponseHash;         //Hash of the contractor's response once gig is completed. 
                                        //Will either represent the URL where contractor has posted the content
                                        //or the content itself, depending on the requester's preferences
    
        uint256 requested_at;
        uint256 accepted_at;
        uint256 submitted_at;
        uint256 approved_at;
        
        uint256 time_limit;             //Starting from when a contractor accepts a gig. The completed work 
                                        //must be submitted no later than: requested_at + time_limit 
        uint256 valueInWei;
    }
    
    mapping (address => uint[]) public userRequests; 
    mapping (address => uint[]) public userGigs;
    mapping (uint => Gig) public gigsById;
    uint[] public allGigs;
    uint[] public arbitrationQueue;
    uint[] public appealsQueue;
    uint256 currentGigId = 0;

    //Client posts gig data offchain (e.g. bzz) and provides its Hash
    //along with time limit. Must be accompanied by the gig's value in ether
    //which will be placed in escrow (held by the contract).
    function createNewRequest(string requestHash, uint256 timeLimit) onlyQualifiedRequester public payable {
        require (msg.value >= minGigValue && msg.value <=maxGigValue);
        currentGigId++;
        
        gigsById[currentGigId] = Gig({
            requester: msg.sender,
            contractor: 0x0,
            arbitrator: 0x0,
            status: GigStatus.OPEN,
            gigRequestHash: requestHash,
            time_limit: timeLimit,
            valueInWei: msg.value,
            requested_at: now,
            accepted_at:0,
            submitted_at: 0,
            approved_at: 0,
            gigResponseHash:''
        });
        
        userRequests[msg.sender].push(currentGigId);
    }
    
    //User accepts gig and starts work - the time limit begins ticking here.
    function acceptGig(uint256 gigId) onlyQualifiedContractor public {
        require (gigsById[gigId].status == GigStatus.OPEN);
        require (msg.sender != gigsById[gigId].requester);
        gigsById[gigId].accepted_at = now;
        gigsById[gigId].contractor = msg.sender;
        gigsById[gigId].status = GigStatus.IN_PROGRESS;
        
        userGigs[msg.sender].push(gigId);
    }
    //The completed work is stored offchain or posted on the web
    //A hash of the content and/or its URL is provided here by the worker.
    //The requester must approve or reject within 24h - if not, submission is
    //auto approved and the funds paid to the worker.
    function submitWork(uint256 gigId, string responseHash) public {
        require ((now - gigsById[gigId].accepted_at) <= gigsById[gigId].time_limit);
        require (gigsById[gigId].status == GigStatus.IN_PROGRESS);
        require (gigsById[gigId].contractor == msg.sender);

        gigsById[gigId].submitted_at = now;
        gigsById[gigId].gigResponseHash = responseHash;
        gigsById[gigId].status = GigStatus.COMPLETED;
    }
    
    //Requester approves submitted work, contractor is paid, case closed
    function approve(uint256 gigId) public {
        require (gigsById[gigId].status == GigStatus.IN_PROGRESS);
        require (gigsById[gigId].requester == msg.sender);
        
        gigsById[gigId].status = GigStatus.APPROVED;
        uint256 payout = gigsById[gigId].valueInWei - (gigsById[gigId].valueInWei * commissionPercent / 100);
        gigsById[gigId].contractor.transfer(payout);            //Pay the contractor, leaving 5% fee in the contract's balance
        //creator.transfer(gigsById[gigId].valueInWei - payout);
    }
    
    //Requester rejects submission, funds held in escrow pending 3rd party review
    function reject(uint256 gigId) public {
                require (gigsById[gigId].status == GigStatus.COMPLETED);
                require (gigsById[gigId].requester == msg.sender);
                require ((now - gigsById[gigId].submitted_at) <= maxReviewTime);
                
                gigsById[gigId].status = GigStatus.ARBITRATION_PENDING;
                arbitrationQueue.push(gigId);
    }
    
    //Forces release of escrow to contractor if requester neither approves nor rejects 
    //within maxReviewTime after submission.
    function refreshApprovalStatus(uint256 gigId) public returns(bool) {
            require (gigsById[gigId].status == GigStatus.COMPLETED);
            if ((now - gigsById[gigId].submitted_at) > maxReviewTime) {
                        //Force approval for gigs that have linged in COMPLETED state longer than maxReviewTime
                        gigsById[gigId].status = GigStatus.APPROVED;
                        uint256 payout = gigsById[gigId].valueInWei - (gigsById[gigId].valueInWei * commissionPercent / 100);
                        gigsById[gigId].contractor.transfer(payout);            //Pay the contractor, leaving 5% fee in the contract's balance
                        return true;
            }
            else {
                return false; //Still within window of review, do not update the status
            }
    }
    
    //Re-opens a gig if the contractor has not submitted the work within the gig's time_limit
    function refreshSubmissionStatus(uint256 gigId) public returns(bool) {
            require (gigsById[gigId].status == GigStatus.IN_PROGRESS);
            //Deadline missed:
            if ((now - gigsById[gigId].accepted_at) > gigsById[gigId].time_limit) {
                //Fire the contractor and re-open the request
                gigsById[gigId].status = GigStatus.OPEN;
                address formerContractor = gigsById[gigId].contractor;
                gigsById[gigId].contractor = 0x0;
                gigsById[gigId].accepted_at = 0;
                
                //Update contractor stats with negative feedback
                addCompletedTransaction(formerContractor);
                addNegativeFeedback(formerContractor);
                
                //Updated: true
                return true;
            } else {
                return false;
            }
    }
    
    //Pulls the next pending item out of the arbitrationQueue and assigns to the current user
    function getItemForArbitration() onlyQualifiedArbitrator public returns (uint256) {
        require (arbitrationQueue.length >= 1);
        uint256 gigId = arbitrationQueue[0];                             //First in, First out
        gigsById[gigId].status = GigStatus.IN_ARBITRATION;               
        gigsById[gigId].arbitrator = msg.sender;
        arbitrationQueue = MathUtils.removeElement(arbitrationQueue, 0); //Dequeue the item
        return gigId;
    }
    
    //Upholds or denies a requester's rejection of contractor's submission
    //sideWithPlaintiff == true to uphold the rejection.
    //If upheld: contractor is fired, gig is closed as rejected, requester gets full refund, contractor gets negative feedback
    //If denied: contractor is paid, gig is closed as approved, requester gets negative feedback
    function submitArbitrationRuling(uint256 gigId, bool sideWithPlaintiff) public {
        //Note: we might want to in future just reopen gigs where rejected work was upheld
        //but for now its simpler to just give a refund and let them post it again
        require (msg.sender == gigsById[gigId].arbitrator && gigsById[gigId].status == GigStatus.IN_ARBITRATION);
        
        //Transaction is done, either way... both sides get 1 added to their count
        addCompletedTransaction(gigsById[gigId].requester);
        addCompletedTransaction(gigsById[gigId].contractor);
        addCompletedTransaction(gigsById[gigId].arbitrator);
        
        if (sideWithPlaintiff) {
            gigsById[gigId].status = GigStatus.REJECTED;
            addNegativeFeedback(gigsById[gigId].contractor);    //Negative feedback for contractor
            gigsById[gigId].requester.transfer(gigsById[gigId].valueInWei);     //Full refund of escrow, no commission is taken
        } else {
            gigsById[gigId].status = GigStatus.APPROVED;
            uint256 payout = gigsById[gigId].valueInWei - (gigsById[gigId].valueInWei * commissionPercent / 100);
            addNegativeFeedback(gigsById[gigId].requester);     //Negative feedback for requester who tried to stiff the contractor
            gigsById[gigId].contractor.transfer(payout);        //Pay the contractor, leaving 5% fee in the contract's balance
        }
        
        //Arbitrator gets paid for their work
        gigsById[gigId].arbitrator.transfer(arbitratorPayoutPerItem);
    }
    
    //Lovely! A self sustaining economy in under 400 lines of solidity
}

