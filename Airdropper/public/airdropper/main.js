let tokenstats = {airdropPending: false}

let refreshDisplayData = () => {
    

    token = eth.contract(tokenABI).at(tokenAddress);
    dropper = eth.contract(dropperABI).at(dropperAddress);

    /* Begin load token info */
    token.totalSupply().then((totalSupply) => {
        tokenstats.totalSupply = totalSupply[0].toString(10);
        $("#totalSupply").html(rawToDecimal(tokenstats.totalSupply, 18));
    // result <BN ...>  4500000
    })

    token.symbol().then((sym) => {
        tokenstats.symbol = sym[0];
        $(".symbol").html(tokenstats.symbol);
        $("#etherscanUrl").attr("href", "https://etherscan.io/token/"+tokenAddress);
    })

    token.name().then((sym) => {
        tokenstats.name = sym[0];
        $("#tokenName").html(tokenstats.name);
    })
    token.decimals().then((val) => {
        tokenstats.decimals = val[0].toString(10);
        $("#decimals").html(tokenstats.decimals);
    })

    /* Begin Load User Balances */
    token.balanceOf(myAddress).then((balance) => {
        tokenstats.balance = balance[0].toString(10);
        $("#tokenBalance").html(rawToDecimal(tokenstats.balance, 18));
    })

    eth.getBalance(myAddress, (err, balance) => {
        var value = web3.fromWei(balance, 'ether');
        tokenstats.etherBalance = value.toString(10);
        $("#etherBalance").html(tokenstats.etherBalance);
    });
      
    /* Begin Load Airdropper Info */
    dropper.tokensDispensed().then((amount) => {
        tokenstats.dispensed = amount[0].toString(10);
        $("#tokensDispensed").html(rawToDecimal(tokenstats.dispensed, 18));
    })

    dropper.tokensRemaining().then((amount) => {
        tokenstats.remaining = amount[0].toString(10);
        $("#tokensRemaining").html(rawToDecimal(tokenstats.remaining, 18));
    })

    dropper.numberOfTokensPerUser().then((amount) => {
        tokenstats.airdropsize = amount[0].toString(10);
        $("#airdropAmount").html(rawToDecimal(tokenstats.airdropsize, 18));
    })

    dropper.airdroppedUsers(myAddress).then((hasGottenAirdrop) => {
        if (hasGottenAirdrop[0]) {
            $("#eligibility").html("Already Received")
            $("#withdrawAirdropTokens").attr("disabled", "disabled")
        } else {
            //If they just requested the airdrop, don't confuse them
            if (!tokenstats.airdropPending) {
                $("#eligibility").html("Hit Button For Tokens")
                $("#withdrawAirdropTokens").removeAttr("disabled")
            }
        }
    })

}


  $(document).ready(() => {
    
    $("#withdrawAirdropTokens").on("click", () => {
        console.log("main.js 557: Withdraw Button Clicked")
        $("#eligibility").html("Please authorize the transaction in your wallet to continue...")
        $("#withdrawAirdropTokens").attr("disabled", "disabled")

        dropper.withdrawAirdropTokens({"from": myAddress}).then((tx) => {
                $("#eligibility").html("Transaction Processing: <a href='https://etherscan.io/tx/"+ tx+"'>"+tx+"</a>");
                tokenstats.airdropPending = true;
        })
    })


    setTimeout(() => {
        if (typeof web3 == 'undefined') {
            $("#needMetamask").show();
            return;
        }

        myAddress = window.web3.eth.defaultAccount;
        eth = new Eth(window.web3.currentProvider);


        console.log("Account: "+myAddress);
        $("#ethAddress").html(myAddress.substring(0,10)+"...");

        refreshDisplayData();
        //Poll the blockchain, refresh the display
        setInterval(refreshDisplayData, 5000)
    }, 2000)
})
