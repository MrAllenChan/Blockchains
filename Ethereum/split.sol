pragma solidity ^0.5.0;

contract Dao {
    uint256 private totalBalance = 0;               /** An initial totalBalance of 0.0 */ 
    mapping (address => uint256) private balances;  /** A balances mapping from addresses to amounts */
    uint256 private valuation = 10;                 /** A default valuation of 10, but in actual use the range will be (0.0, 10.0) */
    address private creator;                        /** Creator of the contract */
    address private curator;                        /** Curator is able to create proposal and delegate responsibility to another address. */
    Proposal private curProposal;                   /** the proposal carried by the contract */
    address[] addresses;                            /** record all addresses that have tokens */

    mapping (address => bool) hasSplit;             /** whether has split */
    mapping (address => uint256) splitPreValuation; /** previous valuation recorded on calling split() time */
    mapping (address => uint256) splitPreDeposit;   /** amount of deposit on calling split() time */

    /* define the Proposal struct, which contains
    the latest status of a proposal */
    struct Proposal {
        bool isSealed;                        /** whether the proposal is sealed or unsealed */
        uint256 totalYes;                     /** number of yes votes on the proposal */
        uint256 totalNo;                      /** number of no votes on the proposal */
        mapping (address => bool) voteRecord; /** record each address's vote choice, true for yes vote, false for no vote */
        mapping (address => bool) didVote;    /** record whether each address has voted or not, true for has voted, false for hasn't voted */
        uint256 threshold;                    /** threshold is the number of tokens which existed at the time of the proposal's creation */
    }

    constructor() public {
        creator = msg.sender;        /** initialize proposal creator */
        curator = creator;           /** initially the curator is the creator */
        curProposal.isSealed = true; /** initially the proposal is sealed */
    }

    /** The curator can call this function to change the
    curator to another address. */
    function delegateCurator(address newCurator) public {
        /** check the sender is the current curator
        and the proposal is sealed */
        require (curator == msg.sender && curProposal.isSealed);
        curator = newCurator;
    }

    /** Call this function to gain tokens (saved in balances and 
    totalBalance) at valuation exchange rate */
    function deposit() payable public {
        /** must be sealed or unsealed but no split */
        require(curProposal.isSealed || !hasSplit[msg.sender]);

        uint256 tokensGained = msg.value / valuation * 10;
        totalBalance += tokensGained;
        balances[msg.sender] += tokensGained;
        /** push new address */
        if (!addressExists(msg.sender)) {
            addresses.push(msg.sender);
        }

        /** A deposit made by someone who has voted also commits 
        the new tokens to their vote */
        if (!curProposal.isSealed && curProposal.didVote[msg.sender]) {
            if (curProposal.voteRecord[msg.sender]) {
                curProposal.totalYes += tokensGained;
            } else if (!curProposal.voteRecord[msg.sender]) {
                curProposal.totalNo += tokensGained;
            }
            /** check latest vote result */
            checkVoteResult();
        }
    }

    /** pays eth out at a rate of valuation for a specified number of tokens 
    note that the valuation is the current value, not the split valuation */
    function withdraw(uint256 tokensToWithdraw) public returns (bool _bool) {
        /** total_balance - split_deposit must be larger than the amount to withdraw */
        require (balances[msg.sender] - splitPreDeposit[msg.sender] >= tokensToWithdraw);
        require (tokensToWithdraw > 0 && addressExists(msg.sender)); /** only existing address can withdraw tokens */
        /** Cannot withdraw tokens if the proposal is unsealed 
        and the address has voted, so it's valid withdraw
        operation only when proposal is sealed or proposal
        is unsealed but the address hasn't voted yet. */
        require (curProposal.isSealed || (!curProposal.didVote[msg.sender]));

        msg.sender.transfer(tokensToWithdraw * valuation / 10);
        balances[msg.sender] -= tokensToWithdraw;
        totalBalance -= tokensToWithdraw;
        return true;
    }

    /** withdraw the part of the money using previous split valuation */
    function splitWithdraw(uint256 tokensToWithdraw) public returns (bool _bool) {
        /** proposal must be sealed and the sender has split */
        require (hasSplit[msg.sender] && curProposal.isSealed);
        require (splitPreDeposit[msg.sender] > tokensToWithdraw);
        require (tokensToWithdraw > 0 && addressExists(msg.sender));

        msg.sender.transfer(tokensToWithdraw * splitPreValuation[msg.sender] / 10);
        balances[msg.sender] -= tokensToWithdraw;
        totalBalance -= tokensToWithdraw;
        splitPreDeposit[msg.sender] -= tokensToWithdraw;
        return true;
    }
    
    /** only curator can create a new proposal and the proposal must be sealed */
    function createProposal() public {
        require (curator == msg.sender && curProposal.isSealed);
        delete curProposal;
        curProposal = Proposal({
            isSealed: false,
            totalYes: 0,
            totalNo: 0,
            threshold: totalBalance / 2
        });
        for (uint i = 0; i < addresses.length; i++) {
            curProposal.didVote[addresses[i]] = false;
            curProposal.voteRecord[addresses[i]] = false;
            /** reset split status when creating a new proposal */
            hasSplit[addresses[i]] = false;
            splitPreValuation[addresses[i]] = 0;
            splitPreDeposit[addresses[i]] = 0;
        }
    }

    /** commits a user's tokens to yes or no for a given proposal */
    function vote(bool voteChoice) public {
        require (!curProposal.isSealed);
        require (balances[msg.sender] > 0);
        require (!curProposal.didVote[msg.sender]);
        require (addressExists(msg.sender)); /** only existing address can vote */
        
        /** set the vote status of the address to true */
        curProposal.didVote[msg.sender] = true;
        /** mark vote record of the current address and update total vote count */
        if (voteChoice) {
            curProposal.voteRecord[msg.sender] = true;
            curProposal.totalYes += balances[msg.sender];
        } else {
            curProposal.voteRecord[msg.sender] = false;
            curProposal.totalNo += balances[msg.sender];
        }
        checkVoteResult();
    }

    /** check vote result of the current proposal */
    function checkVoteResult() private {
        if (curProposal.totalYes > curProposal.threshold) {
            valuation = valuation * getRandomNum() / 10;
            /** If valuation hits 0.0 all tokens are invalidated */
            if (valuation == 0) {
                totalBalance = 0;
                valuation = 10;
                for (uint i = 0; i < addresses.length; i++) {
                    balances[addresses[i]] = 0;
                }
                delete addresses;
            }
            sealProposal();
        } else if (curProposal.totalNo > curProposal.threshold) {
            sealProposal();
        }
    }
    
    function sealProposal() private {
        curProposal.isSealed = true;
    }
    
    /** check whether the address exists, i.e. it has tokens */
    function addressExists(address addr) private view returns (bool) {
        for (uint i = 0; i < addresses.length; i++) {
            if (addresses[i] == addr) {
                return true;
            }
        }
        return false;
    }

    function getRandomNum() private view returns (uint) {
        uint8[1000] memory rand_list = [20, 22, 21, 21, 17, 17, 25, 27, 10, 20, 19, 23, 9, 30, 26, 6, 0, 16, 8, 17, 17, 10, 16, 13, 25, 38, 33, 27, 22, 6, 21, 13, 21, 25, 32, 18, 26, 8, 15, 24, 33, 23, 27, 17, 19, 36, 17, 21, 41, 21, 30, 21, 37, 19, 11, 8, 24, 24, 24, 29, 11, 22, 41, 9, 13, 31, 9, 29, 1, 29, 7, 26, 0, 23, 10, 1, 25, 33, 16, 28, 0, 27, 31, 16, 19, 13, 33, 29, 31, 16, 19, 19, 30, 7, 16, 26, 13, 17, 19, 22, 34, 14, 12, 18, 17, 26, 33, 17, 29, 32, 11, 21, 37, 19, 29, 14, 27, 17, 24, 2, 32, 26, 24, 15, 38, 32, 7, 36, 18, 26, 15, 10, 38, 13, 28, 20, 17, 17, 38, 29, 8, 18, 20, 12, 6, 11, 15, 15, 29, 24, 18, 29, 34, 27, 31, 26, 14, 19, 18, 23, 15, 19, 16, 35, 27, 22, 27, 26, 43, 15, 15, 18, 24, 29, 17, 16, 5, 29, 13, 21, 10, 19, 25, 9, 16, 21, 15, 9, 15, 12, 31, 23, 17, 22, 27, 10, 22, 14, 13, 16, 11, 14, 34, 18, 18, 25, 11, 22, 15, 18, 12, 21, 14, 27, 22, 22, 15, 13, 21, 36, 25, 27, 26, 1, 31, 21, 9, 13, 35, 27, 8, 30, 21, 27, 28, 10, 27, 14, 39, 11, 26, 14, 24, 11, 7, 26, 12, 18, 20, 22, 33, 27, 18, 30, 17, 19, 14, 7, 24, 18, 29, 16, 33, 23, 17, 33, 33, 11, 21, 29, 37, 19, 17, 15, 11, 2, 12, 14, 20, 11, 16, 25, 22, 20, 20, 10, 44, 22, 28, 15, 22, 26, 21, 21, 32, 28, 40, 34, 47, 22, 30, 16, 39, 26, 23, 21, 25, 31, 34, 22, 28, 6, 17, 24, 39, 0, 14, 22, 25, 36, 27, 15, 2, 0, 10, 7, 18, 15, 11, 25, 23, 21, 32, 14, 6, 22, 8, 25, 11, 15, 18, 22, 9, 26, 9, 18, 8, 0, 14, 9, 8, 9, 31, 23, 27, 21, 27, 9, 24, 16, 10, 16, 30, 8, 20, 4, 16, 22, 8, 10, 21, 18, 12, 28, 24, 22, 51, 19, 6, 21, 17, 26, 17, 15, 20, 10, 14, 23, 7, 14, 13, 1, 21, 2, 17, 19, 10, 0, 3, 17, 11, 34, 9, 24, 32, 2, 8, 5, 18, 14, 33, 27, 8, 19, 31, 5, 21, 2, 30, 13, 0, 0, 28, 13, 22, 15, 22, 33, 13, 13, 15, 24, 29, 43, 12, 27, 17, 16, 14, 24, 21, 32, 8, 15, 35, 7, 22, 18, 27, 10, 19, 25, 18, 22, 19, 8, 21, 20, 16, 17, 23, 0, 8, 26, 9, 13, 33, 41, 15, 16, 31, 7, 14, 15, 20, 29, 7, 17, 17, 16, 33, 25, 23, 15, 18, 17, 3, 25, 19, 23, 30, 15, 7, 25, 11, 1, 5, 20, 1, 12, 23, 14, 15, 11, 30, 27, 16, 8, 30, 26, 10, 21, 18, 20, 28, 7, 30, 20, 22, 24, 20, 28, 8, 21, 20, 15, 26, 25, 19, 34, 15, 14, 22, 32, 22, 23, 15, 14, 20, 20, 4, 33, 8, 28, 5, 28, 24, 18, 16, 17, 45, 19, 37, 13, 7, 18, 9, 29, 21, 23, 16, 8, 22, 6, 26, 9, 27, 16, 5, 19, 31, 17, 2, 12, 9, 28, 30, 24, 30, 32, 10, 20, 20, 26, 23, 16, 17, 10, 3, 32, 20, 2, 36, 23, 34, 33, 10, 19, 24, 11, 9, 15, 22, 11, 30, 7, 20, 7, 11, 26, 10, 20, 26, 4, 28, 31, 38, 36, 16, 18, 33, 24, 18, 15, 10, 18, 21, 38, 10, 12, 32, 24, 16, 20, 15, 30, 29, 18, 18, 9, 16, 13, 14, 20, 20, 26, 27, 17, 29, 26, 29, 20, 11, 21, 13, 22, 9, 13, 19, 31, 16, 13, 33, 31, 19, 14, 16, 12, 9, 14, 19, 31, 7, 22, 33, 11, 25, 18, 15, 12, 15, 27, 4, 11, 20, 22, 15, 3, 37, 35, 13, 14, 9, 16, 18, 15, 21, 28, 12, 7, 20, 14, 18, 6, 10, 14, 14, 13, 26, 25, 32, 15, 32, 10, 27, 25, 2, 25, 15, 22, 10, 5, 7, 25, 1, 12, 20, 6, 15, 14, 6, 37, 22, 4, 24, 10, 12, 13, 36, 23, 31, 20, 20, 20, 20, 18, 25, 7, 28, 22, 18, 10, 20, 15, 27, 33, 14, 21, 9, 39, 28, 10, 23, 22, 29, 26, 21, 44, 20, 32, 13, 22, 14, 40, 14, 11, 18, 30, 43, 21, 12, 18, 15, 17, 13, 36, 20, 18, 19, 37, 32, 20, 25, 0, 7, 33, 12, 12, 28, 8, 13, 18, 31, 18, 29, 25, 21, 40, 10, 14, 16, 21, 19, 19, 8, 30, 8, 19, 18, 29, 23, 21, 31, 0, 21, 21, 28, 13, 20, 19, 23, 18, 34, 12, 18, 13, 18, 22, 30, 36, 21, 11, 31, 22, 23, 21, 11, 28, 28, 8, 24, 6, 9, 30, 18, 35, 32, 12, 19, 9, 19, 20, 42, 11, 23, 27, 26, 20, 27, 19, 11, 22, 34, 27, 14, 20, 42, 34, 9, 43, 8, 20, 6, 18, 1, 18, 24, 31, 37, 11, 22, 31, 16, 19, 5, 16, 31, 27, 32, 27, 25, 13, 22, 16, 34, 10, 11, 25, 18, 30, 16, 45, 8, 15, 25, 1, 7, 4, 29, 14, 20, 12, 32, 22, 12, 4, 10, 10, 33, 25, 2, 26, 14, 10, 28, 18, 15, 11, 7, 16, 24, 37, 43, 24, 28, 16, 37, 19, 12, 18, 12, 15, 24, 30, 10, 23, 10, 22, 10, 22, 10, 28, 8, 3, 26, 26, 17, 29, 23, 14, 19, 13, 19, 22, 16, 17, 5, 11, 16, 21, 25, 49, 30, 36, 18, 27, 13, 28, 20, 7, 43, 12, 8, 9, 27, 5, 13, 29, 18, 16];
        uint256 i = uint256(blockhash(block.number - 1)) % 1000;
        return rand_list[i];
    }

    function getBalance() public view returns (uint256 _balance) {
        return balances[msg.sender];
    }

    function split() public {
        /** can only be called by someone who has voted on a 
        proposal which is not yet sealed */
        require(!curProposal.isSealed && curProposal.didVote[msg.sender]);
        /** 1. mark split status as true
            2. record the valuation at the split time
            3. record the deposit of the address at the split time*/
        hasSplit[msg.sender] = true;
        splitPreValuation[msg.sender] = valuation;
        splitPreDeposit[msg.sender] = balances[msg.sender];
    }
}