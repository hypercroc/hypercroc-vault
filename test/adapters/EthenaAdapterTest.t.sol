// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {console} from "lib/forge-std/src/console.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {HyperCrocVaultFactory} from "../../contracts/HyperCrocVaultFactory.sol";
import {HyperCrocVault} from "../../contracts/HyperCrocVault.sol";
import {WithdrawalQueue} from "../../contracts/WithdrawalQueue.sol";
import {IStakedUSDe} from "../../contracts/adapters/ethena/interfaces/IStakedUSDe.sol";
import {EthenaAdapter} from "../../contracts/adapters/ethena/EthenaAdapter.sol";
import {AdapterBase} from "../../contracts/adapters/AdapterBase.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";

interface IStakedUSDeAdmin {
    function setCooldownDuration(uint24 duration) external;
    function owner() external view returns (address);
}

contract EthenaAdapterTest is Test {
    using Math for uint256;

    uint256 public constant FORK_BLOCK = 22515980;

    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IStakedUSDe private constant S_USDE = IStakedUSDe(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);
    IERC20 private constant USDE = IERC20(0x4c9EDD5852cd905f086C759E8383e09bff1E68B3);

    address private NO_ACCESS = makeAddr("NO_ACCESS");

    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    EthenaAdapter private adapter;
    HyperCrocVault private hyperCrocVault;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl), FORK_BLOCK);

        EulerRouterMock oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE(), address(USDE), address(USDC));
        oracle.setPrice(oracle.ONE().mulDiv(117, 100), address(S_USDE), address(USDC));

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

        adapter = new EthenaAdapter(address(hyperCrocVault), address(S_USDE));
        hyperCrocVault.addAdapter(address(adapter));
        assertNotEq(hyperCrocVault.externalPositionAdapterPosition(address(adapter)), 0);

        deal(address(USDE), address(hyperCrocVault), 10 ** 12);

        hyperCrocVault.addTrackedAsset(address(USDE));
        hyperCrocVault.addTrackedAsset(address(S_USDE));
    }

    function testSetup() public view {
        assertEq(address(adapter.stakedUSDe()), address(S_USDE));
        assertEq(adapter.USDe(), address(USDE));
    }

    function testDeposit() public {
        uint256 usdeBalanceBefore = USDE.balanceOf(address(hyperCrocVault));
        uint256 depositAmount = 1000 * 10 ** 6;
        vm.prank(address(hyperCrocVault));
        uint256 expectedLpTokens = adapter.deposit(depositAmount);

        assertEq(usdeBalanceBefore - USDE.balanceOf(address(hyperCrocVault)), depositAmount);
        assertEq(S_USDE.balanceOf(address(hyperCrocVault)), expectedLpTokens);
        assertEq(USDE.balanceOf(address(adapter)), 0);
        assertEq(S_USDE.balanceOf(address(adapter)), 0);

        _assertAdapterAssets(0);
    }

    function testDepositAllExcept() public {
        uint256 except = 1000 * 10 ** 6;
        vm.prank(address(hyperCrocVault));
        uint256 expectedLpTokens = adapter.depositAllExcept(except);

        assertEq(USDE.balanceOf(address(hyperCrocVault)), except);
        assertEq(S_USDE.balanceOf(address(hyperCrocVault)), expectedLpTokens);
        assertEq(USDE.balanceOf(address(adapter)), 0);
        assertEq(S_USDE.balanceOf(address(adapter)), 0);

        _assertAdapterAssets(0);
    }

    function testCooldown() public {
        uint256 usdeBalanceBefore = USDE.balanceOf(address(hyperCrocVault));
        uint256 depositAmount = 1000 * 10 ** 6;
        vm.prank(address(hyperCrocVault));
        uint256 expectedLpTokens = adapter.deposit(depositAmount);

        vm.prank(address(hyperCrocVault));
        adapter.cooldownShares(expectedLpTokens);

        assertEq(USDE.balanceOf(address(hyperCrocVault)), usdeBalanceBefore - depositAmount);
        assertEq(S_USDE.balanceOf(address(hyperCrocVault)), 0);
        assertEq(USDE.balanceOf(address(adapter)), 0);
        assertEq(S_USDE.balanceOf(address(adapter)), 0);

        _assertAdapterAssets(S_USDE.convertToAssets(expectedLpTokens));
    }

    function testCooldownAllExcept() public {
        uint256 usdeBalanceBefore = USDE.balanceOf(address(hyperCrocVault));
        uint256 depositAmount = 1000 * 10 ** 6;
        vm.prank(address(hyperCrocVault));
        uint256 expectedLpTokens = adapter.deposit(depositAmount);

        uint256 except = 100 * 10 ** 6;
        vm.prank(address(hyperCrocVault));
        adapter.cooldownSharesAllExcept(except);

        assertEq(USDE.balanceOf(address(hyperCrocVault)), usdeBalanceBefore - depositAmount);
        assertEq(S_USDE.balanceOf(address(hyperCrocVault)), except);
        assertEq(USDE.balanceOf(address(adapter)), 0);
        assertEq(S_USDE.balanceOf(address(adapter)), 0);

        _assertAdapterAssets(S_USDE.convertToAssets(expectedLpTokens - except));
    }

    function testCooldownOnlyVault() public {
        vm.prank(address(NO_ACCESS));
        vm.expectRevert(abi.encodeWithSelector(EthenaAdapter.NoAccess.selector));
        adapter.cooldownShares(1000);
    }

    function testUnstake() public {
        uint256 usdeBalanceBefore = USDE.balanceOf(address(hyperCrocVault));
        uint256 depositAmount = 1000 * 10 ** 6;
        vm.prank(address(hyperCrocVault));
        uint256 expectedLpTokens = adapter.deposit(depositAmount);

        vm.prank(address(hyperCrocVault));
        adapter.cooldownShares(expectedLpTokens);

        skip(S_USDE.cooldownDuration());

        vm.prank(address(hyperCrocVault));
        adapter.unstake();

        assertApproxEqAbs(USDE.balanceOf(address(hyperCrocVault)), usdeBalanceBefore, 1);
        assertEq(S_USDE.balanceOf(address(hyperCrocVault)), 0);
        assertEq(USDE.balanceOf(address(adapter)), 0);
        assertEq(S_USDE.balanceOf(address(adapter)), 0);

        _assertAdapterAssets(0);
    }

    function testUnstakeOnlyVault() public {
        vm.prank(address(NO_ACCESS));
        vm.expectRevert(abi.encodeWithSelector(EthenaAdapter.NoAccess.selector));
        adapter.unstake();
    }

    function testRedeem() public {
        uint256 usdeBalanceBefore = USDE.balanceOf(address(hyperCrocVault));
        uint256 depositAmount = 1000 * 10 ** 6;
        vm.prank(address(hyperCrocVault));
        uint256 expectedLpTokens = adapter.deposit(depositAmount);

        vm.prank(IStakedUSDeAdmin(address(S_USDE)).owner());
        IStakedUSDeAdmin(address(S_USDE)).setCooldownDuration(0);

        vm.prank(address(hyperCrocVault));
        adapter.redeem(expectedLpTokens);

        assertApproxEqAbs(USDE.balanceOf(address(hyperCrocVault)), usdeBalanceBefore, 1);
        assertEq(S_USDE.balanceOf(address(hyperCrocVault)), 0);
        assertEq(USDE.balanceOf(address(adapter)), 0);
        assertEq(S_USDE.balanceOf(address(adapter)), 0);

        _assertAdapterAssets(0);
    }

    function testRedeemAllExcept() public {
        uint256 usdeBalanceBefore = USDE.balanceOf(address(hyperCrocVault));
        uint256 depositAmount = 1000 * 10 ** 6;
        vm.prank(address(hyperCrocVault));
        adapter.deposit(depositAmount);

        vm.prank(IStakedUSDeAdmin(address(S_USDE)).owner());
        IStakedUSDeAdmin(address(S_USDE)).setCooldownDuration(0);

        uint256 except = 100 * 10 ** 6;
        vm.prank(address(hyperCrocVault));
        adapter.redeemAllExcept(except);

        assertApproxEqAbs(USDE.balanceOf(address(hyperCrocVault)), usdeBalanceBefore - S_USDE.convertToAssets(except), 1);
        assertEq(S_USDE.balanceOf(address(hyperCrocVault)), except);
        assertEq(USDE.balanceOf(address(adapter)), 0);
        assertEq(S_USDE.balanceOf(address(adapter)), 0);

        _assertAdapterAssets(0);
    }

    function testGetManagedAssetsSenderNotVault() public {
        uint256 depositAmount = 1000 * 10 ** 6;
        vm.prank(address(hyperCrocVault));
        uint256 expectedLpTokens = adapter.deposit(depositAmount);

        vm.prank(address(hyperCrocVault));
        adapter.cooldownShares(expectedLpTokens);

        assertNotEq(S_USDE.convertToAssets(expectedLpTokens), 0);
        _assertAdapterAssets(S_USDE.convertToAssets(expectedLpTokens));

        vm.prank(NO_ACCESS);
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);
    }

    function _assertAdapterAssets(uint256 expectedUsde) private {
        uint256 expectedLength = expectedUsde == 0 ? 0 : 1;

        vm.prank(address(hyperCrocVault));
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, expectedLength);
        assertEq(amounts.length, expectedLength);
        if (expectedLength != 0) {
            assertEq(assets[0], address(USDE));
            assertEq(amounts[0], expectedUsde);
        }

        (assets, amounts) = adapter.getManagedAssets(address(hyperCrocVault));
        assertEq(assets.length, expectedLength);
        assertEq(amounts.length, expectedLength);
        if (expectedLength != 0) {
            assertEq(assets[0], address(USDE));
            assertEq(amounts[0], expectedUsde);
        }

        _assertNoDebtAssets();
    }

    function _assertNoDebtAssets() private {
        vm.prank(address(hyperCrocVault));
        (address[] memory assets, uint256[] memory amounts) = adapter.getDebtAssets();
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);
    }
}
