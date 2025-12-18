# Puppet V3

Bear or bull market, true DeFi devs keep building. Remember that lending pool you helped? A new version is out.

They’re now using Uniswap V3 as an oracle. That’s right, no longer using spot prices! This time the pool queries the time-weighted average price of the asset, with all the recommended libraries.

The Uniswap market has 100 WETH and 100 DVT in liquidity. The lending pool has a million DVT tokens.

Starting with 1 ETH and some DVT, you must save all from the vulnerable lending pool. Don't forget to send them to the designated recovery account.

_NOTE: this challenge requires a valid RPC URL to fork mainnet state into your local environment._

无论熊市还是牛市，真正的 DeFi 开发者始终在深耕。还记得你之前帮忙分析过的那个借贷池吗？它的新版本已经上线了。

现在他们改用 Uniswap V3 作为预言机（Oracle）—— 没错，不再使用现货价格了！这一次，该借贷池会查询资产的时间加权平均价格（TWAP） ，并且整合了所有推荐的库文件。

Uniswap 市场中存有 100 枚 WETH 和 100 枚 DVT 的流动性，而这个借贷池内持有 100 万枚 DVT 代币。

你初始拥有 1 枚 ETH 和少量 DVT，目标是从这个存在漏洞的借贷池中窃取所有资产，并务必将这些资产转入指定的回收账户。

⚠️ 注意：此挑战需要一个有效的 RPC URL，用于将主网状态分叉到你的本地开发环境中。

# 漏洞
```solidity
    //@audit-issue :时间有太短，价格容易被操控
    uint32 public constant TWAP_PERIOD = 10 minutes;
```
我们持有101万枚DVT代币，大于借贷池的DVT代币，所以我们可以把所有DVT代币都存入借贷池中以此来影响官方价格。