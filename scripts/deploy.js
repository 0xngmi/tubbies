const hre = require("hardhat");

async function main() {
  const Tubbies = await hre.ethers.getContractFactory("Tubbies");
  const tubbies = await Tubbies.deploy();

  await tubbies.deployed();

  console.log("Deployed to:", tubbies.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
