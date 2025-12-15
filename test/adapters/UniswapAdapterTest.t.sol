// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {PathKey} from "@uniswap/v4-periphery/src/libraries/PathKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

import {HyperCrocVaultFactory} from "../../contracts/HyperCrocVaultFactory.sol";
import {HyperCrocVault} from "../../contracts/HyperCrocVault.sol";
import {WithdrawalQueue} from "../../contracts/WithdrawalQueue.sol";
import {UniswapAdapter} from "../../contracts/adapters/uniswap/UniswapAdapter.sol";
import {AbstractUniswapV3Adapter} from "../../contracts/adapters/uniswap/AbstractUniswapV3Adapter.sol";
import {AdapterBase} from "../../contracts/adapters/AdapterBase.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";

contract UniswapAdapterTest is Test {
    using Math for uint256;

    uint256 public constant FORK_BLOCK = 22515980;

    address private constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant UNISWAP_UNIVERSAL_ROUTER = 0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af;
    address private constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    IERC20 private constant WBTC = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    UniswapAdapter private adapter;
    HyperCrocVault private hyperCrocVault;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl), FORK_BLOCK);

        EulerRouterMock oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE().mulDiv(100_000, 10 ** 2), address(WBTC), address(USDC));

        address hyperCrocVaultImplementation = address(new HyperCrocVault());
        address withdrawalQueueImplementation = address(new WithdrawalQueue());
        address hyperCrocVaultFactoryImplementation = address(new HyperCrocVaultFactory());

        bytes memory data = abi.encodeWithSelector(
            HyperCrocVaultFactory.initialize.selector, hyperCrocVaultImplementation, withdrawalQueueImplementation
        );
        ERC1967Proxy hyperCrocVaultFactoryProxy = new ERC1967Proxy(hyperCrocVaultFactoryImplementation, data);
        HyperCrocVaultFactory hyperCrocVaultFactory = HyperCrocVaultFactory(address(hyperCrocVaultFactoryProxy));

        (address deployedVault,) = hyperCrocVaultFactory.deployVault(
            address(USDC),
            "lpName",
            "lpSymbol",
            "withdrawalQueueName",
            "withdrawalQueueSymbol",
            address(0xFEE),
            address(oracle)
        );

        hyperCrocVault = HyperCrocVault(deployedVault);
        hyperCrocVault.setMaxTrackedAssets(type(uint8).max);

        adapter = new UniswapAdapter(UNISWAP_V3_ROUTER, UNISWAP_UNIVERSAL_ROUTER, PERMIT2);
        hyperCrocVault.addAdapter(address(adapter));

        hyperCrocVault.addTrackedAsset(address(WBTC));
        deal(address(USDC), address(hyperCrocVault), 10 ** 18);
    }

    function testSwapExactInputV3() public {
        uint256 amountIn = 100_000 * 10 ** 6;
        uint256 usdcBalanceBefore = USDC.balanceOf(address(hyperCrocVault));

        bytes memory path = abi.encodePacked(USDC, uint24(3_000), WBTC);

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            recipient: address(hyperCrocVault),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0
        });

        vm.prank(address(hyperCrocVault));
        adapter.swapExactInputV3(params);

        uint256 usdcBalanceAfter = USDC.balanceOf(address(hyperCrocVault));
        assertEq(usdcBalanceBefore - usdcBalanceAfter, amountIn);
        assertGt(WBTC.balanceOf(address(hyperCrocVault)), 0);

        assertEq(WBTC.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);
    }

    function testSwapExactInputV3AllExcept() public {
        deal(address(USDC), address(hyperCrocVault), 105_000 * 10 ** 6);
        uint256 except = 100_000 * 10 ** 6;

        bytes memory path = abi.encodePacked(USDC, uint24(3_000), WBTC);

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            recipient: address(hyperCrocVault),
            deadline: block.timestamp,
            amountIn: except,
            amountOutMinimum: 0
        });

        vm.prank(address(hyperCrocVault));
        adapter.swapExactInputV3AllExcept(params);

        assertEq(USDC.balanceOf(address(hyperCrocVault)), except);
        assertGt(WBTC.balanceOf(address(hyperCrocVault)), 0);

        assertEq(WBTC.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);
    }

    function testSwapExactInputV3WrongRecipient() public {
        uint128 amountIn = 100_000 * 10 ** 6;
        bytes memory path = abi.encodePacked(USDC, uint24(3_000), WBTC);
        address recipient = address(0x01);

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            recipient: recipient,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0
        });

        vm.prank(address(hyperCrocVault));
        vm.expectRevert(
            abi.encodeWithSelector(AbstractUniswapV3Adapter.WrongRecipient.selector, address(hyperCrocVault), recipient)
        );
        adapter.swapExactInputV3(params);
    }

    function testSwapExactOutputV3() public {
        uint256 amountOut = 10 ** 8;
        uint256 usdcBalanceBefore = USDC.balanceOf(address(hyperCrocVault));

        bytes memory path = abi.encodePacked(WBTC, uint24(3_000), USDC);

        ISwapRouter.ExactOutputParams memory params = ISwapRouter.ExactOutputParams({
            path: path,
            recipient: address(hyperCrocVault),
            deadline: block.timestamp,
            amountOut: amountOut,
            amountInMaximum: USDC.balanceOf(address(hyperCrocVault))
        });

        vm.prank(address(hyperCrocVault));
        adapter.swapExactOutputV3(params);

        uint256 usdcBalanceAfter = USDC.balanceOf(address(hyperCrocVault));
        assertGt(usdcBalanceBefore, usdcBalanceAfter);
        assertEq(WBTC.balanceOf(address(hyperCrocVault)), amountOut);

        assertEq(WBTC.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);
    }

    function testSwapExactOutputV3WrongRecipient() public {
        uint256 amountOut = 10 ** 8;
        bytes memory path = abi.encodePacked(WBTC, uint24(3_000), USDC);
        address recipient = address(0x01);

        ISwapRouter.ExactOutputParams memory params = ISwapRouter.ExactOutputParams({
            path: path,
            recipient: recipient,
            deadline: block.timestamp,
            amountOut: amountOut,
            amountInMaximum: USDC.balanceOf(address(hyperCrocVault))
        });

        vm.prank(address(hyperCrocVault));
        vm.expectRevert(
            abi.encodeWithSelector(AbstractUniswapV3Adapter.WrongRecipient.selector, address(hyperCrocVault), recipient)
        );
        adapter.swapExactOutputV3(params);
    }

    function testSwapExactInputV4() public {
        uint128 amountIn = 100_000 * 10 ** 6;
        uint256 usdcBalanceBefore = USDC.balanceOf(address(hyperCrocVault));

        PathKey[] memory path = new PathKey[](1);
        path[0] = PathKey({
            intermediateCurrency: Currency.wrap(address(WBTC)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0)),
            hookData: ""
        });

        IV4Router.ExactInputParams memory params = IV4Router.ExactInputParams({
            path: path,
            currencyIn: Currency.wrap(address(USDC)),
            amountIn: amountIn,
            amountOutMinimum: 0
        });

        vm.prank(address(hyperCrocVault));
        adapter.swapExactInputV4(params, block.timestamp);

        uint256 usdcBalanceAfter = USDC.balanceOf(address(hyperCrocVault));
        assertEq(usdcBalanceBefore - usdcBalanceAfter, amountIn);
        assertGt(WBTC.balanceOf(address(hyperCrocVault)), 0);

        assertEq(WBTC.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);
    }

    function testSwapExactInputV4AllExcept() public {
        deal(address(USDC), address(hyperCrocVault), 105_000 * 10 ** 6);
        uint128 except = 100_000 * 10 ** 6;

        PathKey[] memory path = new PathKey[](1);
        path[0] = PathKey({
            intermediateCurrency: Currency.wrap(address(WBTC)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0)),
            hookData: ""
        });

        IV4Router.ExactInputParams memory params = IV4Router.ExactInputParams({
            path: path,
            currencyIn: Currency.wrap(address(USDC)),
            amountIn: except,
            amountOutMinimum: 0
        });

        vm.prank(address(hyperCrocVault));
        adapter.swapExactInputV4AllExcept(params, block.timestamp);

        uint256 usdcBalanceAfter = USDC.balanceOf(address(hyperCrocVault));
        assertEq(usdcBalanceAfter, except);
        assertGt(WBTC.balanceOf(address(hyperCrocVault)), 0);

        assertEq(WBTC.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);
    }

    function testSwapExactOutputV4() public {
        uint128 amountOut = 10 ** 8;
        uint256 usdcBalanceBefore = USDC.balanceOf(address(hyperCrocVault));

        PathKey[] memory path = new PathKey[](1);
        path[0] = PathKey({
            intermediateCurrency: Currency.wrap(address(USDC)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0)),
            hookData: ""
        });

        IV4Router.ExactOutputParams memory params = IV4Router.ExactOutputParams({
            path: path,
            currencyOut: Currency.wrap(address(WBTC)),
            amountOut: amountOut,
            amountInMaximum: uint128(usdcBalanceBefore)
        });

        vm.prank(address(hyperCrocVault));
        adapter.swapExactOutputV4(params, block.timestamp);

        uint256 usdcBalanceAfter = USDC.balanceOf(address(hyperCrocVault));
        assertGt(usdcBalanceBefore, usdcBalanceAfter);
        assertNotEq(usdcBalanceAfter, 0);
        assertEq(WBTC.balanceOf(address(hyperCrocVault)), amountOut);

        assertEq(WBTC.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(adapter)), 0);
    }
}
