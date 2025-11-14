// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {WETH, NaiveReceiverPool} from "./NaiveReceiverPool.sol";

//部署的示例合约
contract FlashLoanReceiver is IERC3156FlashBorrower {
    address private pool;

    constructor(address _pool) {
        pool = _pool;
    }

    // @audit-issue 谁都能使用该合约的函数，调用资金池发起闪电贷
    function onFlashLoan(address, address token, uint256 amount, uint256 fee, bytes calldata)
        external
        returns (bytes32)
    {
        //内联汇编代码块（底层操作专用）
        //优点：1.极致优化 Gas 成本（比 Solidity 原生代码更省 Gas）
        //2.实现 Solidity 语法无法直接完成的底层操作（如直接读取合约存储槽、手动触发 revert）
        //缺点：汇编代码可读性差、容易出错（比如内存溢出、存储槽操作错误），仅在需要极致优化或底层功能时使用（这也是安全挑战中常见的漏洞隐藏点）
        assembly {
            // gas savings
            //校验调用者是否为资金池
            if iszero(eq(sload(pool.slot), caller())) {
                mstore(0x00, 0x48f5c3ed)
                revert(0x1c, 0x04)
            }
        }

        if (token != address(NaiveReceiverPool(pool).weth())) revert NaiveReceiverPool.UnsupportedCurrency();

        uint256 amountToBeRepaid;

        //TODO:有风险
        //unchecked {}：无溢出检查代码块，允许算术运算溢出 / 下溢（结果会按「模运算」处理
        unchecked {
            amountToBeRepaid = amount + fee;
        }

        _executeActionDuringFlashLoan();

        // Return funds to pool
        WETH(payable(token)).approve(pool, amountToBeRepaid);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    // Internal function where the funds received would be used
    function _executeActionDuringFlashLoan() internal {}
}
