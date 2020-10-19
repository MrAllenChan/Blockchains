pragma solidity ^0.5.1;

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
    Proposal private proposal;
    address[] addresses;

    /* define the Proposal struct, which contains
    the latest status of a proposal */
    struct Proposal {
        bool isSealed;        /** whether the proposal is sealed or unsealed */
        uint256 totalYes;
        uint256 totalNo;
        mapping (address => bool) voteRecord;
        mapping (address => bool) didVote;
        uint256 threshold;  /** threshold is the number of tokens which 
        existed at the time of the proposal's creation */
    }

    constructor() public {
        creator = msg.sender;
        curator = creator;
        proposal.isSealed = true; /** initial the proposal is sealed */
    }

    /** The curator can call this function to change the
    curator to another address. */
    function delegateCurator(address newCurator) public {
        /** check the sender is the current curator
        and the proposal is sealed */
        require (curator == msg.sender && proposal.isSealed);
        curator = newCurator;
    }

    /** Call this function to gain tokens (saved in balances and 
    totalBalance) at valuation exchange rate */
    function deposit() payable public {
        uint256 tokensGained = msg.value / valuation;
        totalBalance += tokensGained;
        balances[msg.sender] += tokensGained;
        /** A deposit made by someone who has voted also commits 
        the new tokens to their vote */
        if (!proposal.isSealed && proposal.didVote[msg.sender]) {
            if (proposal.voteRecord[msg.sender]) {
                proposal.totalYes += tokensGained;
            } else if (!proposal.voteRecord[msg.sender]) {
                proposal.totalNo += tokensGained;
            }
            /** check latest vote result */
            checkVoteResult();
        }
    }

    function withdraw(uint256 tokensToWithdraw) public returns (bool _bool){
        require (balances[msg.sender] > tokensToWithdraw);
        require (totalBalance >= tokensToWithdraw);
        require (tokensToWithdraw > 0);
        // require (!checkNewAccount(msg.sender));  // only the existed account can withdraw
        
        /** Cannot withdraw tokens if the proposal is unsealed 
        and the address has voted, so it's valid withdraw
        operation only when proposal is sealed or proposal
        is unsealed but the address hasn't voted yet. */
        require (proposal.isSealed || (!proposal.didVote[msg.sender]));
        
        balances[msg.sender] -= tokensToWithdraw;
        msg.sender.transfer(tokensToWithdraw * valuation);
        return true;
    }

    function getBalance() public view returns (uint256) {
        return balances[msg.sender];
    }
    
    function createProposal() public {
        require (msg.sender == curator);
        require (proposal.isSealed);
        proposal.isSealed = false;
        proposal.threshold = totalBalance / 2;
    }
    
    function vote(bool voteChoice) public {
        require (!proposal.isSealed);
        require (balances[msg.sender] > 0);
        require (!proposal.didVote[msg.sender]);
        
        /** set the vote status of the address to true */
        proposal.didVote[msg.sender] = true;
        if (voteChoice) {
            proposal.voteRecord[msg.sender] = true;
            proposal.totalYes += balances[msg.sender];
        } else {
            proposal.voteRecord[msg.sender] = false;
            proposal.totalNo += balances[msg.sender];
        }
        checkVoteResult();
    }

    function checkVoteResult() private {
        if (proposal.totalYes > proposal.threshold) {
            valuation = valuation * getRandom() / 10;
            if (valuation == 0) {
               resetBalance();
            }
            resetProposal();
        } else if (proposal.totalNo > proposal.threshold) {
            resetProposal();
        }
    }
    
    function resetProposal() private {
        proposal = Proposal({
            isSealed: true,
            totalYes: 0,
            totalNo: 0,
            threshold: totalBalance / 2
        });
        for (uint i = 0; i < addresses.length; i++) {
            proposal.didVote[addresses[i]] = false;
            proposal.voteRecord[addresses[i]] = false;
        }
    }
    
    function resetBalance() private {
        totalBalance = 0;
        for (uint i = 0; i < addresses.length; i++) {
            balances[addresses[i]] = 0;
        }
        valuation = 1;
    }
    
    function checkNewAccount(address newAddress) private view returns(bool) {
        for (uint i = 0; i < addresses.length; i++) {
            if (addresses[i] == newAddress) {
                return false;
            }
        }
        return true;
    }

    function getRandom() private pure returns(uint) {
        return 1;
    }
}