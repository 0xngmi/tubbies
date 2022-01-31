const { expect } = require("chai");
const { ethers } = require("hardhat");
const { getContract } = require('./utils')

const { MerkleTree } = require('merkletreejs')
const keccak256 = require('keccak256')

function paddedBuffer(addr){
    const buf = Buffer.from(addr.substr(2).padStart(32*2, "0"), "hex")
    return Buffer.concat([buf]);
}

function buildTreeAndProof(
    leaves=[
        "0x4074bc05a89f1b97b51413b06f7e44f46eae6880",
        "0x1508dcc55173733f14624d98a65b8fac5d93d322",
        "0xb47e3cd837ddf8e4c57f05d70ab865de6e193bbb"
    ],
    addressToGetProof = "0x4074bc05a89f1b97b51413b06f7e44f46eae6880"
) {
    const tree = new MerkleTree(leaves.map(x => paddedBuffer(x)), keccak256, { sort: true })
    const root = tree.getHexRoot()
    const leaf = paddedBuffer(addressToGetProof)
    const proof = tree.getHexProof(leaf)
    return {tree, proof, root, leaf}
}

describe("Merkle tree", function () {
    it("tree is constructed properly", async function () {
        const {tree, proof, root, leaf} = buildTreeAndProof()
        expect(tree.verify(proof, leaf, root)).to.equal(true);
    })

    it("works on-chain too", async function () {
        const [signer] = await ethers.getSigners();
        const leaves = [
            "0x4074bc05a89f1b97b51413b06f7e44f46eae6880",
            "0x1508dcc55173733f14624d98a65b8fac5d93d322",
            signer.address
        ]
        const {root, proof, leaf} = buildTreeAndProof(leaves, signer.address)
        const { tubbies } = await getContract(root)
        await tubbies.mint(proof, {
            value: ethers.utils.parseEther("0.1")
        });
    })
})