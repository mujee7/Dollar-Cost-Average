                                                    /**
                                                     * @dev https://github.com/mujee7
                                                     * Muhammad Mujtaba Rehman
                                                     * @mujee7
                                                     * Dollar cost average contract
                                                     */


pragma solidity 0.8.20;

import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {Pausable} from "./Pausable.sol";
import {Ownable} from "./Ownable.sol";
import {SafeMath} from "./SafeMath.sol";
import {SafeCast} from "./SafeCast.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import {EnumerableSet} from "./EnumerableSet.sol";
import "./ISwapRouter.sol";
import "./IUniswapV2Router02.sol";
import {IERC20Extended} from "./IERC20Extended.sol";





contract DCA is ReentrancyGuard, Pausable, Ownable {
    //---------- Libraries ----------//
    using SafeMath for uint256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    // ---------- ERRORS ----------//
    error SendEthFailed();
    error SenderIsNotAdmin();
    error SenderIsNotKeeper();

    //---------- Contracts ----------//
    ISwapRouter public   uniswapV3Router;  //uniswap v3 Router
    IUniswapV2Router02 public uniswapV2Router;


    address public keeper; // Address of the admin who can performKeep.

    //---------- Storage -----------//
    address public feeWallet; // Address of the wallet that will receive the fee.
    uint256 fee = 100; // 0.1% Fee to be charged for each swap.
    uint randNo = 0;

    uint256 public gasUsedPerTX = 305000 ;

    mapping(address user => uint256) public ordersCreatedByUser; 

    mapping(address token0 => mapping(address token1 => bool )) private allowedPairs; 

    mapping(address user => mapping(uint256 index => bytes32 )) public orderIdOfUserByIndex;

    mapping(address user => mapping(bytes32 orderId => uint256 )) public indexOfUserByOrderID;



    struct Order {
        // Order Identity.
        bytes32 orderId;
        // Amount of tokens to swap.
        uint256 amountIn;
        // Path to be performed by the swap.
        address[] path;
        // Address of the order maker.
        address user;
        // Swap interval.
        uint256 interval;
        // Date of the last swap.
        uint256 lastSwapDate;
        // How many "from" tokens there are left to swap
        uint256 remaining;
        // How many swaps left the position has to execute
        uint8 swapsLeft;
        // Number of orders to execute.
        uint8 numOfOrders;
        // Minimum price to execute the order.
        uint256 minPrice;
        // Maximum price to execute the order.
        uint256 maxPrice;
        // Gas needed to execute the order.
        uint256 gasAmount;
        // Gas price sent by user to execute the order.
        uint256 txFeesByUser;
        // Per Order amount to execute the order.
        uint256 amountInPerOrder;
    }

    mapping(bytes32 => Order) private orderBook; 
    EnumerableSet.Bytes32Set private orderIndex;

    //---------- Events -----------//
    event OrderCreated(
        bytes32 indexed orderId,
        uint256 amountIn,
        address tokenIn,
        address tokenOut,
        uint8 numOfOrders,
        uint256 interval,
        address indexed user,
        uint256 txFeesByUser
    );

    event OrderPushed(Order order);

    event OrderCancelled(bytes32 indexed orderId);

    event OrderFilled(
        bytes32 indexed orderId,
        uint256 amountIn,
        uint256 timestamp
    );

    event OrderExecuted(
        bytes32 indexed orderId,
        bytes32 indexed subOrderId,
        uint256 amountIn,
        uint256 amountOut,
        uint256 rate,
        uint256 timestamp, 
        uint256 interval,
        uint8 remainingOrders,
        uint256 txFeesByUser
    );

    //---------- Constructor ----------//
    constructor(
        address _uniswapV3Router,
        address _uniswapV2Router,
        address _keeper,
        address _feeWallet,
        address  _owner        
    ) Ownable(_owner){        
        uniswapV3Router = ISwapRouter(_uniswapV3Router);
        keeper = _keeper;
        feeWallet = _feeWallet;
        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
    }

    //---------- Modifiers ----------//
    /**
     * @dev Reverts if keeper is not keeper.
     */
    modifier onlyKeeper() {
        if (_msgSender() != keeper) revert SenderIsNotKeeper();
        _;
    }

    

    /**
     * @dev Cancel a existent order.
     * @param orderId Order Identity.
     */
    function _deleteOrder(bytes32 orderId,address user) private {
        
        orderIdOfUserByIndex[user][indexOfUserByOrderID[user][orderId]]=bytes32(0);
        orderIndex.remove(orderId);
        delete orderBook[orderId];
    }

    /**
     * @dev Check total Number of orders currently exists for operation
     * 
     */

    function totalOrders() external view returns (uint256) {
        return orderIndex.length();
    }


    /**
     * @notice checks pair allowed on DCA
     * @param token0 address.
     * @param token1 address.
     * @return bool trueon existance and vise versa.
     */

    function pairAllowance(address token0, address token1) public view returns (bool) {
        if(allowedPairs[token0][token1] || allowedPairs[token1][token0] )
        {
            return true;
        }else{
            return false;
        }        
    }

    /**
     * @notice adds new token pair to trade
     * @param token0 address.
     * @param token1 address.
     */

     function addPair(address token0, address token1) onlyKeeper external {
        require(!pairAllowance(token0,token1),"Pair already exists."); 
        allowedPairs[token0][token1] = true;
    }


    /**
     * @notice Show data of the order.
     * @param orderId ID for query.
     * @return The data of the order.
     */
    function getOrder(bytes32 orderId) external view returns (Order memory) {
        return orderBook[orderId];
    }

     /**
     * @notice Show the order in the searched index.
     * @param index Index number for query.
     * @return The id of the order.
     */
    function getOrderAt(uint256 index) external view returns (bytes32) {
        return orderIndex.at(index);
    }


    /**
     * @dev Return funds to user
     * @param amount Amount of tokens remaining of user to return.
     * @param token Address of the asset.
     * @param user Address of the order maker.
     * @param gasAmount remaining of the user that is not used.
     */
    function _returnFunds(uint256 amount, address token, address user,uint256 gasAmount) private {
        payable(user).send(gasAmount);
        IERC20(token).safeTransfer(user, amount);
    }


   
    
/**
     * @notice Find The Profitable routes and perform the swap of tokens
     * @param amountIn Amount of the input token.
     * @param path Array of token addresses (path[0] = input token, path[1] = output token).
     * @param user who created the order and wil receive funds.
     * @param priceIndex index to tell us which exchange/router/pair to use.
     * @param feeTier is used when it is a V3 Exchange.
     * @return amountOut of tokens bought
     */
    function findExchangeAndExecute(uint256 amountIn, address[] memory path, address user,uint256 priceIndex, uint16 feeTier) internal returns(uint256 amountOut) {
        require(path.length == 2);
        uint256[] memory uniswapV2OutputAmounts;
      
        if(priceIndex==0){
            IERC20(path[0]).safeApprove(address(uniswapV2Router), amountIn);
            uniswapV2OutputAmounts= uniswapV2Router.getAmountsOut(amountIn, path);
            amountOut = uniswapV2OutputAmounts[1];
            uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(amountIn, 0, path, user, block.timestamp);
        }else{
            IERC20(path[0]).safeApprove(address(uniswapV3Router), amountIn);

            ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: path[0],
                tokenOut: path[1],
                fee: feeTier,
                recipient: user,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
            amountOut = uniswapV3Router.exactInputSingle(params);
        }

    }
    /**
     * @dev Performs a swap on the recpected orderId
     * @param orderId Order Identity
     */
    function _performSwap(bytes32 orderId, uint256 priceIndex, uint16 feeTier) private {

    Order storage order = orderBook[orderId];
    uint256 amountIn = order.amountInPerOrder;

    if (order.remaining < amountIn) amountIn = order.remaining;

    order.swapsLeft -= 1;
    order.lastSwapDate = block.timestamp;
    order.remaining -= amountIn;

    

    uint256 dcaFees = amountIn.mul(fee).div(10000);
    
    IERC20(order.path[0]).safeTransfer(feeWallet, dcaFees);  
    
    // tokenAmountForWithdraw[order.path[0]] += dcaFees;
    
    amountIn = amountIn - dcaFees ;
    
    // (, , uint256 amountOut, uint256 oneTokenPrice) = getPrice(amountIn, order.path);
    
    
    uint256 amountOut = findExchangeAndExecute(amountIn, order.path, order.user, priceIndex,  feeTier);
    require(amountOut > 0, "Insufficient Liquidity in pool");

    uint256 oneToken = 10 ** uint256(IERC20Extended(order.path[0]).decimals());
    uint256 price = amountIn.div(amountOut);
    uint256 oneTokenPrice = oneToken.mul(price);

    if(order.minPrice !=0){
        require(oneTokenPrice >= order.minPrice && oneTokenPrice <= order.maxPrice, "Price Doesn't lie between the range");
    }

    
    
    // Post-swap state update
    uint8 swapLeft = order.swapsLeft;
    uint256 interval = order.interval;
    uint256 txFeesByUser = order.txFeesByUser;

    bytes32 subOrderId = keccak256(
        abi.encodePacked(orderId, amountIn, oneTokenPrice, block.timestamp, block.number)
    );

    emit OrderExecuted(
        orderId,
        subOrderId,
        amountIn,
        amountOut,
        oneTokenPrice,
        block.timestamp,
        interval,
        swapLeft,
        txFeesByUser
    );

    
}

function _createOrder(
        uint256 amountIn_,
        address tokenIn,
        address tokenOut,
        uint256 interval_,
        uint8 numOfOrders_,
        uint256[2] memory priceRange_,
        address user,
        uint256 gasValue
    ) internal returns(bytes32 orderId) {

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        randNo = uint(keccak256(abi.encodePacked(user, block.timestamp, randNo)));
        orderId = keccak256(
            abi.encodePacked(amountIn_, tokenIn, tokenOut, user, interval_, numOfOrders_, randNo, block.number)
        );


        {
        require(!orderIndex.contains(orderId), "Order id exists");
        
        IERC20(tokenIn).safeTransferFrom(user, address(this), amountIn_);  
        }


        {
        uint256 amountInPerOrder = amountIn_.div(numOfOrders_);

        // Create order
        Order memory newOrder = Order(
            orderId, amountIn_, path, user, interval_, block.timestamp, amountIn_, numOfOrders_, numOfOrders_, priceRange_[0], priceRange_[1], gasValue,tx.gasprice, amountInPerOrder
        );
        _update(orderId, user,newOrder);

        emit OrderCreated(
            orderId, amountIn_, tokenIn, tokenOut, numOfOrders_, interval_, user, tx.gasprice
        );
        emit OrderPushed(newOrder);
        }


    }
    

    function _update(bytes32 orderId, address user, Order memory newOrder) internal {

        orderIndex.add(orderId);
        orderBook[orderId] = newOrder;

        orderIdOfUserByIndex[user][ordersCreatedByUser[user]]=orderId;
        indexOfUserByOrderID[user][orderId]=ordersCreatedByUser[user];
        ordersCreatedByUser[user] += 1;

    }

    function _checksForCreateOrder(
        uint256 amountIn_,
        address tokenIn,
        address tokenOut,
        uint256 interval_,
        uint8 numOfOrders_,
        uint256[2] memory priceRange_,
        uint256 gasValue,
        uint256 gasSentByUser) internal pure {

        {
        
        require(gasSentByUser >= gasValue, "less native for tx");

        require(amountIn_ != 0, "Zero amount in");

        require(tokenIn != address(0) && tokenOut != address(0) && tokenIn != tokenOut, "Invalid tokens");
        }

        {
        require(interval_ >= 1 && interval_ <= 31556952, "Invalid interval");

        require(numOfOrders_ <= 255, "Invalid num of orders");

        if(priceRange_[0] != 0 || priceRange_[1] != 0)
        {
        require(priceRange_[0] != 0 && priceRange_[0] < priceRange_[1], "Invalid price range");
        }
        }

    }

   

    
    

    /**
 * @dev Create new order for DCA.
 * @param amountIn_ Amount to swap.
 * @param tokenIn Address of the input token.
 * @param tokenOut Address of the output token.
 * @param interval_ Time interval for the swap execution.
 * @param numOfOrders_ Number of times the order should be executed.
 * @param priceRange_ Price range for executing the swap [minPrice, maxPrice].
 */
    function createOrder(
        uint256 amountIn_,
        address tokenIn,
        address tokenOut,
        uint256 interval_,
        uint8 numOfOrders_,
        uint256[2] memory priceRange_
    ) external payable whenNotPaused nonReentrant returns(bytes32) {
        require(pairAllowance(tokenIn,tokenOut), "Token Pair Not Allowed"); 
        
        {
        uint256 gasValue = gasUsedPerTX.mul(tx.gasprice).mul(numOfOrders_);
        _checksForCreateOrder(amountIn_, tokenIn, tokenOut, interval_, numOfOrders_, priceRange_, gasValue, msg.value);
        }

        {
        return _createOrder(amountIn_, tokenIn, tokenOut, interval_, numOfOrders_, priceRange_,msg.sender, msg.value);

        }

        
    }



    /**
     * @notice Cancel a existent order.
     * @param orderId Order identity.
     * @notice can be only done by user itself
     */
    function cancelOrder(bytes32 orderId) external nonReentrant {
        //Checks
        require(orderIndex.contains(orderId), "Order does not exist");
        Order memory order = orderBook[orderId];
        require(order.user == _msgSender(), "Invalid access");
        address tokenIn = order.path[0];

        uint256 gasRemaing = order.gasAmount;

        //Effects
        _deleteOrder(orderId,msg.sender);

        //Interactions
        _returnFunds(order.remaining, tokenIn, order.user, gasRemaing);
        emit OrderCancelled(orderId);
    }


    /**
     * @dev This is used by the keeper to perform swaps for the user created order
     * @param orderId Order Identity
     * @notice only be called by keeper
     */

    function performUpkeep(
        bytes32 orderId,
        uint256 priceIndex, uint16 feeTier
    ) external nonReentrant onlyKeeper {
        
        require(orderIndex.contains(orderId), "Order does not exist");
        // bytes32 orderId = abi.decode(performData, (bytes32));
        _performSwap(orderId,  priceIndex, feeTier);

        Order storage order = orderBook[orderId];

        uint256 gasUtilized = (gasUsedPerTX).mul(tx.gasprice);

        require(order.gasAmount >= gasUtilized, "insufficient tx fee left" );

        order.gasAmount = order.gasAmount.sub(gasUtilized); 
        payable(keeper).transfer(gasUtilized);

        if (order.swapsLeft == 0) {
        _returnFunds(order.remaining, order.path[0], order.user, order.gasAmount);
        _deleteOrder(orderId,order.user);
        emit OrderFilled(orderId, order.amountIn, block.timestamp);
    }

    }

    /**
     * @dev This is used by the keeper to cancel any order needed
     * @param orderId_ Order Identity
     * @notice only be called by keeper
     */
    function forceCancelOrder(bytes32 orderId_) external onlyKeeper {
        //Checks
        require(orderIndex.contains(orderId_), "Order does not exist");
        Order memory order = orderBook[orderId_];
        address tokenIn = order.path[0];

        uint256 gasRemaing = order.gasAmount;


        


        //Effects
        _deleteOrder(orderId_, order.user);

        _returnFunds(order.remaining, tokenIn, order.user, gasRemaing);

        //Interactions
        
        emit OrderCancelled(orderId_);
    }

    /**
     * @dev Updates the keeper address
     * @param _keeper new address of the keeper
     * @notice only be called by owner
     */

    function updateKeeper(address _keeper) external onlyOwner {
        keeper = _keeper;
    }

    /**
     * @dev if needs to update uniswapV3 router
     * @param _uniswapV3Router new address of the uniswapV3Router
     * @notice only be called by owner
     */

    function setUniswapV3Router(address _uniswapV3Router) external onlyOwner {
        require(_uniswapV3Router != address(0), "Invalid address");
        uniswapV3Router = ISwapRouter(_uniswapV3Router);
    }


    /**
     * @dev if needs to update uniswapV3 router
     * @param _uniswapV2Router new address of the uniswapV2Router
     * @notice only be called by owner
     */

    function setUniswapV2Router(address _uniswapV2Router) external onlyOwner {
        require(_uniswapV2Router != address(0), "Invalid address");
        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
    }

    /**
     * @dev updates the gasUsedPerTX
     * @param _gasUsedPerTX new gas per transaction
     * @notice only be called by keeper
     */

    function increaseGasUsedPerTx(uint256 _gasUsedPerTX) external onlyKeeper {
        gasUsedPerTX = _gasUsedPerTX;
    }

    /**
     * @dev if needs to update feeWallet address
     * @param _feeWallet new address of the feeWallet
     * @notice only be called by owner
     */

    function updateFeeWallet(address _feeWallet) external onlyOwner {
        feeWallet = _feeWallet;
    }

/**
     * @dev if needs to update fees (current is 1%= 100, to increate to 10%=1000 , to decrease to 0.1%= 10);
     * @param _fee updated fee
     * @notice only be called by owner
     */
    function updateFee(uint256 _fee) external onlyOwner {
        fee = _fee;
    }

    /**
     * @notice Functions for pause and pause the contract.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Functions for pause and unpause the contract.
     */

    function unpause() external onlyOwner {
        _unpause();
    }

    
}
