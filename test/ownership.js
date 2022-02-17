const { expect } = require("chai");
const { ethers } = require("hardhat");
const { getContract } = require('../scripts/utils')

const msigError = 'MultisigOwnable: caller is not the real owner'

describe("MultisigOwnable", function () {
    it("hierarchical ownership works", async function () {
        const [owner, msig, attacker] = await ethers.getSigners();
        const { tubbies } = await getContract({})
        expect(await tubbies.owner()).to.equal(owner.address)
        expect(await tubbies.realOwner()).to.equal(owner.address)
        await tubbies.transferRealOwnership(msig.address);
        expect(await tubbies.realOwner()).to.equal(msig.address)
        await expect(
            tubbies.connect(owner).retrieveFunds(msig.address)
        ).to.be.revertedWith(msigError);
        await expect(
            tubbies.connect(owner).setParams("b", "c", false, false)
        ).to.be.revertedWith(msigError);
        await expect(
            tubbies.connect(attacker).retrieveFunds(msig.address)
        ).to.be.revertedWith(msigError);
        await tubbies.connect(msig).retrieveFunds(attacker.address)

        await tubbies.connect(msig).transferLowerOwnership(attacker.address)
        expect(await tubbies.owner()).to.equal(attacker.address)

        await expect(
            tubbies.connect(attacker).transferLowerOwnership(attacker.address)
        ).to.be.revertedWith(msigError);
        await expect(
            tubbies.connect(attacker).transferRealOwnership(attacker.address)
        ).to.be.revertedWith(msigError);

        await tubbies.connect(msig).transferRealOwnership(attacker.address)

        expect(await tubbies.realOwner()).to.equal(attacker.address)
        await expect(
            tubbies.connect(msig).retrieveFunds(msig.address)
        ).to.be.revertedWith(msigError);
    })

    it("finalization works", async ()=>{
        const { tubbies } = await getContract({})
        await tubbies.setParams("x", "y", true, true);
        await expect(
            tubbies.setParams("x", "y", true, true)
        ).to.be.revertedWith("final");
    })
})