# DefiFlow

This smart contract, named **DeFiFlow**, was created as part of a project for a client in June and July. The contract is designed to facilitate decentralized finance (DeFi) operations, specifically focusing on liquidity management, token swaps, and impermanent loss mitigation across multiple decentralized exchanges (DEXs). 

The contract supports both **Uniswap** and **SushiSwap** for token swapping, integrates with **Chainlink** price feeds to retrieve market data, and utilizes **Chainlink Keepers** for automated rebalancing of liquidity. Additionally, it includes features such as stop-loss mechanisms, liquidity management, and tools to mitigate impermanent loss, making it suitable for a variety of DeFi strategies.

**Note:** The test file included in this repository is for internal testing purposes and is not intended for use by the client. This project was also created in Remix IDE

---

## Features

### 1. **Liquidity Management**
- The contract allows the owner to add or remove liquidity from the Uniswap V2 pools for two tokens (Token A and Token B).
- Liquidity can be provided using specified amounts of Token A and Token B, with a check for the maximum order size to limit exposure.
  
### 2. **Token Swapping Across DEXs**
- The contract can swap tokens between **Uniswap** and **SushiSwap**, automatically choosing the best platform based on price.
- The owner can specify the amount of tokens to swap and the path (token route) to swap along.
- Swap transactions are conducted on the DEX that offers the best price for the trade.

### 3. **Automated Rebalancing**
- The contract uses **Chainlink Keepers** to automate the rebalancing of liquidity pools based on price changes in the market.
- The rebalancing is triggered when the market price changes beyond a pre-set threshold.
  
### 4. **Impermanent Loss Mitigation**
- The contract includes functionality to mitigate impermanent loss by adjusting or removing liquidity during periods of high volatility.
- The owner can manually trigger this mitigation process.

### 5. **Stop-Loss Mechanism**
- The contract allows the owner to set a stop-loss threshold, which triggers the removal of liquidity if the market price moves unfavorably beyond this threshold, preventing further losses.

### 6. **Price Feed Integration**
- The contract integrates with **Chainlink Price Feeds** to retrieve the current market price for token pairs, allowing for informed decisions in liquidity management, token swapping, and risk management.

---

## Contract Overview

### Constructor Parameters
- **`_tokenA`**: The address of the first token (Token A) to be used in liquidity pools.
- **`_tokenB`**: The address of the second token (Token B) to be used in liquidity pools.
- **`_tokenC`**: An optional third token to integrate with additional liquidity pools or swaps.
- **`_uniswapRouter`**: The address of the Uniswap V2 router contract.
- **`_sushiSwapRouter`**: The address of the SushiSwap router contract.
- **`_priceFeed`**: The address of the Chainlink price feed contract to retrieve the current market price.
- **`_maxOrderSize`**: The maximum order size for liquidity provision and token swaps.
- **`_minProfitThreshold`**: The minimum profit threshold in basis points required to execute a trade.
- **`_rebalanceThreshold`**: The price change threshold (in basis points) that triggers liquidity rebalancing.
- **`_stopLossThreshold`**: The stop-loss threshold (in basis points) that triggers the removal of liquidity if the price drops beyond this threshold.

### Functions

- **`provideLiquidity(uint256 amountA, uint256 amountB)`**: Adds liquidity to the Uniswap pool for Token A and Token B.
- **`removeLiquidity(uint256 liquidity)`**: Removes liquidity from the Uniswap pool and retrieves the corresponding tokens.
- **`executeSwap(uint256 amountIn, address[] calldata path)`**: Executes a token swap on either Uniswap or SushiSwap, based on the best available price.
- **`getCurrentMarketPrice()`**: Retrieves the current market price from the Chainlink price feed.
- **`updateMaxOrderSize(uint256 newMaxOrderSize)`**: Allows the owner to update the maximum order size for trades and liquidity operations.
- **`updateMinProfitThreshold(uint256 newMinProfitThreshold)`**: Updates the minimum profit threshold for executing trades.
- **`updateRebalanceThreshold(uint256 newRebalanceThreshold)`**: Updates the price change threshold for triggering rebalancing.
- **`updateStopLossThreshold(uint256 newStopLossThreshold)`**: Updates the stop-loss threshold.
- **`checkUpkeep(bytes calldata)`**: A Chainlink Keeper function that checks if the conditions for rebalancing are met.
- **`performUpkeep(bytes calldata)`**: A Chainlink Keeper function that rebalances liquidity if the conditions are met.
- **`rebalanceLiquidity(uint256 currentPrice)`**: Rebalances the liquidity based on the current market price.
- **`mitigateImpermanentLoss()`**: Mitigates impermanent loss by adjusting or removing liquidity.
- **`triggerStopLoss()`**: Triggers the stop-loss mechanism to protect against further losses.

---

## Events

- **`LiquidityAdded(uint256 amountA, uint256 amountB)`**: Emitted when liquidity is added to the Uniswap pool.
- **`LiquidityRemoved(uint256 amountA, uint256 amountB)`**: Emitted when liquidity is removed from the Uniswap pool.
- **`SwapExecuted(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut)`**: Emitted when a swap is executed.
- **`Rebalanced(uint256 newPrice)`**: Emitted when the liquidity is rebalanced.
- **`ImpermanentLossMitigation(uint256 liquidityWithdrawn)`**: Emitted when impermanent loss mitigation is triggered.
- **`StopLossTriggered(uint256 liquidityWithdrawn)`**: Emitted when the stop-loss mechanism is triggered.

---

## Security

- The contract is designed to be **non-reentrant** when performing liquidity removals, swaps, and other critical functions, utilizing the `ReentrancyGuard` to prevent reentrancy attacks.
- Only the contract owner can execute sensitive actions such as adding/removing liquidity, executing swaps, or updating parameters.

---


## License

This project is licensed under the MIT License. See the LICENSE file for more details.

