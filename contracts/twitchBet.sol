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

// Open Zeppelin
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

// Used to convert between variable types, mostly to match the query and callback functions
contract TypeConverter {
    function bytesToBytes32(bytes memory source) internal pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }

        assembly {
            result := mload(add(source, 32))
        }
    }
  
    //Oracalize
    function stringToAddress(string memory _a) internal pure returns (address _parsedAddress) {
        bytes memory tmp = bytes(_a);
        uint160 iaddr = 0;
        uint160 b1;
        uint160 b2;
        for (uint i = 2; i < 2 + 2 * 20; i += 2) {
            iaddr *= 256;
            b1 = uint160(uint8(tmp[i]));
            b2 = uint160(uint8(tmp[i + 1]));
            if ((b1 >= 97) && (b1 <= 102)) {
                b1 -= 87;
            } else if ((b1 >= 65) && (b1 <= 70)) {
                b1 -= 55;
            } else if ((b1 >= 48) && (b1 <= 57)) {
                b1 -= 48;
            }
            if ((b2 >= 97) && (b2 <= 102)) {
                b2 -= 87;
            } else if ((b2 >= 65) && (b2 <= 70)) {
                b2 -= 55;
            } else if ((b2 >= 48) && (b2 <= 57)) {
                b2 -= 48;
            }
            iaddr += (b1 * 16 + b2);
        }
        return address(iaddr);
    }

    // The Officious BokkyPooBah
    function stringToUint(string memory s) internal pure returns (uint result) {
        bytes memory b = bytes(s);
        uint i;
        result = 0;
        for (i = 0; i < b.length; i++) {
            uint c = uint256(uint8(b[i]));
            if (c >= 48 && c <= 57) {
                result = result * 10 + (c - 48);
            }
        }
    }
    
    // pipermerriam
    function uintToBytes(uint v) internal pure returns (bytes32 ret) {
        if (v == 0) {
            ret = '0';
        }
        else {
            while (v > 0) {
                ret = bytes32(uint(ret) / (2 ** 8));
                ret |= bytes32(((v % 10) + 48) * 2 ** (8 * 31));
                v /= 10;
            }
        }
        return ret;
    }
}

// Zap contracts's methods that subscriber can call knowing the addresses
contract ZapBridge{
    function getContract(string memory contractName) public view returns (address); //coordinator
    function bond(address provider ,bytes32 endpoint, uint256 dots) public;
    function unbond(address provider ,bytes32 endpoint, uint256 dots) public;
    function calcZapForDots(address provider, bytes32 endpoint, uint256 dots) external view returns (uint256); //bondage
    function delegateBond(address holderAddress, address oracleAddress, bytes32 endpoint, uint256 numDots) external returns (uint256 boundZap); //bondage
    function query(address provider, string calldata queryString, bytes32 endpoint, bytes32[] calldata params) external returns (uint256); //dispatch
    function approve(address bondage, uint256 amount) public returns (bool); // Zap Token
}

// Interface for Subscribing to a Zap Oracle
contract Subscriber {

    ZapBridge public coordinator;
    address provider;
    bytes32 endpoint;
    uint256 query_id;
    string[] public response;

    //Coordinator contract is one single contract that knows all other Zap contract addresses
    constructor(address _coordinator, address _provider, bytes32 _endpoint) public{
        coordinator = ZapBridge(_coordinator);
        provider = _provider;
        endpoint = _endpoint;
    }

    //This function call can be skipped if owner approve and delegateBond for this contract
    function approve(uint256 amount) public returns (bool){
      address ZapTokenAddress = coordinator.getContract("ZAP_TOKEN");
      address BondageAddress = coordinator.getContract("BONDAGE");
      return ZapBridge(ZapTokenAddress).approve(BondageAddress,amount);
    }

    //This function call can be ommitted if owner call delegateBond directly to Bondage contract
    //Contract has to hold enough zap approved
    function bond(uint256 dots) public{
        address BondageAddress = coordinator.getContract("BONDAGE");
        return ZapBridge(BondageAddress).bond(provider,endpoint,dots);
    }

    //This function call can be ommitted if owner call delegateBond directly to Bondage
    function unbond(uint256 dots) public{
        address BondageAddress = coordinator.getContract("BONDAGE");
        return ZapBridge(BondageAddress).bond(provider,endpoint,dots);
    }
}

contract TwitchBet is Ownable, Subscriber, TypeConverter {
    using SafeMath for uint256;
    
    // @dev Describes the state of a round
    // JOIN - Started when the round begins. Participants may make bets duing this time. 
    // GAMING - Started when the admin ends the JOIN phase. The only actions allowed during this phase are refuding or declaring the winner
    // CLOSED - Started when the admin refunds or declares a winner. Funds have been disbursed and no further actions are permitted
    enum State {JOIN, GAMING, CLOSED};

    // @dev An instance of an event on which participants can make bets.
    // admin - creator of the round, most likely the streamer
    // reward - optional amount set by the admin that gets split among the winners in addition to the normal payout
    // timeLimit - doesn't do anything right now
    // queryPrice - doesn't do anything right now
    // state - the current state of the Round
    struct Round {
        address payable admin;
        uint256 reward;
        uint256 timeLimit;
        uint256 queryPrice;
        uint256 totalBet;
        State state;
    }
    
    // @dev One of the possible outcomes of a round
    // valid - is this a valid outcome? (May not be necessary, used because outcomes are stored in a mapping)
    // bets - mapping from addresses of bettors to the amount bet
    // bettors - array of users who have placed bets, used when refunding and awarding winners
    // totalBet - the total amount bet on this outcome, used to calculate the amount to award winners
    struct Outcome {
        bool valid;
        mapping(address payable => uint256) bets;
        address[] bettors;
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
    constructor(uint _minBet, uint256 _queryPrice, address _coordinator, address _provider, bytes32 _endpoint) Subscriber(_coordinator,_provider, _endpoint) public{
        minBet = _minBet;
        queryPrice = _queryPrice;
    }

    // @dev Update the minimum bet
    function setMinBet(uint256 _minBet) public onlyOwner {
        minBet = _minBet;
        emit contractUpdated();
    }

    // @dev Sends the profits accumulated by the contract to the contract owner
    function withdraw() public onlyOwner {
        msg.sender.send(this.balance);
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
        require(outcomes.length > 0, "Must have at least one outcome");
        require(msg.value == _reward, "Reward must be submitted when creating bounty");
        require(_timeLimit > now, "Time Limit has already passed");
        
        Round memory newRound = Round(
            msg.sender,  // admin
            _reward,
            _timeLimit,
            queryPrice,  // save current query price
            _reward,  // totalBet, init to admin's reward
            State.JOIN  // state
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
        uint256 maxBet,
        uint256 queryPrice, 
        uint256 totalBet,
        State state,
        bytes32[] outcomeNames
        
    ){
        Round storage currRound = rounds[_id];
        
        admin = currRound.admin;
        reward = currRound.reward;
        timeLimit = currRound.timeLimit;
        maxBet = currRound.maxBet;
        queryPrice = currRound.queryPrice;
        totalBet = currRound.totalBet;
        state = currRound.state;
        outcomeNames = outcomeNames[__id];
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
    
    // @dev Increases the base rewaard of the round
    // @param _id - id of the round
    // @param _increase - amount the reward is increased by
    function increaseReward(uint256 _id, uint256 _increase) external payable onlyAdmin(_id) {
        Round storage currRound = rounds[_id];
        
        require(_newReward > currRound.reward, "Reward must be greater than previous reward.");
        require(msg.value == increase), "Difference must be submitted when changing reward");
        currRound.reward = currRound.reward.add(increase);
        currRound.totalBet = currRound.totalBet.add(increase);
        
        emit roundUpdated(_id);
    }
    
    // @dev Increases the time limit for the round
    // @param _id - id of the round
    // @param _newTimeLimit - time that the time limit will be set to
    function increaseTimeLimit(uint256 _id, uint256 _newTimeLimit) external payable onlyAdmin(_id) {
        Round storage currRound = rounds[_id];
        
        require(_newTimeLimit > currRound.timeLimit, "Time Limit must be later than previous time limit.");
        
        currRound.timeLimit = _newTimeLimit;
        currRound.queryPrice = queryPrice;  // Set query price to most recent
        
        emit roundUpdated(_id);
    }
    
    // @dev Ends the JOIN phase and enter the GAMING phase
    // @param _id - id of the round
    function endJoinPhase(uint256 _id) external payable onlyAdmin(_id) {
        rounds[_id].state = State.GAMING;
        
        emit roundUpdated(_id);
    }
    

    // @dev Refunds the reward and all bets made to their respective senders for the specified round
    // @param _id - id of the round
    function refundAll(uint256 _id) external onlyAdmin(_id) {
        Round storage currRound = rounds[_id];
        
        // require(currBounty.timeLimit > now, "You must wait for the time limit to pass");
        
        currRound.admin.send(currRound.reward);
        for(uint i = 0; i < outcomeNames[_id].length; i++) {
            Outcome storage currOutcome = outcomeNames[_id][i];
            for(uint j = 0; j < currOutcome.bettors.length; j++) {
                currOutcome.bettors[j].send(
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
        Outcome storage currOutcome = outcomes[_id][_outcome]

        // require(currBounty.timeLimit > now, "You must wait for the time limit to pass");
        require(currOutcome.valid == true, "The given outcome is not valid for this round");
        
        uint256 roundTotal = currRound.totalBet, outcomeTotal = currOutcome.totalBet;
        for(uint i = 0; i < currOutcome.bettors.length; i++) {
            currOutcome.bettors[i].send(
                currOutcome.bets[currOutcome.bettors[i]].mul(roundTotal).div(outomeTotal);
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
            currRound.bettors.push(msg.sender);
        }
        currOutcome.bets[msg.sender] = currOutcome.bets[msg.sender].add(_amount);
        currOutcome.totalBet = currOutcome.totalbets.add(_amount);
        currRound.totalBet = currRound.totalBet.add(_amount);
        
        emit roundUpdated(_id);
    }
}