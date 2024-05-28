require("dotenv").config();
const tokenABI = require("./abi/token.json");

const { Web3, Contract } = require("web3");
var web3 = new Web3(process.env.API_URL);

const hre = require("hardhat");
const provider = new hre.ethers.WebSocketProvider(process.env.API_URL);

const dcaABI = require("./artifacts/contracts/DCA.sol/DCA.json").abi;
const dcaAddress = "0xbec49fa140acaa83533fb00a2bb19bddd0290f25"

const token0 = "0x4200000000000000000000000000000000000006"
const token1 = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"

async function main() {
   

    const account = web3.eth.accounts.privateKeyToAccount(process.env.PRIVATE_KEY);
    const ethBalamce = await web3.eth.getBalance(account.address);
    console.log("ETH: ", ethBalamce);

    // const tokenContract = new hre.ethers.Contract(
    //     "0x4200000000000000000000000000000000000006", // Presumed WETH address
    //     tokenABI,
    //     signer
    // );
    const tokenContract = new web3.eth.Contract(tokenABI, token0);
    const dcaContract = new web3.eth.Contract(dcaABI, dcaAddress);


    let balance1 = await tokenContract.methods.balanceOf(account.address).call();
    console.log(balance1);

    const deposit = await tokenContract.methods
    .deposit()
    .send({ from: account.address, value: 10 ** 18 });

    balance1 = await tokenContract.methods.balanceOf(account.address).call();
    console.log(balance1);

    const approve = await tokenContract.methods.approve(dcaAddress,balance1).send(
        {from: account.address}
    );
    // console.log(approve);
    const ethBalance = await web3.eth.getBalance("0x777Fd4CFaD04Af3dA47dF688a3Ac3Cda29A06b0C");
console.log("ETH1: ", ethBalance);

// const amountToSend = web3.utils.toWei('1', 'ether');
// const value = BigInt(amountToSend) - BigInt(ethBalance);


// // Build the transaction object
// const txObject = {
//   from: account.address,
//   to: "0x777Fd4CFaD04Af3dA47dF688a3Ac3Cda29A06b0C",
//   value: value,
//   gas: 21000,
//   gasPrice: web3.utils.toWei('10', 'gwei'), // You can set your own gas price
// };

// // Sign the transaction
// const signedTx = await web3.eth.accounts.signTransaction(txObject, process.env.PRIVATE_KEY);

// // Send the signed transaction
// const txReceipt = await web3.eth.sendSignedTransaction(signedTx.rawTransaction);

// console.log('Transaction Hash:', txReceipt.transactionHash);

    const createOrder = await dcaContract.methods
    .createOrder(balance1,token0,  token1, 5, 1, [0,0])
    .send({ from: account.address, value: 10 ** 18 });

    console.log(createOrder.transactionHash)
   

    try {
        
    } catch (error) {
        console.error("Error during the transaction:", error);
    }
}

main().catch(console.error);
