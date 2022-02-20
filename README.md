# Tubby cats

Commands:
```shell
npx hardhat compile
npm t
npx hardhat run scripts/deploy_rinkeby.js --network rinkeby
npx hardhat verify --network rinkeby 0xCa7cA7BcC765F77339bE2d648BA53ce9c8a262bD "0x98a581b0172678cc040fbfe0a8b8ce4e67c723024e0341181696faffe1a242c0" "a" "c" "0x2ed0feb3e7fd2022120aa84fab1945545a9f2ffc9076fd6156fa96eaff4c1311" "0x01BE23585060835E02B77ef475b0Cc51aA1e0709" "0xb3dCcb4Cf7a26f6cf6B120Cf5A73875B7BBc655B"
```


## Features
- [x] Whitelist
- [x] Multisig super-ownership
- [x] VRF progressive revealing
- [ ] Airdrop

## Tests
- [x] Ownership
- [ ] Deployment on testnet
- [ ] Merkle + full minting

