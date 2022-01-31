const { ethers } = require("hardhat");

async function getContract(merkleRoot){
    const [signer] = await ethers.getSigners();
    const Tubbies = await hre.ethers.getContractFactory("Tubbies");
    const tubbies = await Tubbies.deploy(merkleRoot);
    await tubbies.deployed();
    return {tubbies, signer}
}

module.exports={
    getContract
}