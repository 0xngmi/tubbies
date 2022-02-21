const { MerkleTree } = require('merkletreejs')
const keccak256 = require('keccak256')
const wl = require('./wl.json')
const fs = require('fs');

function paddedBuffer(addr){
    const buf = Buffer.from(addr.substr(2).padStart(32*2, "0"), "hex")
    return Buffer.concat([buf]);
}

async function main() {
    const tree = new MerkleTree(wl.map(x => paddedBuffer(x)), keccak256, { sort: true })
    const proofs = {}
    for(const address of wl){
        const leaf = paddedBuffer(address)
        const proof = tree.getHexProof(leaf)
        proofs[address]=proof
    }
    fs.writeFileSync("proofs.json", JSON.stringify(proofs))
}

main()