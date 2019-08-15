pragma solidity ^0.5.0;

library SafeMath {
    function add(uint a, uint b) internal pure returns (uint c) {
        c = a + b;
        require(c >= a);
    }
    function sub(uint a, uint b) internal pure returns (uint c) {
        require(b <= a);
        c = a - b;
    }
    function mul(uint a, uint b) internal pure returns (uint c) {
        c = a * b;
        require(a == 0 || c / a == b);
    }
    function div(uint a, uint b) internal pure returns (uint c) {
        require(b > 0);
        c = a / b;
    }
} 

contract Ownable {
    address public owner;

    constructor() public{
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        if(newOwner != address(0)) {
            owner = newOwner;
        }
    }
}

contract TwitchBet is Ownable {
    using SafeMath for uint256;
    
    // @dev Describes the state of a round
    // JOIN - Started when the round begins. Participants may make bets duing this time. 
    // GAMING - Started when the admin ends the JOIN phase. The only actions allowed during this phase are refunding or declaring the winner
    // CLOSED - Started when the admin refunds or declares a winner. Funds have been disbursed and no further actions are permitted
    enum State {JOIN, GAMING, CLOSED}

    // @dev An instance of an event on which participants can make bets.
    struct Round {
        // Creator of the round, most likely the streamer
        address payable admin;
        // Optional amount set by the admin that gets split among the winners in addition to the normal payout
        uint256 reward;
        // Doesn't do anything right now
        uint256 timeLimit;
        // Total amount that has been bet for this round
        uint256 totalBet;
        // The current state of this round
        State state;
    }
    
    // @dev One of the possible outcomes of a round
    struct Outcome {
        // Is this a valid outcome? (May not be necessary, used because outcomes are stored in a mapping)
        bool valid;
        // Mapping from addresses of bettors to the amount bet
        mapping(address => uint256) bets;
        // Array of users who have placed bets, used when refunding and awarding winners
        address payable[] bettors;
        // Tthe total amount bet on this outcome, used to calculate the amount to award winners
        uint256 totalBet;
    }
    
    ////////////////////////////////////////////////////////////////
    // Contract Owner Functions
    ////////////////////////////////////////////////////////////////

    // Array of all rounds created
    Round[] public rounds;
    // Mapping from round id to mapping of outcome name to outcome
    mapping(uint256 => mapping(bytes32 => Outcome)) public outcomes;
    // Mapping of found id to array of possible outcome names
    mapping(uint256 => bytes32[]) public outcomeNames;
    // The number of rounds created so far. This value is used when creating a new round
    uint256 public roundIndex = 0;
    // The minimum amount participants may bet on an outcome
    uint256 public minBet;
    // The profit this contract has made so far, minus any amount withdrawn by the contract owner
    uint256 public balance = 0;
    
    event contractUpdated();
    event roundUpdated(uint256 id);
    event callBackResponse(uint256 queryId, string competitionId, string finished, string winner);
    
    ////////////////////////////////////////////////////////////////
    // Contract Owner Functions
    ////////////////////////////////////////////////////////////////

    // @dev constructor for this contract, hooks constract up to the zap oracle endpoint for queries
    constructor(uint _minBet) public{
        minBet = _minBet;
    }

    // @dev Update the minimum bet
    function setMinBet(uint256 _minBet) public onlyOwner {
        minBet = _minBet;
        emit contractUpdated();
    }

    // @dev Sends the profits accumulated by the contract to the contract owner
    function withdraw() public onlyOwner {
        msg.sender.transfer(balance);
        balance = 0;
        
        emit contractUpdated();
    }

    ////////////////////////////////////////////////////////////////
    // Creation Function
    ////////////////////////////////////////////////////////////////

    // @dev Creates and begins a new round, most likely initiated by the streamer
    // @param _outcomes - an array of possible outcomes
    // @param _reward - an optional starting value that gets distributed amongst winners, servers as an incentive to participate
    // @param _timeLimit - doesn't do anything yet
    function createRound(bytes32[] memory _outcomes, uint256 _reward, uint256 _timeLimit) public payable returns (uint256){
        require(_outcomes.length > 0, "Must have at least one outcome");
        require(msg.value == _reward, "Reward must be submitted when creating bounty");
        require(_timeLimit > now, "Time Limit has already passed");
        
        Round memory newRound = Round(
            msg.sender,     // admin
            _reward,        // reward
            _timeLimit,     // timeLimit
            _reward,        // totalBet, init to admin's reward
            State.JOIN      // state
        );
        
        // May not be necessary
        for (uint i=0; i<_outcomes.length; i++) {
            outcomes[roundIndex][_outcomes[i]].valid = true;
        }
        
        outcomeNames[roundIndex] = _outcomes;
        rounds.push(newRound);
        roundIndex++;
        
        emit roundUpdated(roundIndex - 1);
        return roundIndex - 1;
    }

    ////////////////////////////////////////////////////////////////
    // Getter Functions
    ////////////////////////////////////////////////////////////////
    function getRound(uint256 _id) external view returns(
        address payable admin,
        uint256 reward,
        uint256 timeLimit,
        uint256 totalBet,
        State state
        
    ){
        Round storage currRound = rounds[_id];
        
        admin = currRound.admin;
        reward = currRound.reward;
        timeLimit = currRound.timeLimit;
        totalBet = currRound.totalBet;
        state = currRound.state;
    }
    
    ////////////////////////////////////////////////////////////////
    // Admin Functions
    ////////////////////////////////////////////////////////////////

    // @dev Throws function called by anyone other than the round admin
    // @param _id - id of the round
    modifier onlyAdmin(uint256 _id) {
        require (rounds[_id].admin == msg.sender, "Msg.sender is not a admin in this round");
        _;
    }
    
    // @dev Ends the JOIN phase and enter the GAMING phase
    // @param _id - id of the round
    function endJoinPhase(uint256 _id) external payable onlyAdmin(_id) {
        require(rounds[_id].state == State.GAMING, "The round is not in the GAMING phase");

        rounds[_id].state = State.GAMING;
        
        emit roundUpdated(_id);
    }
    

    // @dev Refunds the reward and all bets made to their respective senders for the specified round
    // @param _id - id of the round
    function refundAll(uint256 _id) external onlyAdmin(_id) {
        Round storage currRound = rounds[_id];
        
        // require(currBounty.timeLimit > now, "You must wait for the time limit to pass");
        require(currRound.state == State.GAMING, "The round is not in the GAMING phase");
        
        currRound.admin.transfer(currRound.reward);
        for(uint i = 0; i < outcomeNames[_id].length; i++) {
            Outcome storage currOutcome = outcomes[_id][outcomeNames[_id][i]];
            for(uint j = 0; j < currOutcome.bettors.length; j++) {
                currOutcome.bettors[j].transfer(
                    currOutcome.bets[currOutcome.bettors[j]]
                );
            }
        }
        currRound.state = State.CLOSED;
        
        emit roundUpdated(_id);
    }

    // @dev The round admin specifies the outcome of the event. All bettors that bet for this outcome are rewarded
    // depdending on the amount they bet for this outcome. The round is CLOSED.
    // @param _id - id of the round
    // @param _outcome - the outcome that occurred.
    function declareWinner(uint256 _id, bytes32 _outcome) external onlyAdmin(_id) {
        Round storage currRound = rounds[_id];
        Outcome storage currOutcome = outcomes[_id][_outcome];

        // require(currBounty.timeLimit > now, "You must wait for the time limit to pass")
        require(currRound.state == State.GAMING, "The round is not in the GAMING phase");
        require(currOutcome.valid == true, "The given outcome is not valid for this round");
        
        uint256 roundTotal = currRound.totalBet; uint256 outcomeTotal = currOutcome.totalBet;
        for(uint i = 0; i < currOutcome.bettors.length; i++) {
            currOutcome.bettors[i].transfer(
                currOutcome.bets[currOutcome.bettors[i]].mul(roundTotal).div(outcomeTotal)
            );
        }
        currRound.state = State.CLOSED;
        
        emit roundUpdated(_id);
    }
    
    ////////////////////////////////////////////////////////////////
    // Bettor Functions
    ////////////////////////////////////////////////////////////////

    // @dev The bettor specifies the outcome they wish to bet on along with an amount.
    // Bettors may make multiple bets even on different outcomes. If a bettor has already bet on this outcome
    // their bet for the outcome is increased by the amount being bet.
    // @param _id - id of the round
    // @param _outcome - the outcome being bet on
    // @param _amount - amount the bettor wishes to bet on the outcome
    function bet(uint256 _id, bytes32 _outcome, uint256 _amount) external {
        Round storage currRound = rounds[_id];
        Outcome storage currOutcome = outcomes[_id][_outcome];        
        
        require(currOutcome.valid == true, "The given outcome is not valid for this round");
        require(currRound.state == State.JOIN, "The round is not in the JOIN phase");
        require(_amount >= minBet, "The given bet amount is below the minBet");
        
        if(currOutcome.bets[msg.sender] == 0) {
            currOutcome.bettors.push(msg.sender);
        }
        currOutcome.bets[msg.sender] = currOutcome.bets[msg.sender].add(_amount);
        currOutcome.totalBet = currOutcome.totalBet.add(_amount);
        currRound.totalBet = currRound.totalBet.add(_amount);
        
        emit roundUpdated(_id);
    }
}