const { expect } = require("chai");
const { ethers } = require("hardhat");
const { getContract, deployMockContract } = require('./utils')

const DAY = 3600*24;
const linkToken = "0x514910771AF9Ca656af840dff83E8264EcF986CA";
const linkCoordinator = "0xf0d54349aDdcf704F77AE15b96510dEA15cb7952";

const MAX_MINT = 5;

async function mint(tubbies, amount){
  const txs = []
  for(let i = 0; i<amount; i+=MAX_MINT){
    txs.push(
      tubbies.mintFromSale(MAX_MINT, {value: ethers.utils.parseEther("0.5")})
    )
  }
  await Promise.all(txs);
}

describe("Shuffling", function () {

  it("public sale only starts after 2 days, and other minting checks", async ()=>{
    const {tubbies} = await getContract({})
    await expect(
      tubbies.mint(["0x89c406c1b181f87a146ae08652844f519eb67cb9ea9cc553afb868c6914800c2"], {value: ethers.utils.parseEther("0.1")})
    ).to.be.revertedWith('wrong merkle proof');
    await expect(
      tubbies.mintFromSale(2, {value: ethers.utils.parseEther("0.2")})
    ).to.be.revertedWith("Public sale hasn't started yet");
    await network.provider.send("evm_increaseTime", [DAY])
    await network.provider.send("evm_mine")
    await expect(
      tubbies.mintFromSale(2, {value: ethers.utils.parseEther("0.2")})
    ).to.be.revertedWith("Public sale hasn't started yet");
    await network.provider.send("evm_increaseTime", [DAY*0.99])
    await network.provider.send("evm_mine")
    await expect(
      tubbies.mintFromSale(2, {value: ethers.utils.parseEther("0.2")})
    ).to.be.revertedWith("Public sale hasn't started yet");
    await network.provider.send("evm_increaseTime", [DAY*0.01])
    await network.provider.send("evm_mine")
    //await tubbies.mintFromSale(2, {value: ethers.utils.parseEther("0.2")})

    await expect(
      tubbies.mintFromSale(6, {value: ethers.utils.parseEther("0.2")})
    ).to.be.revertedWith("Only up to 5 tubbies can be minted at once");

    await expect(
      tubbies.mintFromSale(4, {value: ethers.utils.parseEther("0.2")})
    ).to.be.revertedWith("wrong payment");
  })

  it("max mint", async function () {
    this.timeout(100000);
    const [signer] = await ethers.getSigners();
    // Can't impersonate mainnet contracts because of a weird issue with sending txs
    const mockLink = await deployMockContract("MockLinkToken")
    const mockCoordinator = await deployMockContract("MockChainlinkCoordinator")
    const {tubbies} = await getContract({
      linkToken:mockLink.address,
      linkCoordinator: mockCoordinator.address
    })
    await network.provider.send("evm_increaseTime", [2*DAY])
    await network.provider.send("evm_mine")

    const totalMinted = (await tubbies.totalMinted()).toNumber()
    await mint(tubbies, 1.5e3);
    expect(await tubbies.totalMinted()).to.equal(1500);

    await mockLink.transfer(tubbies.address, ethers.utils.parseEther("2000"))

    await tubbies.requestRandomSeed(0, ethers.utils.parseEther("0.5"))
    const requestId = await tubbies.batchToSeedRequest(0)
    await mockCoordinator.sendRandom(tubbies.address, requestId, 46)
    await tubbies.shuffleIndexes(0)

    await mint(tubbies, 20e3-1.5e3);
    await expect(
      tubbies.mintFromSale(1, {value: ethers.utils.parseEther("0.1")})
    ).to.be.revertedWith("limit reached");
    for(let i=1; i<20; i++){
      await tubbies.requestRandomSeed(i, ethers.utils.parseEther("0.5"))
      const requestId = await tubbies.batchToSeedRequest(i)
      await mockCoordinator.sendRandom(tubbies.address, requestId, 46)
      await tubbies.shuffleIndexes(i)
    }
    console.log("1", await tubbies.tokenURI(2e4-1))
  });
});

/*
await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [linkCoordinator],
    });
    const coordinator = await ethers.provider.getSigner(
      linkCoordinator
    );
const linkTokenContract = new ethers.Contract(
  linkToken,
  [
    "function transfer(address to, uint amount) external"
  ],
  coordinator
)
*/