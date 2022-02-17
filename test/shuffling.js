const { expect } = require("chai");
const { ethers } = require("hardhat");
const { getContract, deployMockContract } = require('../scripts/utils')

const DAY = 3600*24;
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

async function setupForSale(){
  // Can't impersonate mainnet contracts because of a weird issue with sending txs
  const mockLink = await deployMockContract("MockLinkToken")
  const mockCoordinator = await deployMockContract("MockChainlinkCoordinator")
  const {tubbies} = await getContract({
    linkToken:mockLink.address,
    linkCoordinator: mockCoordinator.address
  })
  await network.provider.send("evm_increaseTime", [2*DAY])
  await network.provider.send("evm_mine")
  await mockLink.transfer(tubbies.address, ethers.utils.parseEther("2000"))
  return {mockCoordinator, mockLink, tubbies}
}

async function revealBatch(tubbies, mockCoordinator, i, randomvalue){
  await tubbies.requestRandomSeed(ethers.utils.parseEther("0.5"))
  const requestId = "0x5ca28f7c92f8adc821003b5d761ae77281bb1525e382c7605d9b081262b2d534"; // random bytes32
  await mockCoordinator.sendRandom(tubbies.address, requestId, randomvalue)
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

  /*
    Needs the following changes in BatchReveal.sol or it'll take forever
    TOKEN_LIMIT = 200;
    REVEAL_BATCH_SIZE = 10;
  */
  it("no id is repeated and tokenURIs stay constant", async function () {
    this.timeout(1000000);
    const {mockCoordinator, tubbies} = await setupForSale()

    const TOKEN_LIMIT = await tubbies.TOKEN_LIMIT()
    const REVEAL_BATCH_SIZE = await tubbies.REVEAL_BATCH_SIZE()
    const BATCHES = TOKEN_LIMIT/REVEAL_BATCH_SIZE
    await mint(tubbies, TOKEN_LIMIT);
    const ids = {}
    for(let batch=0; batch<BATCHES; batch++){
      const random =  Math.round(Math.random()*40e3)
      await revealBatch(tubbies, mockCoordinator, batch, random)
      await Promise.all(Array.from(Array((batch+1)*REVEAL_BATCH_SIZE).keys()).map(async i=>{
        const newId = await tubbies.tokenURI(i)
        if(ids[newId] === undefined){
          // new id
          ids[newId] = i
          return
        }
        if(ids[newId] !== i){
          throw new Error(`${i} -> ${newId} repeated`)
        }
      }))
      console.log(batch, ids, random)
    }
  })

  it("max mint", async function () {
    this.timeout(100000);
    const {mockCoordinator, tubbies} = await setupForSale()

    await mint(tubbies, 1.5e3);
    expect(await tubbies.totalSupply()).to.equal(1500);

    await mint(tubbies, 20e3-1.5e3);
    await expect(
      tubbies.mintFromSale(1, {value: ethers.utils.parseEther("0.1")})
    ).to.be.revertedWith("limit reached");
    expect(await tubbies.totalSupply()).to.equal(20e3);

    expect(await tubbies.tokenURI(0)).to.equal("b");
    expect(await tubbies.tokenURI(20e3-1)).to.equal("b");
    const snapshot = await network.provider.send("evm_snapshot")
    for(let i=0; i<20; i++){
      await revealBatch(tubbies, mockCoordinator, i, 46)
    }
    expect(await tubbies.tokenURI(20e3-1)).to.equal("45");
    expect(await tubbies.tokenURI(0)).to.equal("46");
    for(let i=0; i<20e3; i+=500){
      expect(await tubbies.tokenURI(i)).to.equal((i+46).toString());
    }
  });
});