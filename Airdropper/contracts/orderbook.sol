pragma solidity ^0.4.23;

/* The order book supports all ERC20 tokens as well as others implementing 
   the following minimum feature set */
interface ITradeableAsset {
    function approve(address spender, uint tokens) external returns (bool success);
    function transferFrom(address from, address to, uint tokens) external returns (bool success);
    function decimals() external returns (uint256);
    function transfer(address _to, uint256 _value) external;
}

/* A basic permissions hierarchy (Owner -> Admin -> Everyone else). One owner may appoint and remove any number of admins
   and may transfer ownership to another individual address */
contract Administered {
    address public creator;
    address public feeCollector;

    mapping (address => bool) public admins;
    
    constructor()  public {
        creator = msg.sender;
        admins[creator] = true;
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
        require(admins[msg.sender] || creator == msg.sender);
        _;
    }

    //Add an admin with basic privileges. Can be done by any superuser (or the owner)
    function grantAdmin(address newAdmin) onlyOwner  public {
        _grantAdmin(newAdmin);
    }

    function _grantAdmin(address newAdmin) internal
    {
        admins[newAdmin] = true;
    }

    //Transfer ownership
    function changeOwner(address newOwner) onlyOwner public {
        creator = newOwner;
    }

    //Remove an admin
    function revokeAdminStatus(address user) onlyOwner public {
        admins[user] = false;
    }
}


//Manages the trading of a cryptocurrency pair (any token <-> ETH)
//Each pair that is to be traded gets its own OrderBook
contract OrderBook is Administered {
    OrderStruct[] public buyOrderBook;
    OrderStruct[] public sellOrderBook;

    //Built in analytics
    uint totalVolume = 0;

    //Safeguard against malicious manipulation or a disastrous typo
    uint maxCommissionPips = 500; //5%

    //Default fees; change with setCommissionRates
    uint buyCommissionPips = 0;
    uint sellCommissionPips = 0; 

    //The token which is being bought and sold
    ITradeableAsset tokenContract;

    //The counter-currency is always Ethereum
    
    //So if we create an instance of this contract pointing to the YEEK token
    //It means we now have an orderbook for the YEEK-ETH pair.
    //A buy means: spend ETH get YEEK
    //A sell means: spend YEEK get ETH 

    struct OrderStruct {
        uint price;
        uint quantity;
        address sender;
    }

    enum OrderStatus {Pending, Filled, PartialFill};


    /* Emitted when an order is matched and filled, either partially or completely */
    event OrderFilled(address indexed buyer, address indexed seller, bool partialFill);

    /* Sets up the order book, which is ready for trading immediately 
       Note that you must explicitly call setCommissionRates if you 
       want to charge commission on trades */
    function OrderBook(address _tokenContract, address _feeCollector) public {
        tokenContract = ITradeableAsset(_tokenContract);
        feeCollector = _feeCollector;
    }

    /* Sets the buy and sell commission rates (in pips - a pip is 1% of 1%) */
    function setCommissionRates(uint _buy, uint _sell) public onlyAdmin {
        require (_buy <= maxCommissionPips && _sell <= maxCommissionPips);
        buyCommissionPips = _buy;
        sellCommissionPips = _sell;
    }

    //Returns current BID, ASK pricing 
    function getPriceQuotation() public view returns(uint, uint) {
        return (buyOrderBook[buyOrderBook.length - 1].price, 
            sellOrderBook[sellOrderBook.length - 1].price);
    }

    //Submit an order to buy _amount of asset at price _maxPrice (per token)
    //Must include ether in the amount of (max price * number of tokens wanted)
    function placeBuyOrder(uint _maxPrice, uint _amount) public payable {
        require (msg.value == (_maxPrice * _amount));
        uint amount = _amount;

        while (amount > 0) {
            if (_maxPrice >= sellOrderBook[sellOrderBook.length - 1].price) {
                if (amount <= sellOrderBook[sellOrderBook.length - 1].quantity) {
                    tokenContract.transfer(msg.sender, amount); //Send tokens to buyer
                    //Send ether to seller
                    sellOrderBook[sellOrderBook.length - 1].sender.transfer(
                        sellOrderBook[sellOrderBook.length - 1].price * _amount
                    );
                    if (amount == sellOrderBook[sellOrderBook.length - 1].quantity)
                        _deleteOrder((sellOrderBook.length - 1), true);
                    else
                        sellOrderBook[sellOrderBook.length - 1].quantity -= amount;

                    amount = 0;

                } else {
                    //The order is going to be completely filled for the seller
                    //but the buyer's order is only part filled
                    uint qty = sellOrderBook[sellOrderBook.length - 1].quantity;
                    require (amount > qty); //SANITY CHECK
                    tokenContract.transfer(msg.sender, qty); //Send tokens to buyer
                    uint fundsToSend = (qty * sellOrderBook[sellOrderBook.length - 1].price);   //Tally the ether to send to seller
                    uint fee = (fundsToSend * buyCommissionPips / 10000);
                    sellOrderBook[sellOrderBook.length - 1].sender.transfer(fundsToSend - fee);       //Pay the seller
                    feeCollector.transfer(fee)
                    _deleteOrder((sellOrderBook.length -1), false);                             //Delete the sell order, as it has been filled
                    amount -= qty;

                }
                // Match Orders
                // Delete Order From Sellbook
                // Adjust Sum
            } else {
                addBuyToBook(_maxPrice, amount);
                amount = 0;
            }
        }
    }

    // Submit order to sell asset of token at price _minPrice (per token)
    function placeSellOrder(uint _minPrice, uint _amount) public {
        require (tokenContract.transferFrom(msg.sender, this, _amount));
        uint etherOwing = 0;
        uint amount = _amount;
        while (amount > 0) {
            //The last item in the buy order book will be the highest outstanding
            //offer to buy, and hence is most likely to match the sell offer 
            
            //If there are buy offers of equal or greater value, match and fill
            if (buyOrderBook[buyOrderBook.length - 1].price >= _minPrice) {
                // Buy order found for equal or greater number of tokens than the amount remainig
                if (amount <= buyOrderBook[buyOrderBook.length - 1].quantity) {
                    //The seller's order is completely filled, the buyer's may or may not be
                    tokenContract.transfer(buyOrderBook[buyOrderBook.length - 1].sender, amount); //Send tokens to buyer
                    etherOwing += amount * buyOrderBook[buyOrderBook.length - 1].price; //Tally the ether to send to seller

                    //If the buy order is filled, delete
                    //Otherwise adjust number of tokens remaining for sale
                    if (amount == buyOrderBook[buyOrderBook.length - 1].quantity)
                        _deleteOrder((buyOrderBook.length - 1), true);
                    else
                        buyOrderBook[buyOrderBook.length - 1].quantity -= amount;

                    amount = 0;
                } else {
                    //The order is going to be completely filled for the buyer
                    //but only partially for the seller
                    uint qty = buyOrderBook[buyOrderBook.length - 1].quantity;
                    require (amount > qty); //SANITY CHECK
                    tokenContract.transfer(buyOrderBook[buyOrderBook.length - 1].sender, qty); //Send tokens to buyer
                    etherOwing += (qty * buyOrderBook[buyOrderBook.length - 1].price); //Tally the ether to send to seller
                    _deleteOrder((buyOrderBook.length -1), true); //Delete the buy order, as it has been filled
                    amount -= qty;
                }
            } else {
                //Any unsold tokens? We create an order and let it rest on the book
                addSellToBook(_minPrice, amount);
                amount = 0;
            }
        }
        //Always send ether last!
        if (etherOwing > 0) {
            feeCollector.transfer(etherOwing * sellCommissionPips / 10000);
            msg.sender.transfer(etherOwing - (etherOwing * sellCommissionPips / 10000)); 
        }
    }

    // Cancels an order previously placed by the current user 
    // Searches for it based on price and quantity - an exact match is required
    // If a user has placed multiple identical orders (same direction / price / amount)
    // Then this will only delete one of them.
    function cancelOrder(uint _price, uint _amount, bool _isBuyOrder) public returns (bool)
    {
        uint i;
        uint j;

        //Find the order, cancel it, return the ether
        if (_isBuyOrder) {
            for (i = 0; i< buyOrderBook.length; i++) {
                if (buyOrderBook[i].sender == msg.sender && buyOrderBook[i].quantity == _amount && buyOrderBook[i].price == _price) {
                    
                    //Found it. Remove from the book...
                    for (j=i; j< (buyOrderBook.length -1); j++) {
                        buyOrderBook[j] = buyOrderBook[j+1];
                    }
                    //WTF why don't they have a "pop" method?
                    delete buyOrderBook[buyOrderBook.length-1];
                    buyOrderBook.length--;

                    //Return the ether
                    msg.sender.transfer(_price * _amount);
                    return true; //Order successfully cancelled
                }
            }

            return false; //Order not found
        }

        else {
            for ( i = 0; i< sellOrderBook.length; i++) {
                if (sellOrderBook[i].sender == msg.sender && sellOrderBook[i].quantity == _amount && sellOrderBook[i].price == _price) {
                    
                    //Found it. Remove from the book...
                    for (j=i; j< (sellOrderBook.length -1); j++) {
                        sellOrderBook[j] = sellOrderBook[j+1];
                    }
                    //WTF why don't they have a "pop" method?
                    delete buyOrderBook[buyOrderBook.length-1];
                    buyOrderBook.length--;

                    //Return the tokens
                    tokenContract.transfer(msg.sender, _amount);
                    return true; //Order successfully cancelled
                }
            }
            return false; //Order not found
        }

    }

    // Add Order Details to Buy Order Book
    // Place in correctly sorted position (ascending)
    function addBuyToBook(uint _maxPrice, uint _amount) private returns(bool success){
        if (buyOrderBook.length == 0) {
            buyOrderBook.push(OrderStruct({
                    price: _maxPrice,
                    quantity:_amount,
                    sender: msg.sender}));
            return true;
        }
        uint iterLength = buyOrderBook.length - 1;
        for (uint i = 0; i <= iterLength; i++) {
            if (_maxPrice > buyOrderBook[iterLength - i].price) {
                if (i == 0) {
                    buyOrderBook.push(OrderStruct({
                        price: _maxPrice,
                        quantity:_amount,
                        sender: msg.sender}));
                    return true;
                } else {
                    buyOrderBook.push(buyOrderBook[iterLength]);
                    for (uint j=0; j < i; j++) {
                        buyOrderBook[iterLength - j + 1] = buyOrderBook[iterLength - j];
                    }
                    buyOrderBook[iterLength - i + 1] = OrderStruct({
                        price: _maxPrice,
                        quantity:_amount,
                        sender: msg.sender});
                    return true;
                }
            }
        }
        buyOrderBook.push(buyOrderBook[iterLength]);
        for (uint k=0; k < iterLength + 1; k++) {
            buyOrderBook[iterLength - k + 1] = buyOrderBook[iterLength - k];
        }
        buyOrderBook[0] = OrderStruct({
            price: _maxPrice,
            quantity:_amount,
            sender: msg.sender});
        return true;
    }

    // Add Order Details to Sell Order Book
    // Place in correctly sorted position (descending)
    function addSellToBook(uint _minPrice, uint _amount) private returns(bool success){
        if (sellOrderBook.length == 0) {
            sellOrderBook.push(OrderStruct({
                    price: _minPrice,
                    quantity:_amount,
                    sender: msg.sender}));
            return true;
        }
        uint iterLength = sellOrderBook.length - 1;
        for (uint i = 0; i <= iterLength; i++) {
            if (_minPrice < sellOrderBook[iterLength - i].price) {
                if (i == 0) {
                    sellOrderBook.push(OrderStruct({
                        price: _minPrice,
                        quantity:_amount,
                        sender: msg.sender}));
                    return true;
                } else {
                    sellOrderBook.push(sellOrderBook[iterLength]);
                    for (uint j=0; j < i; j++) {
                        sellOrderBook[iterLength - j + 1] = sellOrderBook[iterLength - j];
                    }
                    sellOrderBook[iterLength - i + 1] = OrderStruct({
                        price: _minPrice,
                        quantity:_amount,
                        sender: msg.sender});
                    return true;
                }
            }
        }
        sellOrderBook.push(sellOrderBook[iterLength]);
        for (uint k=0; k < iterLength + 1; k++) {
            sellOrderBook[iterLength - k + 1] = sellOrderBook[iterLength - k];
        }
        sellOrderBook[0] = OrderStruct({
            price: _minPrice,
            quantity:_amount,
            sender: msg.sender});
        return true;
    }

    //Removes order from buy or sell book - does not 
    //refund funds or tokens
    function _deleteOrder(uint idx, bool _isBuyOrder) private {
        uint j;

        if (_isBuyOrder) {
            for (j=idx; j< (buyOrderBook.length -1); j++) {
                buyOrderBook[j] = buyOrderBook[j+1];
            }
            //WTF why don't they have a "pop" method?
            delete buyOrderBook[buyOrderBook.length-1];
            buyOrderBook.length--;
        } else {
            for (j=idx; j< (sellOrderBook.length -1); j++) {
                sellOrderBook[j] = sellOrderBook[j+1];
            }
            //WTF why don't they have a "pop" method?
            delete sellOrderBook[sellOrderBook.length-1];
            sellOrderBook.length--;
        }

    }
}
