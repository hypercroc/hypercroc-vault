// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {console} from "lib/forge-std/src/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {HyperCrocVaultFactory} from "../../contracts/HyperCrocVaultFactory.sol";
import {HyperCrocVault} from "../../contracts/HyperCrocVault.sol";
import {WithdrawalQueue} from "../../contracts/WithdrawalQueue.sol";
import {Asserts} from "../../contracts/libraries/Asserts.sol";
import {AdapterBase} from "../../contracts/adapters/AdapterBase.sol";
import {CurveRouterAdapter} from "contracts/adapters/curve/CurveRouterAdapter.sol";
import {ICurveRouterNg} from "../../contracts/adapters/curve/interfaces/ICurveRouterNg.sol";
import {MintableERC20} from "../mocks/MintableERC20.t.sol";
import {CurveRouterMock} from "../mocks/CurveRouterMock.t.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";

contract CurveRouterAdapterTest is Test {
    using Math for uint256;

    HyperCrocVault public vault;
    CurveRouterMock curveRouter;
    CurveRouterAdapter public curveRouterAdapter;

    address public OWNER = makeAddr("OWNER");
    address public USER = makeAddr("USER");

    IERC20 public WETH;
    IERC20 public USDC;
    IERC20 public USDT;
    IERC20 public DAI;
    IERC20 public USDE;
    IERC20 public PENDLE;
    IERC20 public wstETH;
    IERC20 public rsETH;

    address public POOL_1 = makeAddr("POOL_1");
    address public POOL_2 = makeAddr("POOL_2");
    address public POOL_3 = makeAddr("POOL_3");
    address public POOL_4 = makeAddr("POOL_4");
    address public POOL_5 = makeAddr("POOL_5");

    function setUp() public {
        WETH = new MintableERC20("WETH", "WETH", 18);
        USDC = new MintableERC20("USDC", "USDC", 6);
        USDT = new MintableERC20("USDT", "USDT", 6);
        DAI = new MintableERC20("DAI", "DAI", 18);
        USDE = new MintableERC20("USDE", "USDE", 18);
        PENDLE = new MintableERC20("PENDLE", "PENDLE", 18);
        wstETH = new MintableERC20("wstETH", "wstETH", 18);
        rsETH = new MintableERC20("rsETH", "rsETH", 18);

        curveRouter = new CurveRouterMock();

        deal(address(WETH), address(curveRouter), 10000e18);
        deal(address(USDC), address(curveRouter), 10000e6);
        deal(address(USDT), address(curveRouter), 10000e6);
        deal(address(DAI), address(curveRouter), 10000e18);
        deal(address(USDE), address(curveRouter), 10000e18);
        deal(address(PENDLE), address(curveRouter), 10000e18);
        deal(address(wstETH), address(curveRouter), 10000e18);
        deal(address(rsETH), address(curveRouter), 10000e18);

        EulerRouterMock oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE(), address(WETH), address(USDC));
        oracle.setPrice(oracle.ONE(), address(USDT), address(USDC));
        oracle.setPrice(oracle.ONE(), address(USDT), address(USDC));
        oracle.setPrice(oracle.ONE(), address(DAI), address(USDC));
        oracle.setPrice(oracle.ONE(), address(USDE), address(USDC));
        oracle.setPrice(oracle.ONE(), address(PENDLE), address(USDC));
        oracle.setPrice(oracle.ONE(), address(wstETH), address(USDC));
        oracle.setPrice(oracle.ONE(), address(rsETH), address(USDC));

        curveRouterAdapter = new CurveRouterAdapter(address(curveRouter));

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

        vault = HyperCrocVault(deployedVault);
        vault.setMaxTrackedAssets(type(uint8).max);
        vault.addTrackedAsset(address(USDT));
        vault.addTrackedAsset(address(DAI));
        vault.addTrackedAsset(address(USDE));
        vault.addTrackedAsset(address(PENDLE));
        vault.addTrackedAsset(address(WETH));
        vault.addTrackedAsset(address(wstETH));
        vault.addTrackedAsset(address(rsETH));

        vault.addAdapter(address(curveRouterAdapter));

        deal(address(WETH), address(vault), 10000e18);
        deal(address(USDC), address(vault), 10000e6);
        deal(address(USDT), address(vault), 10000e6);
        deal(address(DAI), address(vault), 10000e18);
        deal(address(USDE), address(vault), 10000e18);
        deal(address(PENDLE), address(vault), 10000e18);
        deal(address(wstETH), address(vault), 10000e18);
        deal(address(rsETH), address(vault), 10000e18);
    }

    function testGetAdapterId() public view {
        assertEq(curveRouterAdapter.getAdapterId(), bytes4(keccak256("CurveRouterAdapter")));
    }

    function testConstructorShouldFailWhenZeroAddress() public {
        vm.expectRevert(Asserts.ZeroAddress.selector);
        new CurveRouterAdapter(address(0));
    }

    function testExchangeSingleHop() public {
        IERC20 tokenIn = USDC;
        IERC20 tokenOut = DAI;

        address[11] memory route;
        route[0] = address(USDC);
        route[1] = address(POOL_1);
        route[2] = address(DAI);

        uint256[5][5] memory swapParams;
        uint256 amount = 100e6;
        uint256 minDy = 99e6;
        address[5] memory pools;

        uint256 tokenInBalanceBefore = tokenIn.balanceOf(address(vault));

        hoax(address(vault));
        curveRouterAdapter.exchange(route, swapParams, amount, minDy, pools);

        assertGe(tokenOut.balanceOf(address(vault)), minDy);
        assertEq(tokenIn.balanceOf(address(vault)), tokenInBalanceBefore - amount);

        assertEq(tokenIn.balanceOf(address(curveRouterAdapter)), 0);
        assertEq(tokenOut.balanceOf(address(curveRouterAdapter)), 0);
    }

    function testExchangeMultiHop() public {
        IERC20 tokenIn = USDC;
        IERC20 tokenOut = WETH;

        address[11] memory route;
        route[0] = address(USDC);
        route[1] = address(POOL_1);
        route[2] = address(DAI);
        route[3] = address(POOL_2);
        route[4] = address(WETH);

        uint256[5][5] memory swapParams;
        uint256 amount = 3000e6;
        uint256 minDy = 1.7e18;
        address[5] memory pools;

        uint256 tokenInBalanceBefore = tokenIn.balanceOf(address(vault));

        hoax(address(vault));
        curveRouterAdapter.exchange(route, swapParams, amount, minDy, pools);

        assertGe(tokenOut.balanceOf(address(vault)), minDy);
        assertEq(tokenIn.balanceOf(address(vault)), tokenInBalanceBefore - amount);

        assertEq(tokenIn.balanceOf(address(curveRouterAdapter)), 0);
        assertEq(tokenOut.balanceOf(address(curveRouterAdapter)), 0);
    }

    function testExchangeMaxHops() public {
        IERC20 tokenIn = USDC;
        IERC20 tokenOut = PENDLE;

        address[11] memory route;
        route[0] = address(USDC);
        route[1] = address(POOL_1);
        route[2] = address(DAI);
        route[3] = address(POOL_2);
        route[4] = address(WETH);
        route[5] = address(POOL_3);
        route[6] = address(USDT);
        route[7] = address(POOL_4);
        route[8] = address(USDE);
        route[9] = address(POOL_5);
        route[10] = address(PENDLE);

        uint256[5][5] memory swapParams;
        uint256 amount = 3000e6;
        uint256 minDy = 950e18;
        address[5] memory pools;

        uint256 tokenInBalanceBefore = tokenIn.balanceOf(address(vault));

        hoax(address(vault));
        curveRouterAdapter.exchange(route, swapParams, amount, minDy, pools);

        assertGe(tokenOut.balanceOf(address(vault)), minDy);
        assertEq(tokenIn.balanceOf(address(vault)), tokenInBalanceBefore - amount);

        assertEq(tokenIn.balanceOf(address(curveRouterAdapter)), 0);
        assertEq(tokenOut.balanceOf(address(curveRouterAdapter)), 0);
    }

    function testExchangeShouldFailWhenSlippage() public {
        curveRouter.setOffset(1);

        address[11] memory route;
        route[0] = address(USDC);
        route[1] = address(POOL_1);
        route[2] = address(DAI);

        uint256[5][5] memory swapParams;
        uint256 amount = 100e6;
        uint256 minDy = 99e6;
        address[5] memory pools;

        vm.expectRevert(CurveRouterAdapter.CurveRouterAdapter__SlippageProtection.selector);
        hoax(address(vault));
        curveRouterAdapter.exchange(route, swapParams, amount, minDy, pools);
    }

    function testExchangeAllExcept() public {
        IERC20 tokenIn = USDC;
        IERC20 tokenOut = DAI;

        address[11] memory route;
        route[0] = address(USDC);
        route[1] = address(POOL_1);
        route[2] = address(DAI);

        uint256[5][5] memory swapParams;
        uint256 except = 100e6;
        uint256 minDy = 99e6;
        address[5] memory pools;

        hoax(address(vault));
        curveRouterAdapter.exchangeAllExcept(route, swapParams, except, minDy, pools);

        assertGe(tokenOut.balanceOf(address(vault)), minDy);
        assertEq(tokenIn.balanceOf(address(vault)), except);

        assertEq(tokenIn.balanceOf(address(curveRouterAdapter)), 0);
        assertEq(tokenOut.balanceOf(address(curveRouterAdapter)), 0);
    }
}
