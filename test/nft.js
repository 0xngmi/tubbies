const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Tubbies", function () {
  it("works", async function () {
    this.timeout(50000);
    const [accountWithEth] = await ethers.getSigners();
    const Tubbies = await hre.ethers.getContractFactory("Tubbies");
    const tubbies = await Tubbies.deploy();
    await tubbies.deployed();
  });
});