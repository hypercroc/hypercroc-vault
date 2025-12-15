// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {console} from "lib/forge-std/src/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {CurveRouterAdapter} from "contracts/adapters/curve/CurveRouterAdapter.sol";
import {ICurveRouterNg} from "contracts/adapters/curve/interfaces/ICurveRouterNg.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";
import {HyperCrocVaultFactory} from "../../contracts/HyperCrocVaultFactory.sol";
import {HyperCrocVault} from "../../contracts/HyperCrocVault.sol";
import {WithdrawalQueue} from "../../contracts/WithdrawalQueue.sol";

contract CurveRouterAdapterTest is Test {
    address internal constant CURVE_ROUTER = 0x45312ea0eFf7E09C83CBE249fa1d7598c4C8cd4e;

    IERC20 private USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 private USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 private DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 private WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 private DOLA = IERC20(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 private sUSDE = IERC20(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);
    IERC20 private stETH = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IERC20 private wstETH = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    CurveRouterAdapter internal curveRouterAdapter;

    address internal OWNER = makeAddr("owner");
    HyperCrocVault internal vault;

    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl), 22497400);
        vm.skip(block.chainid != 1, "Only mainnet fork test");

        curveRouterAdapter = new CurveRouterAdapter(CURVE_ROUTER);
        vm.deal(OWNER, 1 ether);

        EulerRouterMock oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE(), address(DAI), address(USDC));
        oracle.setPrice(oracle.ONE(), address(sUSDE), address(USDC));
        oracle.setPrice(oracle.ONE(), address(wstETH), address(USDC));

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
        vault.addAdapter(address(curveRouterAdapter));
    }

    function test_exchange_USDT_DAI() public {
        address usdtUsdcDai3Pool = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;

        address[11] memory route;
        route[0] = address(USDT);
        route[1] = usdtUsdcDai3Pool;
        route[2] = address(DAI);

        // [i, j, swap_type, pool_type, n_coins]
        // i - tokenIn index
        // j - tokenOut index
        // swap_type: 1-exchange, 2-exchange_underlying, 8 - ETH <-> WETH
        // pool_type: 1-stable, 2-2crypto, 3-tricrypto, 4- llama
        // n_coins: number of tokens in curve pool
        uint256[5][5] memory swapParams;
        swapParams[0] = [uint256(2), 0, 1, 1, 3];

        uint256 amount = 100e6;
        uint256 minDy = 0;
        address[5] memory pools;
        pools[0] = usdtUsdcDai3Pool;

        _exchange(route, swapParams, amount, minDy, pools);
    }

    function test_exchange_USDC_sUSDE() public {
        //USDC -> DOLA -> sUSDE

        address DOLA_USDC_USDT_POOL = 0x7d10A8734d985dBB3aD91Fce9c48CcC78b9F8B94;
        address DOLA_sUSDE_POOL = 0x744793B5110f6ca9cC7CDfe1CE16677c3Eb192ef;

        address[11] memory route;
        route[0] = address(USDC);
        route[1] = DOLA_USDC_USDT_POOL;
        route[2] = address(DOLA);
        route[3] = DOLA_sUSDE_POOL;
        route[4] = address(sUSDE);

        uint256[5][5] memory swapParams;
        swapParams[0] = [uint256(1), 0, 2, 1, 1];
        swapParams[1] = [uint256(0), 1, 1, 1, 2];

        uint256 amount = 100e6;
        uint256 minDy = 85e18;
        address[5] memory pools;
        pools[0] = DOLA_USDC_USDT_POOL;
        pools[1] = DOLA_sUSDE_POOL;

        _exchange(route, swapParams, amount, minDy, pools);
    }

    function test_exchange_WETH_wstETH() public {
        //WETH -> ETH -> stETH -> wstETH
        address ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        address ETH_stETH_POOL = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;

        address[11] memory route;
        route[0] = address(WETH);
        route[1] = address(WETH);
        route[2] = address(ETH);
        route[3] = ETH_stETH_POOL;
        route[4] = address(stETH);
        route[5] = address(wstETH);
        route[6] = address(wstETH);

        uint256[5][5] memory swapParams;
        swapParams[0] = [uint256(0), 0, 8, 0, 0]; // WETH -> ETH withdraw
        swapParams[1] = [uint256(0), 1, 1, 1, 1]; // swap ETH to stETH in poll ETH/stETH
        swapParams[2] = [uint256(0), 0, 8, 0, 0]; // stETH -> wstETH wrap

        uint256 amount = 1e18;
        uint256 minDy = 1;

        address[5] memory pools;
        pools[0] = address(1);
        pools[1] = ETH_stETH_POOL;
        pools[2] = address(1);

        _exchange(route, swapParams, amount, minDy, pools);
    }

    function _exchange(
        address[11] memory route,
        uint256[5][5] memory swapParams,
        uint256 amount,
        uint256 minDy,
        address[5] memory pools
    ) internal {
        address tokenIn = _getTokenIn(route);
        address tokenOut = _getTokenOut(route);

        deal(tokenIn, address(vault), amount);

        vault.addTrackedAsset(tokenOut);
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(address(vault));

        hoax(address(vault));
        curveRouterAdapter.exchange(route, swapParams, amount, minDy, pools);

        uint256 balanceAfter = IERC20(tokenOut).balanceOf(address(vault));

        console.log("Exchange ", ERC20(tokenIn).symbol(), " to ", ERC20(tokenOut).symbol());
        console.log("TokenIn = ", amount);
        console.log("TokenOut = ", balanceAfter - balanceBefore);

        assertGe(balanceAfter, balanceBefore + minDy);
    }

    function _getTokenIn(address[11] memory route) internal pure returns (address tokenIn) {
        tokenIn = route[0];
    }

    function _getTokenOut(address[11] memory route) internal pure returns (address tokenOut) {
        tokenOut = route[10]; // assume last token is output token
        if (tokenOut == address(0)) {
            unchecked {
                for (uint256 i = 3; i < 11; ++i) {
                    if (route[i] == address(0)) {
                        tokenOut = route[i - 1];
                        break;
                    }
                }
            }
        }
    }
}
