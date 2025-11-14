// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {FlashLoanReceiver} from "./FlashLoanReceiver.sol";
import {Multicall} from "./Multicall.sol";
import {WETH} from "solmate/tokens/WETH.sol";

//闪电贷资金池
contract NaiveReceiverPool is Multicall, IERC3156FlashLender {
    uint256 private constant FIXED_FEE = 1e18; // not the cheapest flash loan
    bytes32 private constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    WETH public immutable weth;
    address public immutable trustedForwarder;
    address public immutable feeReceiver;

    mapping(address => uint256) public deposits;
    uint256 public totalDeposits;

    error RepayFailed();
    error UnsupportedCurrency();
    error CallbackFailed();

    constructor(address _trustedForwarder, address payable _weth, address _feeReceiver) payable {
        weth = WETH(_weth);
        trustedForwarder = _trustedForwarder;
        feeReceiver = _feeReceiver;
        _deposit(msg.value);
    }

    function maxFlashLoan(address token) external view returns (uint256) {
        if (token == address(weth)) return weth.balanceOf(address(this));
        return 0;
    }

    function flashFee(address token, uint256) external view returns (uint256) {
        if (token != address(weth)) revert UnsupportedCurrency();
        return FIXED_FEE;
    }

    function flashLoan(IERC3156FlashBorrower receiver, address token, uint256 amount, bytes calldata data)
        external
        returns (bool)
    {
        if (token != address(weth)) revert UnsupportedCurrency();

        // Transfer WETH and handle control to receiver
        weth.transfer(address(receiver), amount);
        totalDeposits -= amount;

        if (receiver.onFlashLoan(msg.sender, address(weth), amount, FIXED_FEE, data) != CALLBACK_SUCCESS) {
            revert CallbackFailed();
        }

        uint256 amountWithFee = amount + FIXED_FEE;
        weth.transferFrom(address(receiver), address(this), amountWithFee);
        totalDeposits += amountWithFee;

        deposits[feeReceiver] += FIXED_FEE;

        return true;
    }

    //提取
    function withdraw(uint256 amount, address payable receiver) external {
        // Reduce deposits
        //用户提款时，减少其存款记录和资金池总存款
        deposits[_msgSender()] -= amount;
        totalDeposits -= amount;

        // Transfer ETH to designated receiver
        weth.transfer(receiver, amount);
    }

    function deposit() external payable {
        _deposit(msg.value);
    }

    //用户存款
    function _deposit(uint256 amount) private {
        weth.deposit{value: amount}();

        deposits[_msgSender()] += amount;
        totalDeposits += amount;
    }

    //_msgSender() 在 withdraw 执行时读取的是 delegatecall 的 msg.data
    function _msgSender() internal view override returns (address) {
        // 概念：元交易（用户通过转发器调用），msg.sender指向转发器地址
        // 条件1：当前直接调用者是「可信转发器」（trustedForwarder）
        // 条件2：交易数据长度 ≥20 字节（确保能解析出用户地址，地址占20字节）
        // @audit-issue 我们可以构建一个交易，从forwarder合约调用该函数，从而伪造任意用户地址
        if (msg.sender == trustedForwarder && msg.data.length >= 20) {
            return address(bytes20(msg.data[msg.data.length - 20:])); // 从交易数据的末尾截取20字节，转换为地址（真实用户地址）
        } else {
            // 非元交易场景：调用父合约（Context）的默认实现，返回直接调用者（msg.sender）
            return super._msgSender();
        }
    }
}
