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

// Copied from CryptoKitties
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

contract BountyFactory is Ownable, Subscriber, TypeConverter {
    using SafeMath for uint256;

    struct Bounty {
        address payable patron;
        address payable winner;
        uint256 reward;
        uint256 startTime;
        uint256 huntTimeLimit;
        uint256 queryPrice;
        mapping(address => bytes32) hunterUsernames;  // maps address to a username
        uint256 id;
    }
    
    // Contract member variables
    Bounty[] public bounties;
    mapping(uint256 => address[]) public hunters;  // hunters array from bounty id
    mapping(uint256 => bytes32[]) public parameters;  // game parameters from bounty id
    uint256 public bountyIndex = 0;
    uint256 public minReward;
    uint256 public queryPrice;
    uint256 public balance = 0;
    
    string public answer;
    
    event bountyUpdated();
    event bountyUpdated(uint256 id);
    event callBackResponse(uint256 _queryId, string _competitionId,  string _finished, string _winner);
    
    /////////////////////////////////
    // Contract Owner Functions
    /////////////////////////////////
    constructor(uint _minReward, uint256 _queryPrice, address _coordinator, address _provider, bytes32 _endpoint) Subscriber(_coordinator,_provider, _endpoint) public{
        minReward = _minReward;
        queryPrice = _queryPrice;
    }

    function setMinReward(uint256 _minReward) public onlyOwner {
        minReward = _minReward;
        emit bountyUpdated();
    }
    
    function setQueryPrice(uint256 _queryPrice) public onlyOwner {
        queryPrice = _queryPrice;
        emit bountyUpdated();
    }

    function withdraw(uint256 _amount) public onlyOwner {
        require(_amount < balance);
        
        balance = balance.sub(_amount);
        msg.sender.transfer(_amount);
    }

    /////////////////////////////////
    // Creation Function
    /////////////////////////////////
    function createBounty(bytes32[] memory _params,uint256 _reward, uint256 _huntTimeLimit) public payable returns (uint256){
        // timelimit requirements
        // gameId requirement?
        // params requirements?
        require(_reward >= minReward, "Reward is below the minimum");
        require(msg.value == _reward, "Reward must be submitted when creating bounty");
        
        Bounty memory newBounty = Bounty(
            msg.sender,             // patron
            address(0),             // winner
            _reward,
            now,                    // startTime
            _huntTimeLimit,
            queryPrice,
            bountyIndex             // id
        );
        
        bounties.push(newBounty);
        bountyIndex++;
        
        parameters[bountyIndex - 1] = _params;
        
        emit bountyUpdated(bountyIndex - 1);
        return bountyIndex - 1;
    }

    /////////////////////////////////
    // Getter Functions
    /////////////////////////////////
    function getBounty(uint256 _id) external view returns(
        address payable patron,
        address payable winner,
        uint256 reward,
        uint256 startTime,
        uint256 huntTimeLimit,
        uint256 thisQueryPrice,
        uint256 numHunters,
        uint256 numParams,
        uint256 id
    ){
        Bounty storage currBounty = bounties[_id];
        
        patron = currBounty.patron;
        winner = currBounty.winner;
        startTime = currBounty.startTime;
        reward = currBounty.reward;
        huntTimeLimit = currBounty.huntTimeLimit;
        thisQueryPrice = currBounty.queryPrice;
        numHunters = hunters[_id].length;
        numParams = parameters[_id].length;
        id = currBounty.id;
    }
    
    function getHunter(uint256 _id, address _hunter) external view returns(bytes32 username) {
        username = bounties[_id].hunterUsernames[_hunter];
    }
    
    function getInProgressBountiesOf (address _user, bool patronOrHunter) external view returns(uint256[] memory) {
        uint256[] memory myBounties  = new uint256[](bountyIndex);
        uint256 numBounties = 0;
        
        if(patronOrHunter) {
            for(uint256 id = 0; id < bountyIndex; id++) {
                Bounty storage currBounty = bounties[id];
                if(currBounty.patron == _user && currBounty.winner != address(0) && currBounty.huntTimeLimit > now) {
                    myBounties[numBounties] = id;
                    numBounties++;
                }
            }
        } else {
            for(uint256 id = 0; id < bountyIndex; id++) {
                Bounty storage currBounty = bounties[id];
                if(currBounty.hunterUsernames[_user] != "" && currBounty.winner != address(0) && currBounty.huntTimeLimit > now) {
                    myBounties[numBounties] = id;
                    numBounties++;
                }
            }
        }
        
        uint256[] memory result  = new uint256[](numBounties);
        for(uint256 i = 0; i < numBounties; i++) {
            result[i] = myBounties[i];
        }
        return result;
    }
    
    function getOverdueBountiesOf (address _user, bool patronOrHunter) external view returns(uint256[] memory) {
        uint256[] memory myBounties  = new uint256[](bountyIndex);
        uint256 numBounties = 0;
        
        if(patronOrHunter) {
            for(uint256 id = 0; id < bountyIndex; id++) {
                Bounty storage currBounty = bounties[id];
                if(currBounty.patron == _user && currBounty.winner == address(0) && currBounty.huntTimeLimit < now) {
                    myBounties[numBounties] = id;
                    numBounties++;
                }
            }
        } else {
            for(uint256 id = 0; id < bountyIndex; id++) {
                Bounty storage currBounty = bounties[id];
                if(currBounty.hunterUsernames[_user] != "" && currBounty.winner == address(0) && currBounty.huntTimeLimit < now) {
                    myBounties[numBounties] = id;
                    numBounties++;
                }
            }
        }
        
        uint256[] memory result  = new uint256[](numBounties);
        for(uint256 i = 0; i < numBounties; i++) {
            result[i] = myBounties[i];
        }
        return result;
    }
    
    function getCompletedBountiesOf (address _user, bool patronOrHunter) external view returns(uint256[] memory) {
        uint256[] memory myBounties  = new uint256[](bountyIndex);
        uint256 numBounties = 0;
        
        if(patronOrHunter) {
            for(uint256 id = 0; id < bountyIndex; id++) {
                Bounty storage currBounty = bounties[id];
                if(currBounty.patron == _user && currBounty.winner != address(0) && currBounty.winner != currBounty.patron) {
                    myBounties[numBounties] = id;
                    numBounties++;
                }
            }
        } else {
            for(uint256 id = 0; id < bountyIndex; id++) {
                Bounty storage currBounty = bounties[id];
                if(currBounty.hunterUsernames[_user] != "" && currBounty.winner == _user) {
                    myBounties[numBounties] = id;
                    numBounties++;
                }
            }
        }
        
        uint256[] memory result  = new uint256[](numBounties);
        for(uint256 i = 0; i < numBounties; i++) {
            result[i] = myBounties[i];
        }
        return result;
    }
    
    function getCanceledBountiesOf (address _patron) external view returns(uint256[] memory) {
        uint256[] memory myBounties  = new uint256[](bountyIndex);
        uint256 numBounties = 0;
        
        for(uint256 id = 0; id < bountyIndex; id++) {
            Bounty storage currBounty = bounties[id];
            if(currBounty.patron == _patron && currBounty.winner != currBounty.patron) {
                myBounties[numBounties] = id;
                numBounties++;
            }
        }
        
        uint256[] memory result  = new uint256[](numBounties);
        for(uint256 i = 0; i < numBounties; i++) {
            result[i] = myBounties[i];
        }
        return result;
    }
    
    function getHuntableBounties(address _hunter) external view returns (uint256[] memory) {
        uint256[] memory myBounties  = new uint256[](bountyIndex);
        uint256 numBounties = 0;
        for(uint256 id = 0; id < bountyIndex; id++) {
            if(
                bounties[id].hunterUsernames[_hunter][0] == 0 && 
                bounties[id].patron != _hunter && bounties[id].winner == address(0) && 
                bounties[id].huntTimeLimit > now
            ) {
                myBounties[numBounties] = id;
                numBounties++;
            }
        }
        uint256[] memory result  = new uint256[](numBounties);
        for(uint256 i = 0; i < numBounties; i++) {
            result[i] = myBounties[i];
        }
        return result;
    }
    
    /////////////////////////////////
    // Patron Functions
    /////////////////////////////////
    modifier onlyPatron(uint256 _id) {
        require (bounties[_id].patron == msg.sender, "Msg.sender is not a hunter in this bounty");
        _;
    }
    
    function increaseBet(uint256 _id, uint256 _newReward) external payable onlyPatron(_id) {
        require(_newReward > bounties[_id].reward, "Reward must be greater than previous reward.");
        require(msg.value == _newReward - bounties[_id].reward, "Difference must be submitted when changing reward");
        bounties[_id].reward = _newReward;
        emit bountyUpdated(_id);
    }
    
    function increaseTimeLimit(uint256 _id, uint256 _newTimeLimit) external payable onlyPatron(_id) {
        Bounty storage currBounty = bounties[_id];
        
        require(_newTimeLimit > currBounty.huntTimeLimit, "Time Limit must be later than previous time limit.");
        
        currBounty.huntTimeLimit = _newTimeLimit;
        currBounty.queryPrice = queryPrice;
        emit bountyUpdated(_id);
    }
    
    function refundBounty(uint256 _id) external onlyPatron(_id) {
        Bounty storage currBounty = bounties[_id];
        
        require(currBounty.winner == address(0), "A winner has already been declared");
        
        require(currBounty.huntTimeLimit < now, "You must wait for the time limit to pass");
        msg.sender.transfer(currBounty.reward);
        currBounty.winner = msg.sender;
        emit bountyUpdated(_id);
    }
    
    
    /////////////////////////////////
    // Hunter Functions
    /////////////////////////////////
    modifier onlyHunters(uint256 _id) {
        require (bounties[_id].hunterUsernames[msg.sender] != "","Msg.sender is not a hunter in this bounty");
        _;
    }
    
    function joinBounty(uint256 _id, bytes32 _username) external {
        Bounty storage currBounty = bounties[_id];        
        
        require(currBounty.hunterUsernames[msg.sender] == "", "Msg.Sender is already a hunter");
        require(msg.sender != currBounty.patron, "The patron cannot be a hunter");
        require(currBounty.winner == address(0), "The bounty already has a winner");
        require(currBounty.huntTimeLimit < now, "The time limit has already passed");
        
        currBounty.hunterUsernames[msg.sender] = _username;
        hunters[_id].push(msg.sender);
        
        emit bountyUpdated(_id);
    }
    
    function claimReward(uint256 _id) external payable{
        Bounty storage currBounty = bounties[_id];
        
        require(currBounty.winner == address(0), "The bounty already has a winner");
        require(currBounty.huntTimeLimit < now, "The time limit has already passed");
        require(msg.value == currBounty.queryPrice, "Msg.value does not match queryPrice");

        balance += queryPrice;
        
        query("Winner", parameters[_id]);
    }
    
    /////////////////////////////////
    // Subscriber Functions
    /////////////////////////////////
    function query(string memory queryString, bytes32[] memory params) internal returns (uint256) {
        address dispatchAddress = coordinator.getContract("DISPATCH");
        query_id = ZapBridge(dispatchAddress).query(provider,queryString,endpoint,params);
        return query_id;
    }


    function callback(uint256 _id, string calldata _bountyId, string calldata _finished,string calldata _winner ) external{
        if(keccak256(abi.encodePacked((_finished))) == keccak256(abi.encodePacked(("True")))) {
            uint256 id = stringToUint(_bountyId);
            address payable winner = address(uint160(stringToAddress(_winner)));
            sendReward(id, winner);
        }
        
        emit callBackResponse(_id, _bountyId,  _finished, _winner);
    }
    
    function sendReward(uint256 _id, address payable _winner) internal {
        Bounty storage currBounty = bounties[_id];
        
        uint256 adminFee = (currBounty.reward.mul(5)).div(100);
        currBounty.winner.transfer(currBounty.reward.sub(adminFee));
        currBounty.winner = _winner;
        balance += adminFee;
        
        emit bountyUpdated(_id);
    }
}