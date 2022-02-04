//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@rari-capital/solmate/src/tokens/ERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./MultisigOwnable.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract Tubbies is ERC721, MultisigOwnable, VRFConsumerBase {
    using Strings for uint256;

    uint constant public TOKEN_LIMIT = 20e3;
    uint constant public REVEAL_BATCH_SIZE = 1e3;
    bytes32 immutable public merkleRoot;
    uint immutable public startSaleTimestamp;
    string public baseURI;
    string public unrevealedURI;

    // Constants from https://docs.chain.link/docs/vrf-contracts/
    bytes32 immutable private s_keyHash;
    address immutable private linkToken;
    address immutable private linkCoordinator;

    constructor(bytes32 _merkleRoot, string memory _baseURI, string memory _unrevealedURI, bytes32 _s_keyHash, address _linkToken, address _linkCoordinator)
        ERC721("Tubby Cats", "TUBBY")
        VRFConsumerBase(_linkCoordinator, _linkToken)
    {
        linkToken = _linkToken;
        linkCoordinator = _linkCoordinator;
        s_keyHash = _s_keyHash;
        merkleRoot = _merkleRoot;
        startSaleTimestamp = block.timestamp + 2 days;
        unrevealedURI = _unrevealedURI;
        baseURI = _baseURI;
    }

    function setURIs(string memory newBaseURI, string memory newUnrevealedURI) external onlyRealOwner {
        baseURI = newBaseURI;
        unrevealedURI = newUnrevealedURI;
    }

    function retrieveFunds(address payable to) external onlyRealOwner {
        to.transfer(address(this).balance);
    }

    // SALE

    function _mint(address to, uint256 id) internal override {
        // Impossible
        //require(to != address(0), "INVALID_RECIPIENT");
        //require(ownerOf[id] == address(0), "ALREADY_MINTED");

        // Counter overflow is incredibly unrealistic.
        unchecked {
            balanceOf[to]++;
        }

        ownerOf[id] = to;

        emit Transfer(address(0), to, id);
    }

    function toBytes32(address addr) pure internal returns (bytes32){
        return bytes32(uint256(uint160(addr)));
    }

    // CAUTION: Never introduce any kind of batch processing for mint() or mintFromSale() since then people can
    // execute the same bug that appeared on sushi's bitDAO auction
    // There are some issues with merkle trees such as pre-image attacks or possibly duplicated leaves on
    // unbalanced trees, but here we protect against them by checking against msg.sender and only allowing each account to claim once
    // See https://github.com/miguelmota/merkletreejs#notes for more info
    mapping(address=>bool) public claimed;
    uint public totalMinted = 0;
    function mint(bytes32[] calldata _merkleProof) public payable {
        require(MerkleProof.verify(_merkleProof, merkleRoot, toBytes32(msg.sender)) == true, "wrong merkle proof");
        require(claimed[msg.sender] == false, "already claimed");
        claimed[msg.sender] = true;
        require(msg.value == 0.1 ether, "wrong payment");
        _mint(msg.sender, totalMinted);
        unchecked {
            totalMinted++; // Can't overflow
        }
        require(totalMinted <= TOKEN_LIMIT, "limit reached");
    }

    function mintFromSale(uint tubbiesToMint) public payable {
        require(block.timestamp > startSaleTimestamp, "Public sale hasn't started yet");
        require(tubbiesToMint <= 20, "Only up to 20 tubbies can be minted at once");
        uint cost;
        unchecked {
            cost = tubbiesToMint * 0.1 ether;
        }
        require(msg.value == cost, "wrong payment");
        unchecked {
            for(uint i = 0; i<tubbiesToMint; i++){
                _mint(msg.sender, totalMinted);
                totalMinted++; // OPTIMIZE: Use memory variable?
            }
        }
        require(totalMinted <= TOKEN_LIMIT, "limit reached");
    }

    // RANDOMIZATION

    mapping(bytes32 => uint) public requestIdToBatch;
    mapping(uint => uint8) public batchStatus; // 0 -> unrequested, 1 -> requested, 2 -> received
    // Can be made callable by everyone but restricting to onlyRealOwner for extra security
    // batchNumber belongs to [0, TOKEN_LIMIT/REVEAL_BATCH_SIZE]
    // if fee is incorrect chainlink's coordinator will just revert the tx so it's good
    function requestRandomSeed(uint batchNumber, uint s_fee) public onlyRealOwner returns (bytes32 requestId) {
        require(totalMinted >= (batchNumber + 1) * REVEAL_BATCH_SIZE); // TEST: It works on the last mint

        // checking LINK balance
        require(IERC20(linkToken).balanceOf(address(this)) >= s_fee, "Not enough LINK to pay fee");

        require(batchStatus[batchNumber] == 0, "Already requested");
        // requesting randomness
        requestId = requestRandomness(s_keyHash, s_fee);

        // storing requestId
        requestIdToBatch[requestId] = batchNumber;
        batchStatus[batchNumber] = 1;
    }

    mapping(uint => uint) public batchToSeed;
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        uint batchNumber = requestIdToBatch[requestId];
        batchToSeed[batchNumber] = randomness % TOKEN_LIMIT;
        batchStatus[batchNumber] = 2;
    }

    uint lastTokenRevealed = 0;
    function shuffleIndexes(uint batchNumber) public onlyRealOwner{
        require(lastTokenRevealed == (batchNumber * REVEAL_BATCH_SIZE), "batches must be shuffled in order");
        require(batchStatus[batchNumber] == 2, "wait for fulfillRandomness()");
        lastTokenRevealed += REVEAL_BATCH_SIZE;
    }

    // OPTIMIZATION: No need for numbers to be readable, so this could be optimized
    // but gas cost here doesn't matter so we go for the standard approach
    function tokenURI(uint256 id) public view override returns (string memory) {
        if(id > lastTokenRevealed){
            return unrevealedURI;
        } else {
            uint batch = id/REVEAL_BATCH_SIZE;
            return string(abi.encodePacked(baseURI, getShuffledTokenId(id, batch).toString()));
        }
    }

    function getShuffledTokenId(uint id, uint batch) view private returns (uint) {
        uint finalId = id;
        uint randomSeed = batchToSeed[batch];
        finalId = (finalId + randomSeed) % TOKEN_LIMIT;
        bool[TOKEN_LIMIT/REVEAL_BATCH_SIZE] memory checkedBatches;
        for(uint i=0; i<batch; i++){
            for(uint j=0; j<batch; j++){
                if(checkedBatches[j] == false){
                    uint batchSeed = batchToSeed[j];
                    if(batchSeed < finalId && finalId < (batchSeed + REVEAL_BATCH_SIZE)){
                        finalId = (finalId + REVEAL_BATCH_SIZE) % TOKEN_LIMIT;
                        checkedBatches[j] = true;
                    }
                    if(finalId < REVEAL_BATCH_SIZE && batchSeed > (TOKEN_LIMIT - REVEAL_BATCH_SIZE)){
                        uint end = (batchSeed + REVEAL_BATCH_SIZE) % TOKEN_LIMIT;
                        if(finalId < end){
                            finalId = (finalId + REVEAL_BATCH_SIZE) % TOKEN_LIMIT;
                            checkedBatches[j] = true;
                        }
                    }
                }
            }
        }
        return finalId;
    }
}
