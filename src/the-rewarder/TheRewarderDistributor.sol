// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";

struct Distribution {
    uint256 remaining; //奖励池剩余可分发总量
    uint256 nextBatchNumber; //下一个待创建的批次编号
    mapping(uint256 batchNumber => bytes32 root) roots; //批次 → Merkle 树根映射
    mapping(address claimer => mapping(uint256 word => uint256 bits)) claims; //用户领取状态的位掩码存储
}

//封装用户领取奖励时所需提交的「关键信息 + 验证凭证」
struct Claim {
    uint256 batchNumber; //领取的批次编号
    uint256 amount; //领取的奖励数量
    uint256 tokenIndex; //领取的奖励资产索引
    bytes32[] proof; // Merkle 证明（核心验证凭证）
}

/**
 * An efficient token distributor contract based on Merkle proofs and bitmaps
 */
contract TheRewarderDistributor {
    using BitMaps for BitMaps.BitMap;

    address public immutable owner = msg.sender;

    mapping(IERC20 token => Distribution) public distributions;

    error StillDistributing();
    error InvalidRoot();
    error AlreadyClaimed();
    error InvalidProof();
    error NotEnoughTokensToDistribute();

    event NewDistribution(IERC20 token, uint256 batchNumber, bytes32 newMerkleRoot, uint256 totalAmount);

    function getRemaining(address token) external view returns (uint256) {
        return distributions[IERC20(token)].remaining;
    }

    function getNextBatchNumber(address token) external view returns (uint256) {
        return distributions[IERC20(token)].nextBatchNumber;
    }

    function getRoot(address token, uint256 batchNumber) external view returns (bytes32) {
        return distributions[IERC20(token)].roots[batchNumber];
    }

    // 创建新的奖励分发批次
    // 1. 检查参数有效性（金额≠0，根哈希≠0）
    // 2. 确保没有正在进行的分发（remaining必须为0）
    // 3. 设置分发总量和Merkle树根
    // 4. 递增批次编号
    // 5. 从调用者转账代币到合约
    function createDistribution(IERC20 token, bytes32 newRoot, uint256 amount) external {
        if (amount == 0) revert NotEnoughTokensToDistribute();
        if (newRoot == bytes32(0)) revert InvalidRoot();
        if (distributions[token].remaining != 0) revert StillDistributing();

        distributions[token].remaining = amount;

        uint256 batchNumber = distributions[token].nextBatchNumber;
        distributions[token].roots[batchNumber] = newRoot;
        distributions[token].nextBatchNumber++;

        SafeTransferLib.safeTransferFrom(address(token), msg.sender, address(this), amount);

        emit NewDistribution(token, batchNumber, newRoot, amount);
    }

    //回收合约中闲置的代币
    //@audit-issue 这个函数非常集中化且危险
    function clean(IERC20[] calldata tokens) external {
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = tokens[i];
            if (distributions[token].remaining == 0) {
                token.transfer(owner, token.balanceOf(address(this)));
            }
        }
    }

    // 允许合约接收多个代币的奖励领取请求
    // 1. 遍历所有领取请求
    // 2. 计算位图位置（批次号→word位置→bit位置）
    // 3. 检查是否已领取（位图检查）
    // 4. 验证Merkle证明
    // 5. 更新领取状态和剩余金额
    // 6. 转账奖励给用户
    function claimRewards(Claim[] memory inputClaims, IERC20[] memory inputTokens) external {
        Claim memory inputClaim;
        IERC20 token;
        uint256 bitsSet; // accumulator
        uint256 amount;

        for (uint256 i = 0; i < inputClaims.length; i++) {
            inputClaim = inputClaims[i];

            uint256 wordPosition = inputClaim.batchNumber / 256;
            uint256 bitPosition = inputClaim.batchNumber % 256;

            //@audit-issue 奖励重复领取绕过（逻辑缺陷）
            if (token != inputTokens[inputClaim.tokenIndex]) {
                //@audit-issue token初始为0地址。
                //第一次进入循环时会跳过这里的逻辑，直到第二次进入循环时才会执行这里的逻辑，从而导致第一次领取记录无法被标记为已领取，从而可以重复领取奖励。
                if (address(token) != address(0)) {
                    if (!_setClaimed(token, amount, wordPosition, bitsSet)) revert AlreadyClaimed();
                }

                token = inputTokens[inputClaim.tokenIndex];
                bitsSet = 1 << bitPosition; // set bit at given position
                amount = inputClaim.amount;
            } else {
                bitsSet = bitsSet | 1 << bitPosition;
                amount += inputClaim.amount;
            }

            // for the last claim 针对最后一笔领取记录
            if (i == inputClaims.length - 1) {
                if (!_setClaimed(token, amount, wordPosition, bitsSet)) revert AlreadyClaimed();
            }

            bytes32 leaf = keccak256(abi.encodePacked(msg.sender, inputClaim.amount));
            bytes32 root = distributions[token].roots[inputClaim.batchNumber];

            if (!MerkleProof.verify(inputClaim.proof, root, leaf)) revert InvalidProof();

            inputTokens[inputClaim.tokenIndex].transfer(msg.sender, inputClaim.amount);
        }
    }

    // 标记用户已领取奖励
    function _setClaimed(IERC20 token, uint256 amount, uint256 wordPosition, uint256 newBits) private returns (bool) {
        uint256 currentWord = distributions[token].claims[msg.sender][wordPosition];
        if ((currentWord & newBits) != 0) return false;

        // update state
        distributions[token].claims[msg.sender][wordPosition] = currentWord | newBits;
        distributions[token].remaining -= amount;

        return true;
    }
}
