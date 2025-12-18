# Climber

There’s a secure vault contract guarding 10 million DVT tokens. The vault is upgradeable, following the [UUPS pattern](https://eips.ethereum.org/EIPS/eip-1822).

The owner of the vault is a timelock contract. It can withdraw a limited amount of tokens every 15 days.

On the vault there’s an additional role with powers to sweep all tokens in case of an emergency.

On the timelock, only an account with a “Proposer” role can schedule actions that can be executed 1 hour later.

You must rescue all tokens from the vault and deposit them into the designated recovery account.

有一个安全的金库合约守护着1000万个DVT代币。该金库是可升级的，遵循[UUPS模式](https://eips.ethereum.org/EIPS/eip-1822)。

金库的所有者是一个时间锁合约。它每15天可以提取有限数量的代币。

在金库中，有一个额外的角色，其拥有在紧急情况下清扫所有代币的权力。

在时间锁方面，只有具有“提议者”角色的账户才能安排可在1小时后执行的操作。

你必须从金库中取出所有代币，并将其存入指定的恢复账户。

# 漏洞
timelock的execute函数没有去判断id是否通过了提议就可以直接让timelock执行。

那么我们可以让timkelock执行函数把timelock的所有权转让给我们，然后升级合约，添加一个没有权限检查的withraw函数提取资金库的所有token到指定回收账户，升级合约的函数为upgradeToAndCall(address, "")

# 学习总结
1. 升级合约的流程与逻辑

2. 
