// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface ISushiSwapRouter {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

contract DeFiFlow is Ownable, KeeperCompatibleInterface, ReentrancyGuard {
    IERC20 public tokenA;
    IERC20 public tokenB;
    IERC20 public tokenC; 
    IUniswapV2Router02 public uniswapRouter;
    ISushiSwapRouter public sushiSwapRouter;
    IUniswapV2Pair public uniswapPairAB;
    IUniswapV2Pair public uniswapPairAC; // Optional: For token A/C pair
    IUniswapV2Pair public uniswapPairBC; // Optional: For token B/C pair
    AggregatorV3Interface public priceFeed;
    uint256 public maxOrderSize;
    uint256 public minProfitThreshold; // in basis points
    uint256 public rebalanceThreshold; // price change threshold in basis points for rebalancing
    uint256 public stopLossThreshold; // threshold for triggering stop-loss
    uint256 public lastRebalance; // timestamp of the last rebalance
    
    event LiquidityAdded(uint256 amountA, uint256 amountB);
    event LiquidityRemoved(uint256 amountA, uint256 amountB);
    event SwapExecuted(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
    event Rebalanced(uint256 newPrice);
    event ImpermanentLossMitigation(uint256 liquidityWithdrawn);
    event StopLossTriggered(uint256 liquidityWithdrawn);

    /**
     * @dev Initializes the contract with the tokens, Uniswap router, and price feed.
     * @param _tokenA Address of the first token in the pair.
     * @param _tokenB Address of the second token in the pair.
     * @param _tokenC Address of the third token (optional integration).
     * @param _uniswapRouter Address of the Uniswap V2 router contract.
     * @param _sushiSwapRouter Address of the SushiSwap router contract.
     * @param _priceFeed Address of the Chainlink price feed contract.
     * @param _maxOrderSize The maximum size for each order to limit exposure.
     * @param _minProfitThreshold Minimum profit in basis points to consider an action.
     * @param _rebalanceThreshold Price change threshold in basis points for triggering rebalancing.
     * @param _stopLossThreshold Price change threshold in basis points for triggering stop-loss.
     */
    constructor(
        address _tokenA,
        address _tokenB,
        address _tokenC, 
        address _uniswapRouter,
        address _sushiSwapRouter,
        address _priceFeed,
        uint256 _maxOrderSize,
        uint256 _minProfitThreshold,
        uint256 _rebalanceThreshold,
        uint256 _stopLossThreshold
    ) Ownable(msg.sender) {
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
        tokenC = IERC20(_tokenC); 
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        sushiSwapRouter = ISushiSwapRouter(_sushiSwapRouter);
        priceFeed = AggregatorV3Interface(_priceFeed);
        maxOrderSize = _maxOrderSize;
        minProfitThreshold = _minProfitThreshold;
        rebalanceThreshold = _rebalanceThreshold;
        stopLossThreshold = _stopLossThreshold;

        address factory = uniswapRouter.factory();
        address pairAddressAB = IUniswapV2Factory(factory).getPair(_tokenA, _tokenB);
        require(pairAddressAB != address(0), "Uniswap pair A/B doesn't exist.");
        uniswapPairAB = IUniswapV2Pair(pairAddressAB);

        // Optionally create or check pair with Token C if needed
        address pairAddressAC = IUniswapV2Factory(factory).getPair(_tokenA, _tokenC);
        if (pairAddressAC != address(0)) {
            uniswapPairAC = IUniswapV2Pair(pairAddressAC);
        }

        address pairAddressBC = IUniswapV2Factory(factory).getPair(_tokenB, _tokenC);
        if (pairAddressBC != address(0)) {
            uniswapPairBC = IUniswapV2Pair(pairAddressBC);
        }
    }

    /**
     * @notice Provides liquidity to the Uniswap pool for tokenA and tokenB.
     * @dev This function adds liquidity to the Uniswap pool.
     */
    function provideLiquidity(uint256 amountA, uint256 amountB) external onlyOwner {
        require(amountA > 0 && amountB > 0, "Amounts must be greater than zero.");
        require(amountA <= maxOrderSize && amountB <= maxOrderSize, "Exceeds max order size.");

        tokenA.approve(address(uniswapRouter), amountA);
        tokenB.approve(address(uniswapRouter), amountB);

        (uint256 amountADesired, uint256 amountBDesired, ) = uniswapRouter.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            1,
            1,
            address(this),
            block.timestamp
        );

        emit LiquidityAdded(amountADesired, amountBDesired);
    }

    /**
     * @notice Removes liquidity from the Uniswap pool for tokenA and tokenB.
     * @dev This function burns the LP tokens to remove liquidity from the pool.
     */
    function removeLiquidity(uint256 liquidity) external onlyOwner nonReentrant {
        require(liquidity > 0, "Liquidity must be greater than zero.");

        IERC20 lpToken = IERC20(address(uniswapPairAB));
        lpToken.approve(address(uniswapRouter), liquidity);

        (uint256 amountA, uint256 amountB) = uniswapRouter.removeLiquidity(
            address(tokenA),
            address(tokenB),
            liquidity,
            1,
            1,
            address(this),
            block.timestamp
        );

        emit LiquidityRemoved(amountA, amountB);
    }

    /**
     * @notice Executes a swap on the best DEX.
     * @dev This function swaps tokenA for tokenB, tokenA for tokenC, or tokenB for tokenC, choosing the best platform based on price.
     * @param amountIn The amount of the input token.
     * @param path The path of the swap, which could involve tokenC as well.
     */
    function executeSwap(uint256 amountIn, address[] calldata path) external onlyOwner nonReentrant {
        require(amountIn > 0, "Amount must be greater than zero.");
        require(path.length >= 2, "Invalid swap path.");

        // Compare prices between Uniswap and SushiSwap
        uint256[] memory amountsUniswap = uniswapRouter.getAmountsOut(amountIn, path);
        uint256[] memory amountsSushiSwap = sushiSwapRouter.swapExactTokensForTokens(amountIn, 1, path, address(this), block.timestamp);

        uint256 amountOutUniswap = amountsUniswap[amountsUniswap.length - 1];
        uint256 amountOutSushiSwap = amountsSushiSwap[amountsSushiSwap.length - 1];

        if (amountOutUniswap >= amountOutSushiSwap) {
            // Execute swap on Uniswap
            IERC20(path[0]).approve(address(uniswapRouter), amountIn);
            uint256[] memory amounts = uniswapRouter.swapExactTokensForTokens(
                amountIn,
                amountOutUniswap,
                path,
                address(this),
                block.timestamp
            );
            emit SwapExecuted(path[0], path[path.length - 1], amounts[0], amounts[amounts.length - 1]);
        } else {
            // Execute swap on SushiSwap
            IERC20(path[0]).approve(address(sushiSwapRouter), amountIn);
            uint256[] memory amounts = sushiSwapRouter.swapExactTokensForTokens(
                amountIn,
                amountOutSushiSwap,
                path,
                address(this),
                block.timestamp
            );
            emit SwapExecuted(path[0], path[path.length - 1], amounts[0], amounts[amounts.length - 1]);
        }
    }

    /**
     * @notice Retrieves the current market price from the Chainlink price feed.
     * @return The current market price.
     */
    function getCurrentMarketPrice() public view returns (uint256) {
        (, int price, , ,) = priceFeed.latestRoundData();
        return uint256(price);
    }

    /**
     * @notice Updates the maximum order size.
     * @param newMaxOrderSize The new maximum order size.
     */
    function updateMaxOrderSize(uint256 newMaxOrderSize) external onlyOwner {
        maxOrderSize = newMaxOrderSize;
    }

    /**
     * @notice Updates the minimum profit threshold.
     * @param newMinProfitThreshold The new minimum profit threshold in basis points.
     */
    function updateMinProfitThreshold(uint256 newMinProfitThreshold) external onlyOwner {
        minProfitThreshold = newMinProfitThreshold;
    }

    /**
     * @notice Updates the rebalance threshold.
     * @param newRebalanceThreshold The new rebalance threshold in basis points.
     */
    function updateRebalanceThreshold(uint256 newRebalanceThreshold) external onlyOwner {
        rebalanceThreshold = newRebalanceThreshold;
    }

    /**
     * @notice Updates the stop-loss threshold.
     * @param newStopLossThreshold The new stop-loss threshold in basis points.
     */
    function updateStopLossThreshold(uint256 newStopLossThreshold) external onlyOwner {
        stopLossThreshold = newStopLossThreshold;
    }

    /**
     * @notice Implements Chainlink Keepers to automate rebalancing.
     * @dev This function checks if conditions are met for rebalancing.
     * @return upkeepNeeded Returns true if upkeep is needed.
     * @return performData Bytes to pass to performUpkeep if upkeep is needed.
     */
    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory performData) {
        uint256 currentPrice = getCurrentMarketPrice();
        uint256 priceDiff = currentPrice > lastRebalance ? currentPrice - lastRebalance : lastRebalance - currentPrice;
        uint256 priceDiffBps = priceDiff * 10000 / lastRebalance;

        upkeepNeeded = priceDiffBps >= rebalanceThreshold;
        performData = bytes(""); // Not needed in this implementation
    }

    /**
     * @notice Performs the automated rebalancing of liquidity.
     * @dev This function is triggered by Chainlink Keepers when conditions are met.
     */
    function performUpkeep(bytes calldata) external override {
        uint256 currentPrice = getCurrentMarketPrice();
        rebalanceLiquidity(currentPrice);
    }

    /**
     * @notice Rebalances liquidity based on the current market price.
     * @param currentPrice The current market price used to rebalance liquidity.
     */
    function rebalanceLiquidity(uint256 currentPrice) internal {
        // Logic to rebalance liquidity based on current market price
        lastRebalance = currentPrice;
        emit Rebalanced(currentPrice);
    }

    /**
     * @notice Mitigates impermanent loss by adjusting or removing liquidity during high volatility.
     * @dev This function checks volatility and impermanent loss, and mitigates if necessary.
     */
    function mitigateImpermanentLoss() external onlyOwner nonReentrant {
        // Implement logic to detect high volatility or impermanent loss
        // Adjust or remove liquidity to mitigate loss
        uint256 liquidityWithdrawn = 0; // Example value; replace with actual logic
        emit ImpermanentLossMitigation(liquidityWithdrawn);
    }

    /**
     * @notice Triggers stop-loss mechanism to prevent further losses.
     * @dev This function is triggered when the stop-loss threshold is reached.
     */
    function triggerStopLoss() external onlyOwner nonReentrant {
        // Implement logic to detect and trigger stop-loss
        uint256 liquidityWithdrawn = 0; // Example value; replace with actual logic
        emit StopLossTriggered(liquidityWithdrawn);
    }
}
