const hre = require("hardhat");
const {buildTreeAndProof} = require('./utils')

async function main() {
  const {root} = buildTreeAndProof([
      "0xcA9B80d1c17cD7551882dE80F34E2E58acE2264D",
      "0x71a15Ac12ee91BF7c83D08506f3a3588143898B5"
  ], "0x71a15Ac12ee91BF7c83D08506f3a3588143898B5")
  const Tubbies = await hre.ethers.getContractFactory("Tubbies");
  const tubbies = await Tubbies.deploy(root, "a", "c", 
    "0x2ed0feb3e7fd2022120aa84fab1945545a9f2ffc9076fd6156fa96eaff4c1311", 
    "0x01BE23585060835E02B77ef475b0Cc51aA1e0709",
    "0xb3dCcb4Cf7a26f6cf6B120Cf5A73875B7BBc655B"
  );

  await tubbies.deployed();
  console.log("Deployed to:", tubbies.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
