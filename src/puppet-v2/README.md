# Puppet V2

The developers of the [previous pool](https://damnvulnerabledefi.xyz/challenges/puppet/) seem to have learned the lesson. And released a new version.

Now they’re using a Uniswap v2 exchange as a price oracle, along with the recommended utility libraries. Shouldn't that be enough?

You start with 20 ETH and 10000 DVT tokens in balance. The pool has a million DVT tokens in balance at risk!

Save all funds from the pool, depositing them into the designated recovery account.

# 漏洞代码
pool中的末尾_getOracleQuote函数
```solidity
    // Fetch the price from Uniswap v2 using the official libraries
    //@audit-issue 依赖于单个流动性池的状态，并且预言机仍然使用当前储备金来计算价格
    function _getOracleQuote(uint256 amount) private view returns (uint256) {
        (uint256 reservesWETH, uint256 reservesToken) =
            UniswapV2Library.getReserves({factory: _uniswapFactory, tokenA: address(_weth), tokenB: address(_token)});

        return UniswapV2Library.quote({amountA: amount * 10 ** 18, reserveA: reservesToken, reserveB: reservesWETH});
    }
```

这使得我们可以通过执行大量交易来操纵价格，改变储备金比率


