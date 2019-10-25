pragma solidity 0.4.24;
pragma experimental ABIEncoderV2;

import "https://github.com/thodges-gh/chainlink/evm/contracts/ChainlinkClient.sol";
import "https://github.com/thodges-gh/chainlink/evm/contracts/vendor/Ownable.sol";
/*
Basic info to test node
MHRNUJCVDB4J7TF7
0x9B4019D3b0F29F4A840392960b249c3AD0C5e073
0xa0305333E22Aa2Ef3c624c27CE9ba0d107BA00c5
10
["892be77a8e7c4b4f988ed7e53d07229a","892be77a8e7c4b4f988ed7e53d07229a","892be77a8e7c4b4f988ed7e53d07229a","892be77a8e7c4b4f988ed7e53d07229a","892be77a8e7c4b4f988ed7e53d07229a"]
["0x0D31C381c84d94292C07ec03D6FeE0c1bD6e15c1","0x0D31C381c84d94292C07ec03D6FeE0c1bD6e15c1","0x0D31C381c84d94292C07ec03D6FeE0c1bD6e15c1","0x0D31C381c84d94292C07ec03D6FeE0c1bD6e15c1","0x0D31C381c84d94292C07ec03D6FeE0c1bD6e15c1"]

*/

//Proxy Contract to test functions without Link Interferance
contract ChainPal is ChainlinkClient{

    //Set the payment as one Oracle time the amount of link the contract has I Believe?
    uint256 constant private ORACLE_PAYMENT = 1 * LINK;
    bool public released;
    uint8 public trueCount;
    uint8 public falseCount;
    //These must all be set on creation
    string public invoiceID;
    address public sellerAddress;
    address public buyerAddress;
    uint256 public amount;
    uint256 public deploymentTime;

    event successNodeResponse(
        bool success
    );

    //Arrays 1:1 of Oracales and the corresponding Jobs IDs in those oracles
    string[] public jobIds;
    address[] public oracles;
    constructor(
        string _invoiceID,
        address  _sellerAddress,
        address  _buyerAddress,
        uint256  _amount,
        string[] _jobIds,
        address[] _oracles
    )public payable{
        deploymentTime = block.timestamp;
        trueCount = 0;
        falseCount = 0;
        released = false;
        invoiceID = _invoiceID;
        sellerAddress = _sellerAddress;
        buyerAddress = _buyerAddress;
        amount = _amount;
        jobIds = _jobIds;
        oracles = _oracles;
        setPublicChainlinkToken();
    }

    //modifier to only allow buyers to access functions
    modifier buyerSeller(){
        require(sellerAddress == msg.sender || buyerAddress == msg.sender,"Unauthorised , must be Buyer");
        _;
    }

    //Might Encounter ORACLE_PAYMENT problems with more than one oracle
    //Needs more testing
    function requestConfirmations()
    public
    {
        require(buyerAddress == msg.sender,"Unauthorised , must be Buyer");
        //Reset them to 0 to be able to safely re-run the oracles
        trueCount = 0;
        falseCount = 0;

        //Loop to iterate through all the responses from different nodes
        for(uint i = 0; i < oracles.length; i++){
            Chainlink.Request memory req = buildChainlinkRequest(stringToBytes32(jobIds[i]), this, this.fulfillNodeRequest.selector);
            req.add("invoice_id", invoiceID);
            sendChainlinkRequestTo(oracles[i], req, ORACLE_PAYMENT);
        }

    }

    //This should fulfill the node request
    function fulfillNodeRequest(bytes32 _requestId, bool paid)
    public
    recordChainlinkFulfillment(_requestId)
    {
        //emit NodeRequestFulfilled(_requestId, _output);
        //Append to these to calculate if the funds should be released
        if(paid == true) {
            //Invoice Paid
            trueCount += 1;
        }else if (paid == false){
            //Invoice Not Paid Yet
            falseCount += 1;
        }
        if(trueCount > falseCount){
            released = true;
        }
        successNodeResponse(released);
    }

    //This isnt really needed
    function getChainlinkToken() public view returns (address) {
        return chainlinkTokenAddress();
    }

    //Withdraw ETH from contract
    //Checks on who can withdraw should only be accessible by buyer and seller
    //If enough time has passed seller can withdraw the eth
    //If the checks pass then the buyer can withdraw the eth
    //Maybe modifications that the seller can send the ETH to the buyer.

    function withdrawETH() public{
        if(msg.sender == sellerAddress && released == false && deploymentTime >= block.timestamp + 1 days){
            //Check time
            //If a day has passed then the seller can take back his ETH
            address(msg.sender).transfer(amount);
        }else if (msg.sender == buyerAddress && released == true){
            //Withdraw the ETH from the contract
            address(msg.sender).transfer(amount);
        }else{
            //Do Nothing cause you do not have access to this contract
        }
    }

    //Withdraw Link from contract
    function withdrawLink() public {
        require(buyerAddress == msg.sender,"Unauthorised , must be Buyer");
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        require(link.transfer(msg.sender, link.balanceOf(address(this))), "Unable to transfer");
    }

    function stringToBytes32(string memory source) private pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
          return 0x0;
        }
        //Or this
        assembly{
          result := mload(add(source, 32))
        }
    }
}

contract ChainPalFactory{
    mapping (address => address[]) public LinkPalAddresses;

    event contractDeployed(
        address LinkPalAddress;
    );

    //Need to figure out parameters
    //Link, Address To, ETH amount, Lock that amount of ETH
    //Specify the chainlink node and job too
    function createLinkPal(
        string _invoiceID,
        address  _buyerAddress,
        string[] _jobIds,
        address[] _oracles
    ) public payable{
        //Probably need more requirement checks
        require(msg.value > 0,"No Negative Values are allowed");

        address LinkPalAddress = (new ChainPal).value(address(this).balance)(
             _invoiceID,
            msg.sender,
            _buyerAddress,
            msg.value,
            _jobIds,
            _oracles
        );
        LinkPalAddresses[msg.sender].push(LinkPalAddress);
        //Emit an event here\
        contractDeployed(LinkPalAddress);
    }
}