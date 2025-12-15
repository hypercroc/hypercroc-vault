// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {console} from "lib/forge-std/src/console.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {HyperCrocPoolAdapter} from "../../contracts/adapters/hyperCrocPool/HyperCrocPoolAdapter.sol";
import {AdapterBase} from "../../contracts/adapters/AdapterBase.sol";
import {IHyperCrocPool} from "../../contracts/adapters/hyperCrocPool/interfaces/IHyperCrocPool.sol";
import {FP96} from "../../contracts/adapters/hyperCrocPool/FP96.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";
import {HyperCrocVaultFactory} from "../../contracts/HyperCrocVaultFactory.sol";
import {HyperCrocVault} from "../../contracts/HyperCrocVault.sol";
import {WithdrawalQueue} from "../../contracts/WithdrawalQueue.sol";
import {IAdapter} from "../../contracts/interfaces/IAdapter.sol";
import {IExternalPositionAdapter} from "../../contracts/interfaces/IExternalPositionAdapter.sol";
import {Asserts} from "../../contracts/libraries/Asserts.sol";
import {HyperCrocPoolMock} from "../mocks/HyperCrocPoolMock.t.sol";

contract HyperCrocPoolAdapterHarness is HyperCrocPoolAdapter {
    constructor(address vault) HyperCrocPoolAdapter(vault) {}

    function exposed_addPool(address pool) external {
        _addPool(pool);
    }

    function exposed_removePool(address pool) external {
        _removePool(pool);
    }
}

contract HyperCrocPoolAdapterTest is Test {
    using FP96 for IHyperCrocPool.FixedPoint;
    using Math for uint256;

    uint256 private constant X96_ONE = 2 ** 96;
    uint256 private constant FORK_BLOCK_NUMBER = 23490700;

    IERC20 private USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 private PT_yUSD = IERC20(0xf580CF6B26251541f323bbda1f31CC8F91a0cA78);
    // IERC20 private weETH = IERC20(0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee);

    address private PT_yUSD_USDC_POOL = 0x12191a443aB56772d876c07FE35C6E85d6d130C8; // farming pool, only long
    // address private weETH_WETH_POOL = 0x68f61128DeCd74b63f5b76Dc133A4C3F74319DF5; // trade pool, long, short available

    HyperCrocPoolAdapter internal adapter;

    HyperCrocVault internal vault;
    EulerRouterMock internal oracle;

    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl), FORK_BLOCK_NUMBER);
        vm.skip(block.chainid != 1, "Only mainnet fork test");

        oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE(), address(USDC), address(USDC));
        oracle.setPrice(oracle.ONE(), address(PT_yUSD), address(USDC));
        // oracle.setPrice(oracle.ONE(), address(weETH), address(USDC));

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
        vault.setMaxExternalPositionAdapters(type(uint8).max);
        vault.setMaxTrackedAssets(type(uint8).max);

        // vault.addTrackedAsset(address(weETH));
        vault.addTrackedAsset(address(PT_yUSD));

        adapter = new HyperCrocPoolAdapter(address(vault));
        vault.addAdapter(address(adapter));

        // _fundHyperCrocPool(weETH_WETH_POOL);

        deal(address(USDC), address(vault), 1000e6);
        deal(address(PT_yUSD), address(vault), 1000e6);
        // deal(address(weETH), address(vault), 1000e6);
    }

    function test_getVault() public view {
        assertEq(adapter.getVault(), address(vault));
    }

    function test_constructorShouldFailWhenZeroVaultAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Asserts.ZeroAddress.selector));
        new HyperCrocPoolAdapter(address(0));
    }

    function test_supportsInterface() public view {
        assertTrue(adapter.supportsInterface(type(IAdapter).interfaceId));
        assertTrue(adapter.supportsInterface(type(IExternalPositionAdapter).interfaceId));
    }

    function test_getAdapterId() public view {
        assertEq(adapter.getAdapterId(), bytes4(keccak256("HyperCrocPoolAdapter")));
    }

    function test_depositQuote() public {
        IHyperCrocPool pool = IHyperCrocPool(PT_yUSD_USDC_POOL);
        uint256 depositAmount = 10e6;

        address[] memory pools = adapter.getPools();
        assertEq(pools.length, 0);

        vm.expectEmit(true, true, false, false);
        emit HyperCrocPoolAdapter.PoolAdded(PT_yUSD_USDC_POOL);

        vm.prank(address(vault));
        adapter.deposit(address(USDC), depositAmount, 0, false, address(pool), 0, 0);
        skip(5 minutes);

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(USDC));
        assertApproxEqAbs(amounts[0], depositAmount, 10);

        (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        assertEq(debtAssets.length, 1);
        assertEq(debtAssets[0], address(0));

        assertEq(debtAmounts.length, 1);
        assertEq(debtAmounts[0], 0);

        pools = adapter.getPools();
        assertEq(pools.length, 1);
        assertEq(pools[0], address(pool));

        _showAssets();
    }

    function test_depositAllExcept() public {
        IHyperCrocPool pool = IHyperCrocPool(PT_yUSD_USDC_POOL);
        uint256 exceptAmount = 995e6;
        uint256 depositAmount = IERC20(USDC).balanceOf(address(vault)) - exceptAmount;

        address[] memory pools = adapter.getPools();
        assertEq(pools.length, 0);

        vm.prank(address(vault));
        adapter.depositAllExcept(address(USDC), exceptAmount, 0, false, address(pool), 0, 0);
        skip(5 minutes);

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(USDC));
        assertApproxEqAbs(amounts[0], depositAmount, 10);

        (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        assertEq(debtAssets.length, 1);
        assertEq(debtAssets[0], address(0));

        assertEq(debtAmounts.length, 1);
        assertEq(debtAmounts[0], 0);

        pools = adapter.getPools();
        assertEq(pools.length, 1);
        assertEq(pools[0], address(pool));

        _showAssets();
    }

    function test_depositQuoteAndLong() public {
        IHyperCrocPool pool = IHyperCrocPool(PT_yUSD_USDC_POOL);
        uint256 depositAmount = 1e6;
        int256 longAmount = -4e6;

        uint256 swapCallData = pool.defaultSwapCallData();
        IHyperCrocPool.FixedPoint memory basePrice = pool.getBasePrice();
        uint256 limitPriceX96 = basePrice.inner.mulDiv(110, 100);

        vm.prank(address(vault));
        adapter.deposit(address(USDC), depositAmount, longAmount, false, address(pool), limitPriceX96, swapCallData);

        IHyperCrocPool.Position memory position = pool.positions(address(adapter));
        assertEq(uint8(position._type), uint8(IHyperCrocPool.PositionType.Long));

        assertEq(USDC.balanceOf(address(adapter)), 0);
        assertEq(PT_yUSD.balanceOf(address(adapter)), 0);

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(PT_yUSD));

        (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        assertEq(debtAssets.length, 1);
        assertEq(debtAssets[0], address(USDC));
        assertEq(debtAmounts.length, 1);
        assertTrue(debtAmounts[0] > 0);
    }

    function test_depositBase() public {
        IHyperCrocPool pool = IHyperCrocPool(PT_yUSD_USDC_POOL);
        uint256 depositAmount = 10e6;
        vm.prank(address(vault));
        adapter.deposit(address(PT_yUSD), depositAmount, 0, false, address(pool), 0, 0);
        skip(5 minutes);

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(PT_yUSD));
        assertApproxEqAbs(amounts[0], depositAmount, 10);

        (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        assertEq(debtAssets.length, 1);
        assertEq(debtAssets[0], address(0));

        assertEq(debtAmounts.length, 1);
        assertEq(debtAmounts[0], 0);

        _showAssets();
    }

    // function test_depositBaseAndShort() public {
    //     IHyperCrocPool pool = IHyperCrocPool(weETH_WETH_POOL);
    //     uint256 depositAmount = 1e6;
    //     int256 shortAmount = -4e6;

    //     uint256 swapCallData = pool.defaultSwapCallData();
    //     uint256 limitPriceX96 = pool.getBasePrice().inner.mulDiv(90, 100);

    //     vm.prank(address(vault));
    //     adapter.deposit(address(weETH), depositAmount, shortAmount, false, address(pool), limitPriceX96, swapCallData);
    //     skip(5 minutes);

    //     IHyperCrocPool.Position memory position = pool.positions(address(adapter));
    //     assertEq(uint8(position._type), uint8(IHyperCrocPool.PositionType.Short));

    //     assertEq(USDC.balanceOf(address(adapter)), 0);
    //     assertEq(weETH.balanceOf(address(adapter)), 0);

    //     (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
    //     assertEq(assets.length, 1);
    //     assertEq(amounts.length, 1);
    //     assertEq(assets[0], address(USDC));
    //     assertTrue(amounts[0] > 0);

    //     (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
    //     assertEq(debtAssets.length, 1);
    //     assertEq(debtAssets[0], address(weETH));
    //     assertEq(debtAmounts.length, 1);
    //     assertTrue(debtAmounts[0] > 0);
    // }

    // function test_depositQuoteAndShortCoeffs() public {
    //     IHyperCrocPool pool = IHyperCrocPool(weETH_WETH_POOL);
    //     _openPositionsInPool(weETH_WETH_POOL);
    //     uint256 depositAmount = 1e6;
    //     int256 shortAmount = 5e6;

    //     uint256 swapCallData = pool.defaultSwapCallData();
    //     uint256 limitPriceX96 = pool.getBasePrice().inner.mulDiv(90, 100);

    //     vm.prank(address(vault));
    //     adapter.deposit(address(USDC), depositAmount, shortAmount, false, address(pool), limitPriceX96, swapCallData);
    //     //check coeffs before reinit
    //     (, uint256[] memory amounts) = adapter.getManagedAssets();
    //     (, uint256[] memory debtAmounts) = adapter.getDebtAssets();
    //     uint256 quoteCollateral = amounts[0];
    //     uint256 baseDebt = debtAmounts[0];

    //     IHyperCrocPool.Position memory position = pool.positions(address(adapter));
    //     assertEq(uint8(IHyperCrocPool.PositionType.Short), uint8(position._type));
    //     uint256 actualQuoteCollateral =
    //         pool.quoteCollateralCoeff().inner.mulDiv(position.discountedQuoteAmount, X96_ONE);
    //     uint256 actualBaseDebt = pool.baseDebtCoeff().inner.mulDiv(position.discountedBaseAmount, X96_ONE);

    //     assertEq(quoteCollateral, actualQuoteCollateral, "wrong quote collateral before reinit");
    //     assertEq(baseDebt, actualBaseDebt, "wrong base debt before reinit");

    //     skip(60 days);

    //     //check coeffs after reinit
    //     (, amounts) = adapter.getManagedAssets();
    //     (, debtAmounts) = adapter.getDebtAssets();
    //     quoteCollateral = amounts[0];
    //     baseDebt = debtAmounts[0];

    //     //reinit
    //     pool.execute(IHyperCrocPool.CallType.Reinit, 0, 0, 0, false, address(0), 0);

    //     position = pool.positions(address(adapter));
    //     actualQuoteCollateral = pool.quoteCollateralCoeff().inner.mulDiv(position.discountedQuoteAmount, X96_ONE);
    //     actualBaseDebt = pool.baseDebtCoeff().inner.mulDiv(position.discountedBaseAmount, X96_ONE);

    //     assertEq(quoteCollateral, actualQuoteCollateral, "wrong quote collateral after reinit");
    //     assertEq(baseDebt, actualBaseDebt, "wrong base debt after reinit");
    // }

    // function test_depositBaseAndLongCoeffs() public {
    //     IHyperCrocPool pool = IHyperCrocPool(weETH_WETH_POOL);
    //     _openPositionsInPool(weETH_WETH_POOL);
    //     uint256 depositAmount = 1e6;
    //     int256 longAmount = 5e6;

    //     uint256 swapCallData = pool.defaultSwapCallData();
    //     uint256 limitPriceX96 = pool.getBasePrice().inner.mulDiv(110, 100);

    //     vm.prank(address(vault));
    //     adapter.deposit(address(weETH), depositAmount, longAmount, false, address(pool), limitPriceX96, swapCallData);
    //     //check coeffs before reinit
    //     (, uint256[] memory amounts) = adapter.getManagedAssets();
    //     (, uint256[] memory debtAmounts) = adapter.getDebtAssets();
    //     uint256 baseCollateral = amounts[0];
    //     uint256 quoteDebt = debtAmounts[0];

    //     IHyperCrocPool.Position memory position = pool.positions(address(adapter));
    //     assertEq(uint8(IHyperCrocPool.PositionType.Long), uint8(position._type));
    //     uint256 actualBaseCollateral = pool.baseCollateralCoeff().inner.mulDiv(position.discountedBaseAmount, X96_ONE);
    //     uint256 actualQuoteDebt = pool.quoteDebtCoeff().inner.mulDiv(position.discountedQuoteAmount, X96_ONE);

    //     assertEq(baseCollateral, actualBaseCollateral, "wrong base collateral before reinit");
    //     assertEq(quoteDebt, actualQuoteDebt, "wrong base debt before reinit");

    //     skip(60 days);

    //     //check coeffs after reinit
    //     (, amounts) = adapter.getManagedAssets();
    //     (, debtAmounts) = adapter.getDebtAssets();
    //     baseCollateral = amounts[0];
    //     quoteDebt = debtAmounts[0];

    //     //reinit
    //     pool.execute(IHyperCrocPool.CallType.Reinit, 0, 0, 0, false, address(0), 0);

    //     position = pool.positions(address(adapter));
    //     actualBaseCollateral = pool.baseCollateralCoeff().inner.mulDiv(position.discountedBaseAmount, X96_ONE);
    //     actualQuoteDebt = pool.quoteDebtCoeff().inner.mulDiv(position.discountedQuoteAmount, X96_ONE);

    //     assertEq(baseCollateral, actualBaseCollateral, "wrong quote collateral after reinit");
    //     assertEq(quoteDebt, actualQuoteDebt, "wrong quote debt after reinit");
    // }

    // function test_depositBaseCoeffs() public {
    //     IHyperCrocPool pool = IHyperCrocPool(weETH_WETH_POOL);
    //     _openPositionsInPool(weETH_WETH_POOL);
    //     uint256 depositAmount = 1e6;

    //     vm.prank(address(vault));
    //     adapter.deposit(address(weETH), depositAmount, 0, false, address(pool), 0, 0);
    //     //check coeffs before reinit
    //     (, uint256[] memory amounts) = adapter.getManagedAssets();
    //     uint256 baseCollateral = amounts[0];

    //     IHyperCrocPool.Position memory position = pool.positions(address(adapter));
    //     assertEq(uint8(IHyperCrocPool.PositionType.Lend), uint8(position._type));
    //     uint256 actualBaseCollateral = pool.baseCollateralCoeff().inner.mulDiv(position.discountedBaseAmount, X96_ONE);

    //     assertEq(baseCollateral, actualBaseCollateral, "wrong base collateral before reinit");

    //     skip(5 minutes);

    //     //check coeffs after reinit
    //     (, amounts) = adapter.getManagedAssets();
    //     baseCollateral = amounts[0];
    //     uint256 blockTimestamp = block.timestamp;

    //     //reinit
    //     pool.execute(IHyperCrocPool.CallType.Reinit, 0, 0, 0, false, address(0), 0);

    //     assertEq(block.timestamp, blockTimestamp);

    //     position = pool.positions(address(adapter));
    //     actualBaseCollateral = pool.baseCollateralCoeff().inner.mulDiv(position.discountedBaseAmount, X96_ONE);

    //     assertEq(baseCollateral, actualBaseCollateral, "wrong base collateral after reinit");
    // }

    // function test_depositQuoteCoeffs() public {
    //     IHyperCrocPool pool = IHyperCrocPool(weETH_WETH_POOL);
    //     _openPositionsInPool(weETH_WETH_POOL);
    //     uint256 depositAmount = 1e6;

    //     vm.prank(address(vault));
    //     adapter.deposit(address(USDC), depositAmount, 0, false, address(pool), 0, 0);
    //     //check coeffs before reinit
    //     (, uint256[] memory amounts) = adapter.getManagedAssets();
    //     uint256 quoteCollateral = amounts[0];

    //     IHyperCrocPool.Position memory position = pool.positions(address(adapter));
    //     assertEq(uint8(IHyperCrocPool.PositionType.Lend), uint8(position._type));
    //     uint256 actualQuoteCollateral =
    //         pool.quoteCollateralCoeff().inner.mulDiv(position.discountedQuoteAmount, X96_ONE);

    //     assertEq(quoteCollateral, actualQuoteCollateral, "wrong base collateral before reinit");

    //     skip(5 minutes);

    //     //check coeffs after reinit
    //     (, amounts) = adapter.getManagedAssets();
    //     quoteCollateral = amounts[0];
    //     uint256 blockTimestamp = block.timestamp;

    //     //reinit
    //     pool.execute(IHyperCrocPool.CallType.Reinit, 0, 0, 0, false, address(0), 0);

    //     assertEq(block.timestamp, blockTimestamp);

    //     position = pool.positions(address(adapter));
    //     actualQuoteCollateral = pool.quoteCollateralCoeff().inner.mulDiv(position.discountedQuoteAmount, X96_ONE);

    //     assertEq(quoteCollateral, actualQuoteCollateral, "wrong base collateral after reinit");
    // }

    function test_depositQuoteAndLongShouldFailWhenOracleNotExists() public {
        oracle.removePrice(address(USDC), address(USDC));
        uint256 depositAmount = 1e6;
        int256 longAmount = -4e6;

        uint256 swapCallData = IHyperCrocPool(PT_yUSD_USDC_POOL).defaultSwapCallData();
        IHyperCrocPool.FixedPoint memory basePrice = IHyperCrocPool(PT_yUSD_USDC_POOL).getBasePrice();
        uint256 limitPriceX96 = basePrice.inner.mulDiv(110, 100);

        vm.prank(address(vault));
        vm.expectRevert(
            abi.encodeWithSelector(
                HyperCrocPoolAdapter.HyperCrocPoolAdapter__OracleNotExists.selector, address(USDC), address(USDC)
            )
        );
        adapter.deposit(address(USDC), depositAmount, longAmount, false, PT_yUSD_USDC_POOL, limitPriceX96, swapCallData);
    }

    // function test_depositBaseAndShortShouldFailWhenOracleNotExists() public {
    //     oracle.removePrice(address(weETH), address(USDC));
    //     uint256 depositAmount = 1e6;
    //     int256 shortAmount = -4e6;

    //     uint256 swapCallData = IHyperCrocPool(weETH_WETH_POOL).defaultSwapCallData();
    //     IHyperCrocPool.FixedPoint memory basePrice = IHyperCrocPool(weETH_WETH_POOL).getBasePrice();
    //     uint256 limitPriceX96 = basePrice.inner.mulDiv(110, 100);

    //     vm.prank(address(vault));
    //     vm.expectRevert(
    //         abi.encodeWithSelector(
    //             HyperCrocPoolAdapter.HyperCrocPoolAdapter__OracleNotExists.selector, address(weETH), address(USDC)
    //         )
    //     );
    //     adapter.deposit(address(weETH), depositAmount, shortAmount, false, weETH_WETH_POOL, limitPriceX96, swapCallData);
    // }

    function test_depositShouldFailWhenNotAuthorized() public {
        vm.expectRevert(HyperCrocPoolAdapter.HyperCrocPoolAdapter__NotAuthorized.selector);
        adapter.deposit(address(0), 0, 0, false, address(0), 0, 0);
    }

    // function test_depositBaseQuoteShouldFailWhenNotSupported() public {
    //     IHyperCrocPool pool = IHyperCrocPool(weETH_WETH_POOL);
    //     uint256 depositAmount = 1e6;

    //     vm.startPrank(address(vault));
    //     adapter.deposit(address(weETH), depositAmount, 0, false, address(pool), 0, 0);

    //     vm.expectRevert(HyperCrocPoolAdapter.HyperCrocPoolAdapter__NotSupported.selector);
    //     adapter.deposit(address(USDC), depositAmount, 0, false, address(pool), 0, 0);
    // }

    // function test_depositQuoteBaseShouldFailWhenNotSupported() public {
    //     IHyperCrocPool pool = IHyperCrocPool(weETH_WETH_POOL);
    //     uint256 depositAmount = 1e6;

    //     vm.startPrank(address(vault));
    //     adapter.deposit(address(USDC), depositAmount, 0, false, address(pool), 0, 0);

    //     vm.expectRevert(HyperCrocPoolAdapter.HyperCrocPoolAdapter__NotSupported.selector);
    //     adapter.deposit(address(weETH), depositAmount, 0, false, address(pool), 0, 0);
    // }

    function test_partialWithdraw() public {
        // deposit first
        IHyperCrocPool pool = IHyperCrocPool(PT_yUSD_USDC_POOL);
        uint256 depositAmount = 5e6;
        vm.startPrank(address(vault));
        adapter.deposit(address(PT_yUSD), depositAmount, 0, false, address(pool), 0, 0);

        //withdraw
        uint256 withdrawAmount = 4e6;
        adapter.withdraw(address(PT_yUSD), withdrawAmount, address(pool));

        IHyperCrocPool.Position memory position = pool.positions(address(adapter));
        assertEq(uint8(position._type), uint8(IHyperCrocPool.PositionType.Lend));

        _showAssets();
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts[0], depositAmount - withdrawAmount);

        (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        assertEq(debtAssets.length, 1);
        assertEq(debtAmounts[0], 0);

        address[] memory pools = adapter.getPools();
        assertEq(pools.length, 1);
        assertEq(pools[0], address(pool));
    }

    function test_withdrawBase() public {
        // deposit first
        IHyperCrocPool pool = IHyperCrocPool(PT_yUSD_USDC_POOL);
        uint256 depositAmount = 1e6;
        vm.startPrank(address(vault));
        adapter.deposit(address(PT_yUSD), depositAmount, 0, false, address(pool), 0, 0);
        IHyperCrocPool.Position memory position = pool.positions(address(adapter));
        assertEq(uint8(position._type), uint8(IHyperCrocPool.PositionType.Lend));

        //withdraw
        vm.expectEmit(true, true, false, false);
        emit HyperCrocPoolAdapter.PoolRemoved(PT_yUSD_USDC_POOL);
        uint256 withdrawAmount = type(uint256).max;
        adapter.withdraw(address(PT_yUSD), withdrawAmount, address(pool));

        position = pool.positions(address(adapter));
        assertEq(uint8(position._type), uint8(IHyperCrocPool.PositionType.Uninitialized));
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);

        (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        assertEq(debtAssets.length, 0);
        assertEq(debtAmounts.length, 0);
    }

    function test_withdrawQuote() public {
        IHyperCrocPool pool = IHyperCrocPool(PT_yUSD_USDC_POOL);
        uint256 depositAmount = 1e6;
        vm.startPrank(address(vault));
        adapter.deposit(address(USDC), depositAmount, 0, false, address(pool), 0, 0);
        IHyperCrocPool.Position memory position = pool.positions(address(adapter));
        assertEq(uint8(position._type), uint8(IHyperCrocPool.PositionType.Lend));

        //withdraw
        uint256 withdrawAmount = type(uint256).max;
        adapter.withdraw(address(USDC), withdrawAmount, address(pool));

        position = pool.positions(address(adapter));
        assertEq(uint8(position._type), uint8(IHyperCrocPool.PositionType.Uninitialized));
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);

        (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        assertEq(debtAssets.length, 0);
        assertEq(debtAmounts.length, 0);
    }

    function test_withdrawShouldFailWhenNotAuthorized() public {
        vm.expectRevert(HyperCrocPoolAdapter.HyperCrocPoolAdapter__NotAuthorized.selector);
        adapter.withdraw(address(0), 0, address(0));
    }

    // function test_closePosition() public {
    //     //open short position
    //     IHyperCrocPool pool = IHyperCrocPool(weETH_WETH_POOL);
    //     uint256 depositAmount = 1e6;
    //     int256 shortAmount = -2e6;

    //     uint256 swapCallData = pool.defaultSwapCallData();
    //     IHyperCrocPool.FixedPoint memory basePrice = pool.getBasePrice();
    //     uint256 limitPriceX96 = basePrice.inner.mulDiv(90, 100);

    //     vm.startPrank(address(vault));
    //     adapter.deposit(address(weETH), depositAmount, shortAmount, false, address(pool), limitPriceX96, swapCallData);

    //     IHyperCrocPool.Position memory position = pool.positions(address(adapter));
    //     assertEq(uint8(position._type), uint8(IHyperCrocPool.PositionType.Short));

    //     //close position
    //     limitPriceX96 = basePrice.inner.mulDiv(110, 100);
    //     adapter.closePosition(address(pool), false, limitPriceX96, swapCallData);
    //     position = pool.positions(address(adapter));
    //     assertEq(uint8(position._type), uint8(IHyperCrocPool.PositionType.Lend));

    //     (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
    //     assertEq(assets.length, 1);
    //     assertEq(amounts.length, 1);

    //     (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
    //     assertEq(debtAssets.length, 1);
    //     assertEq(debtAmounts.length, 1);
    // }

    function test_closeLongWithWithdrawal() public {
        HyperCrocPoolMock pool = new HyperCrocPoolMock(address(PT_yUSD), address(USDC));
        deal(address(PT_yUSD), address(pool), 10e6);
        deal(address(USDC), address(pool), 10e6);

        vm.startPrank(address(vault));
        adapter.deposit(address(PT_yUSD), 10e6, 0, false, address(pool), 0, 0);

        pool.setPosition(IHyperCrocPool.PositionType.Long, 10e6, 9e6);
        pool.setBasePriceX96(1 << 96);
        uint256 baseBalanceDelta = 1e6;

        uint256 baseBalanceBefore = PT_yUSD.balanceOf(address(pool));
        uint256 quoteBalanceBefore = USDC.balanceOf(address(pool));
        uint256 vaultBaseBalanceBefore = PT_yUSD.balanceOf(address(vault));

        adapter.closePosition(address(pool), true, pool.basePriceX96(), 0);

        IHyperCrocPool.Position memory position = pool.positions(address(adapter));
        assertEq(uint8(position._type), uint8(IHyperCrocPool.PositionType.Uninitialized));

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);

        (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        assertEq(debtAssets.length, 0);
        assertEq(debtAmounts.length, 0);

        assertEq(PT_yUSD.balanceOf(address(pool)), baseBalanceBefore - baseBalanceDelta);
        assertEq(USDC.balanceOf(address(pool)), quoteBalanceBefore);
        assertEq(PT_yUSD.balanceOf(address(vault)), vaultBaseBalanceBefore + baseBalanceDelta);
    }

    function test_closeShortWithWithdrawal() public {
        HyperCrocPoolMock pool = new HyperCrocPoolMock(address(PT_yUSD), address(USDC));
        deal(address(PT_yUSD), address(pool), 10e6);
        deal(address(USDC), address(pool), 10e6);

        vm.startPrank(address(vault));
        adapter.deposit(address(PT_yUSD), 10e6, 0, false, address(pool), 0, 0);

        pool.setPosition(IHyperCrocPool.PositionType.Short, 9e6, 10e6);
        pool.setBasePriceX96(1 << 96);
        uint256 quoteBalanceDelta = 1e6;

        uint256 baseBalanceBefore = PT_yUSD.balanceOf(address(pool));
        uint256 quoteBalanceBefore = USDC.balanceOf(address(pool));
        uint256 vaultQuoteBalanceBefore = USDC.balanceOf(address(vault));

        adapter.closePosition(address(pool), true, pool.basePriceX96(), 0);

        IHyperCrocPool.Position memory position = pool.positions(address(adapter));
        assertEq(uint8(position._type), uint8(IHyperCrocPool.PositionType.Uninitialized));

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);

        (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        assertEq(debtAssets.length, 0);
        assertEq(debtAmounts.length, 0);

        assertEq(PT_yUSD.balanceOf(address(pool)), baseBalanceBefore);
        assertEq(USDC.balanceOf(address(pool)), quoteBalanceBefore - quoteBalanceDelta);
        assertEq(USDC.balanceOf(address(vault)), vaultQuoteBalanceBefore + quoteBalanceDelta);
    }

    function test_closePositionShouldFailWhenNotAuthorized() public {
        vm.expectRevert(HyperCrocPoolAdapter.HyperCrocPoolAdapter__NotAuthorized.selector);
        adapter.closePosition(address(PT_yUSD_USDC_POOL), false, 0, 0);
    }

    function test_sellCollateralLong() public {
        HyperCrocPoolMock pool = new HyperCrocPoolMock(address(PT_yUSD), address(USDC));
        deal(address(PT_yUSD), address(pool), 10e6);
        deal(address(USDC), address(pool), 10e6);

        vm.startPrank(address(vault));
        adapter.deposit(address(PT_yUSD), 1e6, 0, false, address(pool), 0, 0);

        pool.setPosition(IHyperCrocPool.PositionType.Long, 10e6, 9e6);
        pool.setBasePriceX96(1 << 96);
        uint256 expectedPositionQuoteAmount = 1e6;

        uint256 baseBalanceBefore = PT_yUSD.balanceOf(address(pool));
        uint256 quoteBalanceBefore = USDC.balanceOf(address(pool));
        uint256 vaultQuoteBalanceBefore = USDC.balanceOf(address(vault));

        adapter.sellCollateral(address(pool), false, pool.basePriceX96(), 0);

        IHyperCrocPool.Position memory position = pool.positions(address(adapter));
        assertEq(uint8(position._type), uint8(IHyperCrocPool.PositionType.Lend));
        assertEq(position.discountedQuoteAmount, expectedPositionQuoteAmount);

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);

        (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        assertEq(debtAssets.length, 1);
        assertEq(debtAmounts.length, 1);

        assertEq(PT_yUSD.balanceOf(address(pool)), baseBalanceBefore);
        assertEq(USDC.balanceOf(address(pool)), quoteBalanceBefore);
        assertEq(USDC.balanceOf(address(vault)), vaultQuoteBalanceBefore);
    }

    function test_sellCollateralLongWithWithdrawal() public {
        HyperCrocPoolMock pool = new HyperCrocPoolMock(address(PT_yUSD), address(USDC));
        deal(address(PT_yUSD), address(pool), 10e6);
        deal(address(USDC), address(pool), 10e6);

        vm.startPrank(address(vault));
        adapter.deposit(address(PT_yUSD), 10e6, 0, false, address(pool), 0, 0);

        pool.setPosition(IHyperCrocPool.PositionType.Long, 10e6, 9e6);
        pool.setBasePriceX96(1 << 96);
        uint256 quoteBalanceDelta = 1e6;

        uint256 baseBalanceBefore = PT_yUSD.balanceOf(address(pool));
        uint256 quoteBalanceBefore = USDC.balanceOf(address(pool));
        uint256 vaultQuoteBalanceBefore = USDC.balanceOf(address(vault));

        adapter.sellCollateral(address(pool), true, pool.basePriceX96(), 0);

        IHyperCrocPool.Position memory position = pool.positions(address(adapter));
        assertEq(uint8(position._type), uint8(IHyperCrocPool.PositionType.Uninitialized));

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);

        (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        assertEq(debtAssets.length, 0);
        assertEq(debtAmounts.length, 0);

        assertEq(PT_yUSD.balanceOf(address(pool)), baseBalanceBefore);
        assertEq(USDC.balanceOf(address(pool)), quoteBalanceBefore - quoteBalanceDelta);
        assertEq(USDC.balanceOf(address(vault)), vaultQuoteBalanceBefore + quoteBalanceDelta);
    }

    function test_sellCollateralShort() public {
        HyperCrocPoolMock pool = new HyperCrocPoolMock(address(PT_yUSD), address(USDC));
        deal(address(PT_yUSD), address(pool), 10e6);
        deal(address(USDC), address(pool), 10e6);

        vm.startPrank(address(vault));
        adapter.deposit(address(PT_yUSD), 1e6, 0, false, address(pool), 0, 0);

        pool.setPosition(IHyperCrocPool.PositionType.Short, 9e6, 10e6);
        pool.setBasePriceX96(1 << 96);
        uint256 expectedPositionBaseAmount = 1e6;

        uint256 baseBalanceBefore = PT_yUSD.balanceOf(address(pool));
        uint256 quoteBalanceBefore = USDC.balanceOf(address(pool));
        uint256 vaultBaseBalanceBefore = PT_yUSD.balanceOf(address(vault));

        adapter.sellCollateral(address(pool), false, pool.basePriceX96(), 0);

        IHyperCrocPool.Position memory position = pool.positions(address(adapter));
        assertEq(uint8(position._type), uint8(IHyperCrocPool.PositionType.Lend));
        assertEq(position.discountedBaseAmount, expectedPositionBaseAmount);

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);

        (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        assertEq(debtAssets.length, 1);
        assertEq(debtAmounts.length, 1);

        assertEq(PT_yUSD.balanceOf(address(pool)), baseBalanceBefore);
        assertEq(USDC.balanceOf(address(pool)), quoteBalanceBefore);
        assertEq(PT_yUSD.balanceOf(address(vault)), vaultBaseBalanceBefore);
    }

    function test_sellCollateralShortWithWithdrawal() public {
        HyperCrocPoolMock pool = new HyperCrocPoolMock(address(PT_yUSD), address(USDC));
        deal(address(PT_yUSD), address(pool), 10e6);
        deal(address(USDC), address(pool), 10e6);

        vm.startPrank(address(vault));
        adapter.deposit(address(PT_yUSD), 10e6, 0, false, address(pool), 0, 0);

        pool.setPosition(IHyperCrocPool.PositionType.Short, 9e6, 10e6);
        pool.setBasePriceX96(1 << 96);
        uint256 baseBalanceDelta = 1e6;

        uint256 baseBalanceBefore = PT_yUSD.balanceOf(address(pool));
        uint256 quoteBalanceBefore = USDC.balanceOf(address(pool));
        uint256 vaultBaseBalanceBefore = PT_yUSD.balanceOf(address(vault));

        adapter.sellCollateral(address(pool), true, pool.basePriceX96(), 0);

        IHyperCrocPool.Position memory position = pool.positions(address(adapter));
        assertEq(uint8(position._type), uint8(IHyperCrocPool.PositionType.Uninitialized));

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);

        (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        assertEq(debtAssets.length, 0);
        assertEq(debtAmounts.length, 0);

        assertEq(PT_yUSD.balanceOf(address(pool)), baseBalanceBefore - baseBalanceDelta);
        assertEq(USDC.balanceOf(address(pool)), quoteBalanceBefore);
        assertEq(PT_yUSD.balanceOf(address(vault)), vaultBaseBalanceBefore + baseBalanceDelta);
    }

    function test_sellCollateralShouldFailWhenNotAuthorized() public {
        vm.expectRevert(HyperCrocPoolAdapter.HyperCrocPoolAdapter__NotAuthorized.selector);
        adapter.sellCollateral(address(PT_yUSD_USDC_POOL), false, 0, 0);
    }

    function test_long() public {
        IHyperCrocPool pool = IHyperCrocPool(PT_yUSD_USDC_POOL);
        uint256 depositAmount = 1e6;
        uint256 longAmount = 3e6; // long 3 WETH

        uint256 swapCallData = pool.defaultSwapCallData();
        uint256 limitPriceX96 = pool.getBasePrice().inner.mulDiv(110, 100);

        vm.startPrank(address(vault));
        adapter.deposit(address(PT_yUSD), depositAmount, 0, false, address(pool), 0, 0);
        adapter.long(longAmount, false, address(pool), limitPriceX96, swapCallData);
        skip(5 minutes);

        IHyperCrocPool.Position memory position = pool.positions(address(adapter));
        assertEq(uint8(position._type), uint8(IHyperCrocPool.PositionType.Long));

        assertEq(USDC.balanceOf(address(adapter)), 0);
        assertEq(PT_yUSD.balanceOf(address(adapter)), 0);

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(PT_yUSD));
        assertApproxEqAbs(amounts[0], depositAmount + longAmount, 10);

        (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        assertEq(debtAssets.length, 1);
        assertEq(debtAssets[0], address(USDC));

        assertEq(debtAmounts.length, 1);
        assertTrue(debtAmounts[0] > 0);

        _showAssets();
    }

    function test_longShouldFailWhenNotAuthorized() public {
        vm.expectRevert(HyperCrocPoolAdapter.HyperCrocPoolAdapter__NotAuthorized.selector);
        adapter.long(0, false, address(PT_yUSD_USDC_POOL), 0, 0);
    }

    // function test_short() public {
    //     uint256 depositAmount = 1e6;
    //     uint256 shortAmount = 4e6;
    //     IHyperCrocPool pool = IHyperCrocPool(weETH_WETH_POOL);

    //     uint256 swapCallData = pool.defaultSwapCallData();
    //     uint256 limitPriceX96 = pool.getBasePrice().inner.mulDiv(90, 100);

    //     vm.startPrank(address(vault));
    //     adapter.deposit(address(weETH), depositAmount, 0, false, address(pool), 0, 0);
    //     adapter.short(shortAmount, false, address(pool), limitPriceX96, swapCallData);
    //     skip(5 minutes);

    //     IHyperCrocPool.Position memory position = pool.positions(address(adapter));
    //     assertEq(uint8(position._type), uint8(IHyperCrocPool.PositionType.Short));

    //     assertEq(USDC.balanceOf(address(adapter)), 0);
    //     assertEq(weETH.balanceOf(address(adapter)), 0);

    //     (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
    //     assertEq(assets.length, 1);
    //     assertEq(amounts.length, 1);
    //     assertEq(assets[0], address(USDC));
    //     assertTrue(amounts[0] > 0);

    //     (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
    //     assertEq(debtAssets.length, 1);
    //     assertEq(debtAssets[0], address(weETH));

    //     assertEq(debtAmounts.length, 1);
    //     assertGe(debtAmounts[0], shortAmount);

    //     _showAssets();
    // }

    function test_shortShouldFailWhenNoAuthorized() public {
        vm.expectRevert(HyperCrocPoolAdapter.HyperCrocPoolAdapter__NotAuthorized.selector);
        adapter.short(0, false, address(PT_yUSD_USDC_POOL), 0, 0);
    }

    function test_depositQuoteLong() public {
        IHyperCrocPool pool = IHyperCrocPool(PT_yUSD_USDC_POOL);
        uint256 depositAmount = 1e6; // deposit 1 WETH and flip to PT-weETH
        int256 longAmount = -3e6; // long 3 WETH

        uint256 swapCallData = pool.defaultSwapCallData();
        uint256 limitPriceX96 = pool.getBasePrice().inner.mulDiv(110, 100);

        vm.prank(address(vault));
        adapter.deposit(address(USDC), depositAmount, longAmount, false, address(pool), limitPriceX96, swapCallData);

        assertEq(USDC.balanceOf(address(adapter)), 0);
        assertEq(PT_yUSD.balanceOf(address(adapter)), 0);

        IHyperCrocPool.Position memory position = pool.positions(address(adapter));
        assertEq(uint8(position._type), uint8(IHyperCrocPool.PositionType.Long));

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(assets[0], address(PT_yUSD));

        assertEq(amounts.length, 1);
        assertTrue(amounts[0] > 0);

        (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        assertEq(debtAssets.length, 1);
        assertEq(debtAssets[0], address(USDC));

        assertEq(debtAmounts.length, 1);
        assertTrue(debtAmounts[0] > 0);

        _showAssets();
    }

    function test_depositBaseAndLong() public {
        IHyperCrocPool pool = IHyperCrocPool(PT_yUSD_USDC_POOL);
        uint256 depositAmount = 1e6;
        int256 longAmount = 3e6; // long 3 WETH

        uint256 swapCallData = pool.defaultSwapCallData();
        uint256 limitPriceX96 = pool.getBasePrice().inner.mulDiv(110, 100);

        vm.prank(address(vault));
        adapter.deposit(address(PT_yUSD), depositAmount, longAmount, false, address(pool), limitPriceX96, swapCallData);

        assertEq(USDC.balanceOf(address(adapter)), 0);
        assertEq(PT_yUSD.balanceOf(address(adapter)), 0);

        IHyperCrocPool.Position memory position = pool.positions(address(adapter));
        assertEq(uint8(position._type), uint8(IHyperCrocPool.PositionType.Long));

        _showAssets();
    }

    function test_depositTwoTimes() public {
        uint256 depositAmount = 1e6; // deposit 1 WETH and flip to PT-weETH
        deal(address(USDC), address(vault), depositAmount * 2);

        vm.startPrank(address(vault));
        adapter.deposit(address(USDC), depositAmount, 0, false, PT_yUSD_USDC_POOL, 0, 0);
        adapter.deposit(address(USDC), depositAmount, 0, false, PT_yUSD_USDC_POOL, 0, 0);

        assertEq(USDC.balanceOf(address(adapter)), 0);
        assertEq(PT_yUSD.balanceOf(address(adapter)), 0);

        address[] memory pools = adapter.getPools();
        assertEq(pools.length, 1);
        assertEq(pools[0], address(PT_yUSD_USDC_POOL));
    }

    function test_removePoolsAfterWithdraw() public {
        uint256 depositAmount = 1e6; // deposit 1 WETH and flip to PT-weETH
        deal(address(USDC), address(vault), depositAmount * 2);

        vm.startPrank(address(vault));
        adapter.deposit(address(USDC), depositAmount, 0, false, PT_yUSD_USDC_POOL, 0, 0);
        // adapter.deposit(address(USDC), depositAmount, 0, false, weETH_WETH_POOL, 0, 0);

        adapter.withdraw(address(USDC), type(uint256).max, PT_yUSD_USDC_POOL);
        address[] memory pools = adapter.getPools();
        assertEq(pools.length, 0);
        // assertEq(pools[0], address(weETH_WETH_POOL));
    }

    function test_emergencyWithdrawQuote() public {
        //deposit quote
        HyperCrocPoolMock pool = new HyperCrocPoolMock(address(PT_yUSD), address(USDC));
        deal(address(PT_yUSD), address(pool), 10e6);
        deal(address(USDC), address(pool), 10e6);

        uint256 depositAmount = 1e6;
        deal(address(USDC), address(vault), depositAmount * 2);
        vm.startPrank(address(vault));
        adapter.deposit(address(USDC), depositAmount, 0, false, address(pool), 0, 0);

        pool.setPosition(IHyperCrocPool.PositionType.Lend, depositAmount, 0);
        pool.setMode(IHyperCrocPool.Mode.LongEmergency);

        uint256 baseBalanceBefore = USDC.balanceOf(address(vault));

        //emergencyWithdraw
        adapter.emergencyWithdraw(address(pool));

        assertEq(USDC.balanceOf(address(adapter)), 0);
        assertEq(PT_yUSD.balanceOf(address(adapter)), 0);
        assertGe(USDC.balanceOf(address(vault)), baseBalanceBefore);

        address[] memory pools = adapter.getPools();
        assertEq(pools.length, 0);
    }

    function test_emergencyWithdrawBase() public {
        //deposit base
        HyperCrocPoolMock pool = new HyperCrocPoolMock(address(PT_yUSD), address(USDC));
        deal(address(PT_yUSD), address(pool), 10e6);
        deal(address(USDC), address(pool), 10e6);

        uint256 depositAmount = 1e6;
        deal(address(PT_yUSD), address(vault), depositAmount * 2);
        vm.startPrank(address(vault));
        adapter.deposit(address(PT_yUSD), depositAmount, 0, false, address(pool), 0, 0);

        pool.setPosition(IHyperCrocPool.PositionType.Lend, depositAmount, 0);
        pool.setMode(IHyperCrocPool.Mode.ShortEmergency);
        uint256 baseBalanceBefore = PT_yUSD.balanceOf(address(vault));

        //emergencyWithdraw
        adapter.emergencyWithdraw(address(pool));

        assertEq(USDC.balanceOf(address(adapter)), 0);
        assertEq(PT_yUSD.balanceOf(address(adapter)), 0);
        assertGe(PT_yUSD.balanceOf(address(vault)), baseBalanceBefore);

        address[] memory pools = adapter.getPools();
        assertEq(pools.length, 0);
    }

    function test_emergencyWithdraw_ShortAndShortEmergency() public {
        //deposit quote
        HyperCrocPoolMock pool = new HyperCrocPoolMock(address(PT_yUSD), address(USDC));
        deal(address(PT_yUSD), address(pool), 10e6);
        deal(address(USDC), address(pool), 10e6);

        uint256 depositAmount = 1e6;
        uint256 shortAmount = 2e6;
        deal(address(USDC), address(vault), depositAmount);
        vm.startPrank(address(vault));
        adapter.deposit(address(USDC), depositAmount, 0, false, address(pool), 0, 0);

        pool.setPosition(IHyperCrocPool.PositionType.Short, depositAmount, shortAmount);
        pool.setMode(IHyperCrocPool.Mode.ShortEmergency);

        uint256 baseBalanceBefore = USDC.balanceOf(address(vault));

        //emergencyWithdraw
        adapter.emergencyWithdraw(address(pool));

        assertEq(USDC.balanceOf(address(adapter)), 0);
        assertEq(PT_yUSD.balanceOf(address(adapter)), 0);
        assertEq(USDC.balanceOf(address(vault)), baseBalanceBefore);

        address[] memory pools = adapter.getPools();
        assertEq(pools.length, 0);
    }

    function test_emergencyWithdrawLongAndLongEmergency() public {
        //deposit base
        HyperCrocPoolMock pool = new HyperCrocPoolMock(address(PT_yUSD), address(USDC));
        deal(address(PT_yUSD), address(pool), 10e6);
        deal(address(USDC), address(pool), 10e6);

        uint256 depositAmount = 1e6;
        uint256 longAmount = 3e6;
        deal(address(PT_yUSD), address(vault), depositAmount * 2);
        vm.startPrank(address(vault));
        adapter.deposit(address(PT_yUSD), depositAmount, 0, false, address(pool), 0, 0);

        pool.setPosition(IHyperCrocPool.PositionType.Long, depositAmount, longAmount);
        pool.setMode(IHyperCrocPool.Mode.LongEmergency);
        uint256 baseBalanceBefore = PT_yUSD.balanceOf(address(vault));

        //emergencyWithdraw
        adapter.emergencyWithdraw(address(pool));

        assertEq(USDC.balanceOf(address(adapter)), 0);
        assertEq(PT_yUSD.balanceOf(address(adapter)), 0);
        assertEq(PT_yUSD.balanceOf(address(vault)), baseBalanceBefore);

        address[] memory pools = adapter.getPools();
        assertEq(pools.length, 0);
    }

    function test_emergencyWithdrawLongAndShortEmergency() public {
        //deposit base
        HyperCrocPoolMock pool = new HyperCrocPoolMock(address(PT_yUSD), address(USDC));
        deal(address(PT_yUSD), address(pool), 10e6);
        deal(address(USDC), address(pool), 10e6);

        uint256 depositAmount = 1e6;
        uint256 longAmount = 3e6;
        deal(address(PT_yUSD), address(vault), depositAmount * 2);
        vm.startPrank(address(vault));
        adapter.deposit(address(PT_yUSD), depositAmount, 0, false, address(pool), 0, 0);

        pool.setPosition(IHyperCrocPool.PositionType.Long, depositAmount, longAmount);
        pool.setMode(IHyperCrocPool.Mode.ShortEmergency);
        uint256 baseBalanceBefore = PT_yUSD.balanceOf(address(vault));

        //emergencyWithdraw
        adapter.emergencyWithdraw(address(pool));

        assertEq(USDC.balanceOf(address(adapter)), 0);
        assertEq(PT_yUSD.balanceOf(address(adapter)), 0);
        assertGt(PT_yUSD.balanceOf(address(vault)), baseBalanceBefore);

        address[] memory pools = adapter.getPools();
        assertEq(pools.length, 0);
    }

    function test_emergencyWithdrawShortAndLongEmergency() public {
        //deposit quote
        HyperCrocPoolMock pool = new HyperCrocPoolMock(address(PT_yUSD), address(USDC));
        deal(address(PT_yUSD), address(pool), 10e6);
        deal(address(USDC), address(pool), 10e6);

        uint256 depositAmount = 1e6;
        uint256 shortAmount = 2e6;
        deal(address(USDC), address(vault), depositAmount);
        vm.startPrank(address(vault));
        adapter.deposit(address(USDC), depositAmount, 0, false, address(pool), 0, 0);

        pool.setPosition(IHyperCrocPool.PositionType.Short, depositAmount, shortAmount);
        pool.setMode(IHyperCrocPool.Mode.LongEmergency);

        uint256 baseBalanceBefore = USDC.balanceOf(address(vault));

        //emergencyWithdraw
        adapter.emergencyWithdraw(address(pool));

        assertEq(USDC.balanceOf(address(adapter)), 0);
        assertEq(PT_yUSD.balanceOf(address(adapter)), 0);
        assertGt(USDC.balanceOf(address(vault)), baseBalanceBefore);

        address[] memory pools = adapter.getPools();
        assertEq(pools.length, 0);
    }

    function test_emergencyWithdrawShouldFailWhenWrongHyperCrocPoolMode() public {
        uint256 depositAmount = 1e6; // deposit 1 WETH and flip to PT-weETH
        deal(address(USDC), address(vault), depositAmount * 2);

        vm.startPrank(address(vault));
        adapter.deposit(address(USDC), depositAmount, 0, false, PT_yUSD_USDC_POOL, 0, 0);

        vm.expectRevert(HyperCrocPoolAdapter.HyperCrocPoolAdapter__WrongHyperCrocPoolMode.selector);
        adapter.emergencyWithdraw(PT_yUSD_USDC_POOL);
    }

    function test_addPool() public {
        HyperCrocPoolAdapterHarness harness = new HyperCrocPoolAdapterHarness(address(1));
        harness.exposed_addPool(address(2));
        harness.exposed_addPool(address(3));
        harness.exposed_addPool(address(4));

        address[] memory pools = harness.getPools();
        assertEq(pools.length, 3);
        assertEq(pools[0], address(2));
        assertEq(pools[1], address(3));
        assertEq(pools[2], address(4));

        assertEq(harness.getPoolPosition(address(2)), 1);
        assertEq(harness.getPoolPosition(address(3)), 2);
        assertEq(harness.getPoolPosition(address(4)), 3);

        harness.exposed_removePool(address(2));
        assertEq(harness.getPoolPosition(address(4)), 1);
        assertEq(harness.getPoolPosition(address(3)), 2);
    }

    function test_removePoolShouldFail() public {
        HyperCrocPoolAdapterHarness harness = new HyperCrocPoolAdapterHarness(address(1));
        vm.expectRevert(HyperCrocPoolAdapter.HyperCrocPoolAdapter__NoPool.selector);
        harness.exposed_removePool(address(1));
    }

    function _showAssets() private view {
        address[] memory hyperCrocPools = adapter.getPools();
        console.log("Pool positions:");
        for (uint256 i = 0; i < hyperCrocPools.length; i++) {
            _showPosition(hyperCrocPools[i]);
        }

        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        console.log("Managed assets:");
        for (uint256 i = 0; i < assets.length; i++) {
            console.log(" ", ERC20(assets[i]).symbol(), amounts[i]);
        }

        console.log("Debt assets:");
        (address[] memory debtAssets, uint256[] memory debtAmounts) = adapter.getDebtAssets();
        for (uint256 i = 0; i < debtAssets.length; i++) {
            if (debtAssets[i] != address(0)) {
                console.log(" ", ERC20(debtAssets[i]).symbol(), debtAmounts[i]);
            }
        }
    }

    function _showPosition(address pool) private view {
        IHyperCrocPool.Position memory position = IHyperCrocPool(pool).positions(address(adapter));

        string memory typeStr = "Uninitialized";
        if (position._type == IHyperCrocPool.PositionType.Lend) {
            typeStr = "Lend";
        } else if (position._type == IHyperCrocPool.PositionType.Short) {
            typeStr = "Short";
        } else if (position._type == IHyperCrocPool.PositionType.Long) {
            typeStr = "Long";
        }

        console.log(
            " ", ERC20(IHyperCrocPool(pool).baseToken()).symbol(), "/", ERC20(IHyperCrocPool(pool).quoteToken()).symbol()
        );
        console.log("   type: ", typeStr);
        console.log("   base  amount: ", position.discountedBaseAmount);
        console.log("   quote amount: ", position.discountedQuoteAmount);
    }

    function _openPositionsInPool(address pool) private {
        ERC20 quoteToken = ERC20(IHyperCrocPool(pool).quoteToken());
        ERC20 baseToken = ERC20(IHyperCrocPool(pool).baseToken());

        uint256 quoteDepositAmount = 1 * 10 ** quoteToken.decimals();
        uint256 baseDepositAmount = 1 * 10 ** baseToken.decimals();

        {
            address longer = makeAddr("LONGER");
            int256 longAmount = 5 * int256(baseDepositAmount);
            deal(address(baseToken), address(longer), baseDepositAmount);
            startHoax(longer);
            baseToken.approve(pool, baseDepositAmount);
            IHyperCrocPool(pool).execute(
                IHyperCrocPool.CallType.DepositBase,
                baseDepositAmount,
                longAmount,
                IHyperCrocPool(pool).getBasePrice().inner.mulDiv(110, 100),
                false,
                address(0),
                IHyperCrocPool(pool).defaultSwapCallData()
            );
            vm.stopPrank();
        }

        {
            address shorter = makeAddr("SHORTER");
            int256 shortAmount = 5 * int256(baseDepositAmount);
            deal(address(quoteToken), address(shorter), quoteDepositAmount);
            startHoax(shorter);
            quoteToken.approve(pool, quoteDepositAmount);
            IHyperCrocPool(pool).execute(
                IHyperCrocPool.CallType.DepositQuote,
                quoteDepositAmount,
                shortAmount,
                IHyperCrocPool(pool).getBasePrice().inner.mulDiv(90, 100),
                false,
                address(0),
                IHyperCrocPool(pool).defaultSwapCallData()
            );
            vm.stopPrank();
        }
    }

    function _fundHyperCrocPool(address pool) private {
        address user = makeAddr("funder");
        ERC20 quoteToken = ERC20(IHyperCrocPool(pool).quoteToken());
        ERC20 baseToken = ERC20(IHyperCrocPool(pool).baseToken());

        uint256 quoteDepositAmount = 100 * 10 ** quoteToken.decimals();
        uint256 baseDepositAmount = 100 * 10 ** baseToken.decimals();

        deal(address(quoteToken), address(user), quoteDepositAmount);
        deal(address(baseToken), address(user), baseDepositAmount);
        vm.deal(user, 1 ether);
        vm.startPrank(user);

        quoteToken.approve(pool, quoteDepositAmount);
        IHyperCrocPool(pool).execute(
            IHyperCrocPool.CallType.DepositQuote,
            quoteDepositAmount,
            0,
            0,
            false,
            address(0),
            IHyperCrocPool(pool).defaultSwapCallData()
        );

        baseToken.approve(pool, baseDepositAmount);
        IHyperCrocPool(pool).execute(
            IHyperCrocPool.CallType.DepositBase,
            baseDepositAmount,
            0,
            0,
            false,
            address(0),
            IHyperCrocPool(pool).defaultSwapCallData()
        );

        vm.stopPrank();
    }
}
