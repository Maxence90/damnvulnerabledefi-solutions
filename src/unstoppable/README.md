# Unstoppable

There's a tokenized vault with a million DVT tokens deposited. It’s offering flash loans for free, until the grace period ends.

To catch any bugs before going 100% permissionless, the developers decided to run a live beta in testnet. There's a monitoring contract to check liveness of the flashloan feature.

Starting with 10 DVT tokens in balance, show that it's possible to halt the vault. It must stop offering flash loans.

有一个存放了百万DVT代币的代币化保险库。它正在免费提供闪电贷款，直到宽限期结束。

为了在完全去中心化之前发现任何错误，开发人员决定在测试网上运行一个实时beta版。有一个监控合约来检查闪电贷款功能的活跃性。

从10个DVT代币的余额开始，展示如何暂停保险库。它必须停止提供闪电贷款。

# 错误的地方
在UnstoppableVault.sol的flashLoan函数中。
```
if (convertToShares(totalSupply) != balanceBefore) revert InvalidBalance(); 
```
convertToShares(uint256 assets): 这是一个传入资产数量返回对应的金库份额数量的函数。（显而易见这里传入的参数出错了，进行判断对比的变量也出错了）

在初始时金库份额数量和底层资产数量相等，即1：1，所以这个判断并不会revert。
但如果我在测试中把用户的所有余额都转账给了UnstoppableVault，那么这个合约的balance就会变多，但是totalSupply并不会增加，此时balanceBefore和totalSupply就不相等了。就会出现错误，合约会暂停。