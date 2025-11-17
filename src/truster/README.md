# Truster

More and more lending pools are offering flashloans. In this case, a new pool has launched that is offering flashloans of DVT tokens for free.

The pool holds 1 million DVT tokens. You have nothing.

To pass this challenge, rescue all funds in the pool executing a single transaction. Deposit the funds into the designated recovery account.

越来越多的借贷池开始提供闪贷服务。本场景中，一个新上线的借贷池推出了 免费的 DVT 代币闪贷（无需支付手续费）。
该借贷池持有 100 万枚 DVT 代币，而你初始一无所有。
要完成本挑战，需通过 单笔交易 提取借贷池中的全部资金，并将这些资金存入指定的恢复账户（recovery account）。

# 漏洞代码
pool的flashLone中

```solidity
//@audit-issue :允许任意数据以pool的名义调用
        target.functionCall(data);
```

# 解决方案思路
利用flashLoan的漏洞，构造调用池中token的approve函数的数据，让pool批准我们花费它的token。然后再调用transferFrom把token转走。
# 解决方案代码
```solidity
function test_truster() public checkSolvedByPlayer {
        //console.log("Nonce before new Attacker:", vm.getNonce(player));
        Attacker attacker = new Attacker(); // 增加 nonce
        //console.log("Nonce after new Attacker:", vm.getNonce(player));
        attacker.attack(pool, token, recovery);
        //console.log("Nonce after attack call:", vm.getNonce(player));
    }
```
之所以要部署攻击代码，是因为在 Foundry 测试中，vm.startPrank 只是设置了 msg.sender，但**没有真正发送链上交易**，所以 vm.getNonce(player) 仍然是 0。
只有部署合约才会真正发送一笔交易，从而让player的nonce增加，达到作者要求的player只执行一笔交易的要求