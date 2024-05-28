require("dotenv").config();

const { Web3, Contract } = require("web3");

var web3 = new Web3(process.env.API_URL);


const hre = require("hardhat");
const provider = new hre.ethers.WebSocketProvider(process.env.API_URL);

const dcaABI = require("./artifacts/contracts/DCA.sol/DCA.json").abi;
const dcaAddress = "0xbec49fa140acaa83533fb00a2bb19bddd0290f25"

const uniswapV2RouterABI = require("./abi/uniswapV2Router.json")
const uniswapV2RouterAddress = "0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24"

const uniswapV3QuoterABI = require("./abi/quoterV2.json")
const uniswapV3QuoterAddress = "0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a"

const dcaContract = getEthersContract(dcaAddress,dcaABI);

const keeper = new hre.ethers.Wallet(process.env.KEEPER_PRIVATE_KEY, provider)


function getEthersContract(dcaAddress, dcaABI){
    const contract = new hre.ethers.Contract(
        dcaAddress,
        dcaABI,
        provider
    );
    return contract
}

async function performUpkeep(orderId) {
    try{

    const contractWithSigner = dcaContract.connect(keeper);

    const order = await contractWithSigner.getOrder(orderId)

    if(order.orderId == "0x0000000000000000000000000000000000000000000000000000000000000000") return;

    console.log(order.orderId)

    const {priceIndex, feeTier, amountOut} =await getPriceIndexAndFee(order.amountInPerOrder, order.path[0], order.path[1])

    if(amountOut == 0){
        console.log("Insufficient funds in the pool")
        return 
    }

    console.log("PUK", priceIndex, feeTier)

    const ethBalamce = await web3.eth.getBalance(keeper.address);
    console.log("ETH: ", ethBalamce);

    let gas = await contractWithSigner.gasUsedPerTX()
    console.log(gas)

    console.log("gasPrice", order.txFeesByUser)
    const transaction = await contractWithSigner
    .performUpkeep(order.orderId, priceIndex, feeTier,{gasPrice: order.txFeesByUser})

    console.log(transaction.hash)
    
    const ethBalamceAfter = await web3.eth.getBalance(keeper.address);
    console.log("ETH: ", ethBalamceAfter);

    console.log(ethBalamceAfter - ethBalamce)
          

    return;

}catch (err){
    console.log("Error inperform Up Keep: ", err.message)
}

    

}

dcaContract.on("OrderCreated", async (orderId, amountIn, tokenIn, tokenOut, numOfOrders, interval, user, txFeesByUser) => {

    setTimeout(async () => {performUpkeep(orderId)}, Number(interval) * 1000);

})

dcaContract.on("OrderExecuted", async (orderId, subOrderId, amountIn, amountOut, oneTokenPrice, timestamp, interval, swapLeft, txFeesByUser) => {

    if(swapLeft > 0){
        setTimeout(async () => {performUpkeep(orderId)}, Number(interval) * 1000);
    }


})


async function getPriceIndexAndFee(amountIn, token0, token1){
    let prices = []
    var amountOut=0;

    const uniswapV2RouterContract = getEthersContract(uniswapV2RouterAddress,uniswapV2RouterABI)
    try{
    const amounts = await uniswapV2RouterContract.getAmountsOut(amountIn, [token0, token1])
    console.log("amount:m",amounts[1])
    prices[0] = amounts[1]

    }catch (err){
        prices[0] = 0
    }

    let feeses = [500,3000,10000]
    var params = {
        tokenIn: token0, // Address of the token you're swapping from
        tokenOut: token1, // Address of the token you're swapping to
        amountIn: amountIn, // Amount of tokenIn
        fee: feeses[0], // Fee level (e.g., 3000 for 0.3%)
        sqrtPriceLimitX96: 0 // Optional sqrtPriceLimitX96
      };

    console.log(params)

    prices[1] = await v3Prices(params)

    params.fee =feeses[1]

    prices[2] = await v3Prices(params)

    params.fee =feeses[2]

    prices[3] = await v3Prices(params)

    let feeTier;

            for(var i=0; i< prices.length; ++i){
            if(amountOut < prices[i]){
                amountOut = prices[i];
                priceIndex = i;
                if(i>0){
                    feeTier=feeses[i-1];
                }
            }

        }
        console.log(priceIndex, amountOut, feeTier);
    
    return {priceIndex, feeTier, amountOut}
}


async function v3Prices(params){

    const quoterContractV3 = getEthersContract(uniswapV3QuoterAddress, uniswapV3QuoterABI)
    try{
        const data = await quoterContractV3.quoteExactInputSingle.staticCall(params)
        console.log("data: ", data)

        return data[0]
    
        }catch(err){
            console.log("error in v3Prices")
            return 0
        }

}

