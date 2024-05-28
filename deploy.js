const { ethers } = require("hardhat");

async function main() {
    const provider = new ethers.JsonRpcProvider("http://localhost:8545");
    const wallet = new ethers.Wallet("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", provider);

    const uniswapV2Router = "0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24";
    const uniswapV3Router = "0x2626664c2603336E57B271c5C0b26F421741e481";
    const uniswapV3Factory = "0x33128a8fC17869897dcE68Ed026d694621f6FDfD";
    const uniswapV2Factory = "0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6";
    const keeper = "0x777Fd4CFaD04Af3dA47dF688a3Ac3Cda29A06b0C"
    const feeWallet = "0xf1d5582Fe3B3e3D329f0B08f16eE55546A824b01"
    const owner = "0xf1d5582Fe3B3e3D329f0B08f16eE55546A824b01"
    

    const contractFactory = new ethers.ContractFactory(
        require("./artifacts/contracts/DCA.sol/DCA.json").abi,
        require("./artifacts/contracts/DCA.sol/DCA.json").bytecode,
        wallet
      );
  // Deploy the contract with constructor arguments
//   const MyContract = await ethers.getContractFactory("DCA");
  const contract = await contractFactory.deploy(uniswapV3Router, uniswapV2Router, uniswapV3Factory, uniswapV2Factory, keeper, feeWallet, owner);

  console.log("Contract deployed to const:", contract);
}

main().then(() => process.exit(0)).catch(error => {
  console.error(error);
  process.exit(1);
});