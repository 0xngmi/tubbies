const { expect } = require("chai");
const { ethers } = require("hardhat");
const { getContract, buildTreeAndProof } = require('../scripts/utils')

describe("Merkle tree", function () {
    it("tree is constructed properly", async function () {
        const {tree, proof, root, leaf} = buildTreeAndProof()
        expect(tree.verify(proof, leaf, root)).to.equal(true);
    })

    it("works on-chain too", async function () {
        const [signer, attacker] = await ethers.getSigners();
        const leaves = [
            "0x4074bc05a89f1b97b51413b06f7e44f46eae6880",
            "0x1508dcc55173733f14624d98a65b8fac5d93d322",
            signer.address
        ]
        const {root, proof, leaf} = buildTreeAndProof(leaves, signer.address)
        const { tubbies } = await getContract({merkleRoot:root})
        expect(await tubbies.balanceOf(signer.address)).to.equal(0)
        await expect(
            tubbies.mint(proof, {value: ethers.utils.parseEther("0.2")})
        ).to.be.revertedWith('wrong payment');
        await expect(
            tubbies.mint(proof)
        ).to.be.revertedWith('wrong payment');
        await tubbies.mint(proof, {
            value: ethers.utils.parseEther("0.1")
        });
        expect(await tubbies.balanceOf(signer.address)).to.equal(1)
        await expect(
            tubbies.mint(proof, {
                value: ethers.utils.parseEther("0.1")
            })
        ).to.be.revertedWith('already claimed');
        await expect(
            tubbies.connect(attacker).mint(proof, {value: ethers.utils.parseEther("0.1")})
        ).to.be.revertedWith('wrong merkle proof');
    })
})