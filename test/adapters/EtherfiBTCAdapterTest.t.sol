// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {HyperCrocVaultFactory} from "../../contracts/HyperCrocVaultFactory.sol";
import {HyperCrocVault} from "../../contracts/HyperCrocVault.sol";
import {WithdrawalQueue} from "../../contracts/WithdrawalQueue.sol";
import {EtherfiBTCAdapter} from "../../contracts/adapters/etherfi/EtherfiBTCAdapter.sol";
import {AdapterBase} from "../../contracts/adapters/AdapterBase.sol";
import {IAtomicQueue} from "../../contracts/adapters/etherfi/interfaces/IAtomicQueue.sol";
import {ILiquidityPool} from "../../contracts/adapters/etherfi/interfaces/ILiquidityPool.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";

interface IWithdrawRequestNFTAdmin {
    function finalizeRequests(uint256 requestId) external;
    function nextRequestId() external view returns (uint256);
    function isFinalized(uint256 requestId) external view returns (bool);
    function isValid(uint256 requestId) external view returns (bool);
    function getClaimableAmount(uint256 requestId) external view returns (uint256);
}

interface IAtomicSolver {
    function redeemSolve(
        address queue,
        IERC20 offer,
        IERC20 want,
        address[] calldata users,
        uint256 minimumAssetsOut,
        uint256 maxAssets,
        address teller
    ) external;
}

contract EtherfiBTCAdapterTest is Test {
    using Math for uint256;

    uint256 public constant FORK_BLOCK = 23532800;

    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 private constant WBTC = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    IERC20 private constant EBTC = IERC20(0x657e8C867D8B37dCC18fA4Caead9C45EB088C642);
    address private constant LAYER_ZERO_TELLER = 0x6Ee3aaCcf9f2321E49063C4F8da775DdBd407268;
    address private constant ATOMIC_QUEUE = 0xD45884B592E316eB816199615A95C182F75dea07;
    IAtomicSolver private constant ATOMIC_SOLVER = IAtomicSolver(0x989468982b08AEfA46E37CD0086142A86fa466D7);
    address private constant SOLVER_ADMIN = 0xf8553c8552f906C19286F21711721E206EE4909E;

    address private NO_ACCESS = makeAddr("NO_ACCESS");

    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    EtherfiBTCAdapter private adapter;
    HyperCrocVault private hyperCrocVault;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl), FORK_BLOCK);

        EulerRouterMock oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE().mulDiv(100_000, 10 ** 2), address(WBTC), address(USDC));
        oracle.setPrice(oracle.ONE().mulDiv(100_000, 10 ** 2), address(EBTC), address(USDC));

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
        hyperCrocVault.setMaxExternalPositionAdapters(type(uint8).max);
        hyperCrocVault.setMaxTrackedAssets(type(uint8).max);

        adapter =
            new EtherfiBTCAdapter(address(hyperCrocVault), address(WBTC), address(EBTC), LAYER_ZERO_TELLER, ATOMIC_QUEUE);
        hyperCrocVault.addAdapter(address(adapter));
        assertNotEq(hyperCrocVault.externalPositionAdapterPosition(address(adapter)), 0);

        deal(address(WBTC), address(hyperCrocVault), 10 * 10 ** 8);

        hyperCrocVault.addTrackedAsset(address(EBTC));
        hyperCrocVault.addTrackedAsset(address(WBTC));
    }

    function testDepositBtc() public {
        uint256 wbtcBalanceBefore = WBTC.balanceOf(address(hyperCrocVault));
        uint256 depositAmount = 10 ** 8;
        vm.prank(address(hyperCrocVault));
        uint256 shares = adapter.deposit(depositAmount, 0);

        assertEq(wbtcBalanceBefore - WBTC.balanceOf(address(hyperCrocVault)), depositAmount);
        assertEq(EBTC.balanceOf(address(hyperCrocVault)), shares);
        assertEq(WBTC.balanceOf(address(adapter)), 0);
        assertEq(EBTC.balanceOf(address(adapter)), 0);

        _assertAdapterAssets(0, 0);
    }

    function testDepositBtcAllExcept() public {
        uint256 exceptAmount = 9 * 10 ** 8;
        vm.prank(address(hyperCrocVault));
        uint256 shares = adapter.depositAllExcept(exceptAmount, 0);

        assertEq(WBTC.balanceOf(address(hyperCrocVault)), exceptAmount);
        assertEq(EBTC.balanceOf(address(hyperCrocVault)), shares);
        assertEq(WBTC.balanceOf(address(adapter)), 0);
        assertEq(EBTC.balanceOf(address(adapter)), 0);

        _assertAdapterAssets(0, 0);
    }

    function testDepositBtcNoAccess() public {
        uint256 depositAmount = 10 ** 8;
        vm.prank(NO_ACCESS);
        vm.expectRevert(abi.encodeWithSelector(EtherfiBTCAdapter.NoAccess.selector));
        adapter.deposit(depositAmount, 0);
    }

    function testRequestWithdrawBtc() public {
        uint256 depositAmount = 2 * 10 ** 8;
        vm.prank(address(hyperCrocVault));
        uint256 shares = adapter.deposit(depositAmount, 0);

        uint88 price = 10 ** 8;
        uint64 deadline = type(uint64).max;
        uint256 withdrawAmount = shares;

        vm.prank(address(hyperCrocVault));
        adapter.requestWithdraw(uint96(withdrawAmount), price, deadline);

        IAtomicQueue.AtomicRequest memory request =
            IAtomicQueue(ATOMIC_QUEUE).getUserAtomicRequest(address(adapter), EBTC, WBTC);

        assertEq(request.deadline, deadline);
        assertEq(request.atomicPrice, price);
        assertEq(request.offerAmount, withdrawAmount);
        assert(!request.inSolve);

        assertEq(WBTC.balanceOf(address(adapter)), 0);
        assertEq(EBTC.balanceOf(address(adapter)), shares);

        _assertAdapterAssets(0, withdrawAmount);
    }

    function testRequestWithdrawBtcAllExcept() public {
        uint256 depositAmount = 2 * 10 ** 8;
        vm.prank(address(hyperCrocVault));
        uint256 shares = adapter.deposit(depositAmount, 0);

        uint88 price = 10 ** 8;
        uint64 deadline = type(uint64).max;

        vm.prank(address(hyperCrocVault));
        uint96 except = uint96(1 * 10 ** 8);
        uint256 withdrawAmount = shares - except;
        adapter.requestWithdrawAllExcept(except, price, deadline);

        IAtomicQueue.AtomicRequest memory request =
            IAtomicQueue(ATOMIC_QUEUE).getUserAtomicRequest(address(adapter), EBTC, WBTC);

        assertEq(request.deadline, deadline);
        assertEq(request.atomicPrice, price);
        assertEq(request.offerAmount, withdrawAmount);
        assert(!request.inSolve);

        assertEq(WBTC.balanceOf(address(adapter)), 0);
        assertEq(EBTC.balanceOf(address(adapter)), withdrawAmount);

        _assertAdapterAssets(0, withdrawAmount);
    }

    function testRequestWithdrawBtcNoAccess() public {
        uint256 withdrawAmount = 10 ** 8;
        vm.prank(NO_ACCESS);
        vm.expectRevert(abi.encodeWithSelector(EtherfiBTCAdapter.NoAccess.selector));
        adapter.requestWithdraw(uint96(withdrawAmount), 10 ** 8, type(uint64).max);
    }

    function testClaimWithdrawBtc() public {
        uint256 depositAmount = 2 * 10 ** 8;
        vm.prank(address(hyperCrocVault));
        uint256 shares = adapter.deposit(depositAmount, 0);

        uint88 price = 10 ** 8;
        uint64 deadline = type(uint64).max;
        uint256 withdrawAmount = shares;

        vm.prank(address(hyperCrocVault));
        adapter.requestWithdraw(uint96(withdrawAmount), price, deadline);

        _prankResolve();

        uint256 expectedBalance = withdrawAmount.mulDiv(price, 10 ** 8);
        _assertAdapterAssets(expectedBalance, 0);

        uint256 balanceBefore = WBTC.balanceOf(address(hyperCrocVault));

        vm.prank(address(hyperCrocVault));
        adapter.claimWithdraw();

        assertEq(WBTC.balanceOf(address(hyperCrocVault)) - balanceBefore, expectedBalance);
        assertEq(EBTC.balanceOf(address(hyperCrocVault)), 0);
        assertEq(WBTC.balanceOf(address(adapter)), 0);
        assertEq(EBTC.balanceOf(address(adapter)), 0);

        _assertAdapterAssets(0, 0);
    }

    function testClaimWithdrawBtcNoAccess() public {
        vm.prank(NO_ACCESS);
        vm.expectRevert(abi.encodeWithSelector(EtherfiBTCAdapter.NoAccess.selector));
        adapter.claimWithdraw();
    }

    function testCancelWithdrawBtc() public {
        uint256 depositAmount = 10 ** 8;
        vm.prank(address(hyperCrocVault));
        uint256 shares = adapter.deposit(depositAmount, 0);

        vm.prank(address(hyperCrocVault));
        adapter.requestWithdraw(uint96(shares), 10 ** 8, type(uint64).max);

        assertEq(WBTC.balanceOf(address(adapter)), 0);
        assertEq(EBTC.balanceOf(address(adapter)), shares);

        vm.prank(address(hyperCrocVault));
        adapter.cancelWithdrawRequest();

        IAtomicQueue.AtomicRequest memory request =
            IAtomicQueue(ATOMIC_QUEUE).getUserAtomicRequest(address(adapter), EBTC, WBTC);

        assertEq(request.deadline, 0);
        assertEq(request.atomicPrice, 0);
        assertEq(request.offerAmount, 0);
        assert(!request.inSolve);

        assertEq(EBTC.allowance(address(adapter), ATOMIC_QUEUE), 0);
    }

    function testCancelWithdrawRequestBtcNoAccess() public {
        vm.prank(NO_ACCESS);
        vm.expectRevert(abi.encodeWithSelector(EtherfiBTCAdapter.NoAccess.selector));
        adapter.cancelWithdrawRequest();
    }

    function testGetManagedAssetsSenderNotVault() public {
        uint256 wbtcAmount = 10 * 10 ** 8;
        uint256 ebtcAmount = 10 ** 8;
        deal(address(WBTC), address(adapter), wbtcAmount);
        deal(address(EBTC), address(adapter), ebtcAmount);

        _assertAdapterAssets(wbtcAmount, ebtcAmount);

        vm.prank(NO_ACCESS);
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 2);
        assertEq(amounts.length, 2);
        assertEq(assets[0], address(WBTC));
        assertEq(assets[1], address(EBTC));
        assertEq(amounts[0], 0);
        assertEq(amounts[1], 0);
    }

    function _assertAdapterAssets(uint256 expectedWbtc, uint256 expectedEbtc) private {
        vm.prank(address(hyperCrocVault));
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 2);
        assertEq(amounts.length, 2);
        assertEq(assets[0], address(WBTC));
        assertEq(assets[1], address(EBTC));
        assertEq(amounts[0], expectedWbtc);
        assertEq(amounts[1], expectedEbtc);

        (assets, amounts) = adapter.getManagedAssets(address(hyperCrocVault));
        assertEq(assets.length, 2);
        assertEq(amounts.length, 2);
        assertEq(assets[0], address(WBTC));
        assertEq(assets[1], address(EBTC));
        assertEq(amounts[0], expectedWbtc);
        assertEq(amounts[1], expectedEbtc);

        _assertNoDebtAssets();
    }

    function _assertNoDebtAssets() private {
        vm.prank(address(hyperCrocVault));
        (address[] memory assets, uint256[] memory amounts) = adapter.getDebtAssets();
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);
    }

    function _prankResolve() private {
        address[] memory users = new address[](1);
        users[0] = address(adapter);

        vm.prank(SOLVER_ADMIN);
        ATOMIC_SOLVER.redeemSolve(ATOMIC_QUEUE, EBTC, WBTC, users, 0, type(uint256).max, LAYER_ZERO_TELLER);
    }
}
