const { MerkleTree } = require('merkletreejs')
const keccak256 = require('keccak256')
const wl = require('./wl.json')
const ethers = require('ethers');

function paddedBuffer(addr){
    const buf = Buffer.from(addr.substr(2).padStart(32*2, "0"), "hex")
    return Buffer.concat([buf]);
}

async function mint(addressToMint) {
    const tree = new MerkleTree(wl.map(x => paddedBuffer(x)), keccak256, { sort: true })
    const leaf = paddedBuffer(addressToMint)
    const proof = tree.getHexProof(leaf)
    console.log("proof:", proof)
    /*
    const provider = {}// metamask provider
    const tubbies = new ethers.Contract(
      "0x03babfb394e1933f87aa2c003d6eac950ce60e9b",
      ['function mint(bytes32[] calldata _merkleProof)'],
      provider
    )
    await tubbies.mint(proof, {
        value: ethers.utils.parseEther("0.1"),
    })
    */
}

mint("0xb0d32b53e55f69e1e5d52796bd5428aefd3df08b")
