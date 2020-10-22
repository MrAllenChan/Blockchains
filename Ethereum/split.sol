pragma solidity ^0.5.0;

contract Dao {
    /** An initial totalBalance of 0.0 */ 
    uint256 private totalBalance = 0;
    /** A balances mapping from addresses to amounts */
    mapping (address => uint256) private balances;
    /** A default valuation of 1.0 */
    uint256 private valuation = 1;
    /** Creator of the contract */
    address private creator;
    /** Curator is able to create proposal and
    delegate responsibility to another address.
    The default curator is the creator */
    address private curator;
    /** the proposal carried by the contract */
    Proposal private curProposal;
    /** record all addresses that have tokens */
    address[] addresses;

    /* define the Proposal struct, which contains
    the latest status of a proposal */
    struct Proposal {
        bool isSealed;                        /** whether the proposal is sealed or unsealed */
        uint256 totalYes;                     /** number of yes votes on the proposal */
        uint256 totalNo;                      /** number of no votes on the proposal */
        mapping (address => bool) voteRecord; /** record each address's vote choice, true for yes vote, false for no vote */
        mapping (address => bool) didVote;    /** record whether each address has voted or not, true for has voted, false for hasn't voted */
        uint256 threshold;                    /** threshold is the number of tokens which existed at the time of the proposal's creation */
        mapping (address => bool) hasSplit;
        mapping (address => uint256) splitPreValuation;
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
        require(curProposal.isSealed || !curProposal.hasSplit[msg.sender]);

        uint256 tokensGained = msg.value / valuation;
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

    /** pays eth out at a rate of valuation for a specified number of tokens */
    function withdraw(uint256 tokensToWithdraw) public returns (bool _bool) {
        require (balances[msg.sender] > tokensToWithdraw);
        require (totalBalance >= tokensToWithdraw);
        require (tokensToWithdraw > 0);
        require (addressExists(msg.sender)); /** only existing address can withdraw tokens */
        
        /** Cannot withdraw tokens if the proposal is unsealed 
        and the address has voted, so it's valid withdraw
        operation only when proposal is sealed or proposal
        is unsealed but the address hasn't voted yet. */
        require (curProposal.isSealed || (!curProposal.didVote[msg.sender]));
        /** sealed and has split */
        if (curProposal.hasSplit[msg.sender]) {
            msg.sender.transfer(tokensToWithdraw * curProposal.splitPreValuation[msg.sender]);
        } else { /** unsealed and hasn't voted, or sealed but no split */
            msg.sender.transfer(tokensToWithdraw * valuation);
        }
        
        balances[msg.sender] -= tokensToWithdraw;
        return true;
    }

    function getBalance() public view returns (uint256 _balance) {
        return balances[msg.sender];
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
            curProposal.hasSplit[addresses[i]] = false;
            curProposal.splitPreValuation[addresses[i]] = 0;
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
            valuation = valuation * getRandom() / 10;
            /** If valuation hits 0.0 all tokens are invalidated */
            if (valuation == 0) {
                totalBalance = 0;
                valuation = 1;
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

    function getRandom() private pure returns(uint) {
        return 10;
    }

    function split() public {
        /** can only be called by someone who has voted on a 
        proposal which is not yet sealed */
        require(!curProposal.isSealed && curProposal.didVote[msg.sender]);
        /** mark split status as true and record the previous valuation */
        curProposal.hasSplit[msg.sender] = true;
        curProposal.splitPreValuation[msg.sender] = valuation;
    }
}