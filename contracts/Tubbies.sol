//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./MultisigOwnable.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "./ERC721A.sol";

/*
:::::::::::::::::::::::::::::ヽヽヽヽ:::::::::::::::::::::::::::::::::::::::::::::::::::::::
::::::::::::::::☆:::::::.:::::::::ヽヽヽヽヽ:::::::::::::::::::::::::::::::::::::::::::::::::
::::::::::::::::::::::,'  ヽ.::::::::ヽヽヽ::::::::,.::::::::::::::::::::::::::::::::::::::::
:::::::::::::::::。::/       ヽ:::::::::ヽヽ ::: ／   ヽ:::::::☆:::::::::::::☆::::::::☆::::::
::::::::::::::::::/           ヽ:::::::::☆::/         ヽ::::::::::::::::::::::::::::::::::::
::::::::::::::::;'              ｀--ｰｰｰｰｰ-く .         ',:::::::::::::::::::::::::::::::::
:::::::::☆:::::/                                       ',:::::::::::::::::::::::::::::::::
::::::::::::::/                                          ,:::::::::::::::::。:::::::::::::
:::::::::::::/                                            ,::::::::::::::。::::::::::::::::
::::::::::::;'                                            ::::::。:::::::::::::::::::::::::
:::。:::::: /                    , ＿＿＿＿＿＿             j::::::::::::::。::::::::::::::::
:::::::::: j               ' ´                   ｀ ヽ.      ,:::::::::::。::::::::::::::::::
::::::::::!              ´                           ヽ      ,:::::::::☆:::::::::::::::::::
::::::::: !             ´      ＿                ＿   ヽ     !::::::::::::::::::::::::::::::
::::::::: !            |  γ  =（   ヽ         : ' =::（ ヽ|     !:::::::::::::::::::::::::::::
::::::::: !            | 〈 ん:::☆:j j       ! ん:☆:::ﾊ       ::::::::::::::::::::::::::::::
::::::::: !            |  弋:::::.ﾉ ﾉ        ヾ:::::ﾉ ﾉ |     ::::::::::::::::::::::::::::::
:::::::::::'           |    ゝ  -  '     人    -    '  ﾉ     j::::::::::::::::::::::::::::::
:::::::::::,            ヽ                            ,     j::::☆::::::::::::::::::::::::::
::::::::::::,            ' ､                      , ／     ﾉ::::::::::::::::::::::::::::::::
::::::::::::::＼             ｰ--------------- '         ,':::::::::::::::::::::::::::::::::
::::☆:::::::::::ヽ                                    ／:::::::::::::::::::::::::::::::::::
:::::::::::::::::::7                :::::::::::::::＜::::::::::::::::::::::::::::::::::::::
:::::::::::::::::::r´                   :::::::::::::ヽ::::::::::::::::::::::::::::::::::::
::::::::::::::::::/                               :::::ヽ::::::::::::::::::::::::::::::::::
*/

// IMPORTANT: _burn() must never be called
contract Tubbies is ERC721A, MultisigOwnable, VRFConsumerBase {
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
        ERC721A("Tubby Cats", "TUBBY")
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

    function toBytes32(address addr) pure internal returns (bytes32){
        return bytes32(uint256(uint160(addr)));
    }

    // CAUTION: Never introduce any kind of batch processing for mint() or mintFromSale() since then people can
    // execute the same bug that appeared on sushi's bitDAO auction
    // There are some issues with merkle trees such as pre-image attacks or possibly duplicated leaves on
    // unbalanced trees, but here we protect against them by checking against msg.sender and only allowing each account to claim once
    // See https://github.com/miguelmota/merkletreejs#notes for more info
    mapping(address=>bool) public claimed;
    function mint(bytes32[] calldata _merkleProof) public payable {
        require(MerkleProof.verify(_merkleProof, merkleRoot, toBytes32(msg.sender)) == true, "wrong merkle proof");
        require(claimed[msg.sender] == false, "already claimed");
        claimed[msg.sender] = true;
        require(msg.value == 0.1 ether, "wrong payment");
        _mint(msg.sender, 1, '', false);
        require(totalSupply() <= TOKEN_LIMIT, "limit reached");
    }

    function mintFromSale(uint tubbiesToMint) public payable {
        require(block.timestamp > startSaleTimestamp, "Public sale hasn't started yet");
        require(tubbiesToMint <= 5, "Only up to 5 tubbies can be minted at once");
        uint cost;
        unchecked {
            cost = tubbiesToMint * 0.1 ether;
        }
        require(msg.value == cost, "wrong payment");
        _mint(msg.sender, tubbiesToMint, '', false);
        require(totalSupply() <= TOKEN_LIMIT, "limit reached");
    }

    // RANDOMIZATION

    mapping(bytes32 => uint) public requestIdToBatch;
    mapping(uint => uint8) public batchStatus; // 0 -> unrequested, 1 -> requested, 2 -> received
    // Can be made callable by everyone but restricting to onlyRealOwner for extra security
    // batchNumber belongs to [0, TOKEN_LIMIT/REVEAL_BATCH_SIZE]
    // if fee is incorrect chainlink's coordinator will just revert the tx so it's good
    mapping(uint => bytes32) public batchToSeedRequest; // Just for testing TODO delete
    function requestRandomSeed(uint batchNumber, uint s_fee) public onlyRealOwner returns (bytes32 requestId) {
        require(totalSupply() >= (batchNumber + 1) * REVEAL_BATCH_SIZE);

        // checking LINK balance
        require(IERC20(linkToken).balanceOf(address(this)) >= s_fee, "Not enough LINK to pay fee");

        require(batchStatus[batchNumber] == 0, "Already requested");
        // requesting randomness
        requestId = requestRandomness(s_keyHash, s_fee);

        // storing requestId
        requestIdToBatch[requestId] = batchNumber;
        batchStatus[batchNumber] = 1;
        batchToSeedRequest[batchNumber] = requestId; //TODO delete
    }

    mapping(uint => uint) public batchToSeed;
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        uint batchNumber = requestIdToBatch[requestId];
        // not perfectly random since the folding doesn't match bounds perfectly, but difference is small
        batchToSeed[batchNumber] = randomness % (TOKEN_LIMIT - (batchNumber*REVEAL_BATCH_SIZE));
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

    struct Range{
        int128 start;
        int128 end;
    }

    // Forked from openzeppelin
    /**
     * @dev Returns the largest of two numbers.
     */
    function max(int128 a, int128 b) internal pure returns (int128) {
        return a >= b ? a : b;
    }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(int128 a, int128 b) internal pure returns (int128) {
        return a < b ? a : b;
    }

    uint constant RANGE_LENGTH = (TOKEN_LIMIT/REVEAL_BATCH_SIZE)*2;
    int128 constant intTOKEN_LIMIT = int128(int(TOKEN_LIMIT));

    // ranges include the start but not the end [start, end)
    function addRange(Range[RANGE_LENGTH] memory ranges, int128 start, int128 end, uint lastIndex) pure private returns (uint) {
        uint positionToAssume = lastIndex;
        for(uint j=0; j<lastIndex; j++){
            int128 rangeStart = ranges[j].start;
            int128 rangeEnd = ranges[j].end;
            if(start < rangeStart && positionToAssume == lastIndex){
                positionToAssume = j;
            }
            if(
                (start < rangeStart && end > rangeStart) ||
                (rangeStart <= start &&  end <= rangeEnd) ||
                (start < rangeEnd && end > rangeEnd)
            ){
                int128 length = end-start;
                start = min(start, rangeStart);
                end = start + length + (rangeEnd-rangeStart);
                ranges[j] = Range(-1,-1); // Delete
            }
        }
        for(uint pos = lastIndex; pos > positionToAssume; pos--){
            ranges[pos] = ranges[pos-1];
        }
        ranges[positionToAssume] = Range(start, min(end, intTOKEN_LIMIT));
        lastIndex++;
        if(end > intTOKEN_LIMIT){
            addRange(ranges, 0, end - intTOKEN_LIMIT, lastIndex);
            lastIndex++;
        }
        return lastIndex;
    }

    function buildJumps(uint lastBatch) view private returns (Range[RANGE_LENGTH] memory) {
        Range[RANGE_LENGTH] memory ranges;
        uint lastIndex = 0;
        for(uint i=0; i<lastBatch; i++){
            int128 start = int128(int(getFreeTokenId(batchToSeed[i], ranges)));
            int128 end = start + int128(int(REVEAL_BATCH_SIZE));
            lastIndex = addRange(ranges, start, end, lastIndex);
        }
        return ranges;
    }

    function getShuffledTokenId(uint startId, uint batch) view private returns (uint) {
        Range[RANGE_LENGTH] memory ranges = buildJumps(batch);
        uint positionsToMove = (startId % REVEAL_BATCH_SIZE) + batchToSeed[batch];
        return getFreeTokenId(positionsToMove, ranges);
    }

    function getFreeTokenId(uint positionsToMoveStart, Range[RANGE_LENGTH] memory ranges) pure private returns (uint) {
        int128 positionsToMove = int128(int(positionsToMoveStart));
        int128 id = 0;

        for(uint round = 0; round<2; round++){
            for(uint i=0; i<RANGE_LENGTH; i++){
                int128 start = ranges[i].start;
                int128 end = ranges[i].end;
                if(id < start){
                    int128 finalId = id + positionsToMove;
                    if(finalId < start){
                        return uint(uint128(finalId));
                    } else {
                        positionsToMove -= start - id;
                        id = end;
                    }
                } else if(id < end){
                    id = end;
                }
            }
            if((id + positionsToMove) >= intTOKEN_LIMIT){
                positionsToMove -= intTOKEN_LIMIT - id;
                id = 0;
            }
        }
        return uint(uint128(id + positionsToMove));
    }
}
