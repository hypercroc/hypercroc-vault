// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {HyperCrocVaultFactory} from "../../contracts/HyperCrocVaultFactory.sol";
import {HyperCrocVault} from "../../contracts/HyperCrocVault.sol";
import {WithdrawalQueue} from "../../contracts/WithdrawalQueue.sol";
import {MakerDaoUsdsAdapter} from "../../contracts/adapters/makerDao/MakerDaoUsdsAdapter.sol";
import {AdapterBase} from "../../contracts/adapters/AdapterBase.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";

contract MakerDaoUsdsAdapterTest is Test {
    using Math for uint256;

    uint256 public constant FORK_BLOCK = 22515980;

    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC4626 private constant S_USDS = IERC4626(0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD);
    IERC20 private constant USDS = IERC20(0xdC035D45d973E3EC169d2276DDab16f1e407384F);

    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    MakerDaoUsdsAdapter private adapter;
    HyperCrocVault private hyperCrocVault;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl), FORK_BLOCK);

        EulerRouterMock oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE(), address(USDS), address(USDC));
        oracle.setPrice(oracle.ONE().mulDiv(95, 100), address(S_USDS), address(USDC));

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

        adapter = new MakerDaoUsdsAdapter(address(S_USDS));
        hyperCrocVault.addAdapter(address(adapter));
        assertEq(hyperCrocVault.externalPositionAdapterPosition(address(adapter)), 0);

        deal(address(USDS), address(hyperCrocVault), 10 ** 24);

        hyperCrocVault.addTrackedAsset(address(USDS));
        hyperCrocVault.addTrackedAsset(address(S_USDS));
    }

    function testSetup() public view {
        assertEq(adapter.sUSDS(), address(S_USDS));
        assertEq(adapter.USDS(), address(USDS));
    }

    function testDeposit() public {
        uint256 balanceBefore = USDS.balanceOf(address(hyperCrocVault));
        uint256 depositAmount = 1000 * 10 ** 18;
        vm.prank(address(hyperCrocVault));
        uint256 expectedLpTokens = adapter.deposit(depositAmount);

        assertEq(balanceBefore - USDS.balanceOf(address(hyperCrocVault)), depositAmount);
        assertEq(S_USDS.balanceOf(address(hyperCrocVault)), expectedLpTokens);
        assertEq(USDS.balanceOf(address(adapter)), 0);
        assertEq(S_USDS.balanceOf(address(adapter)), 0);
    }

    function testRedeem() public {
        uint256 usdeBalanceBefore = USDS.balanceOf(address(hyperCrocVault));
        uint256 depositAmount = 1000 * 10 ** 18;
        vm.prank(address(hyperCrocVault));
        uint256 expectedLpTokens = adapter.deposit(depositAmount);

        vm.prank(address(hyperCrocVault));
        adapter.redeem(expectedLpTokens);

        assertApproxEqAbs(USDS.balanceOf(address(hyperCrocVault)), usdeBalanceBefore, 1);
        assertEq(S_USDS.balanceOf(address(hyperCrocVault)), 0);
        assertEq(USDS.balanceOf(address(adapter)), 0);
        assertEq(S_USDS.balanceOf(address(adapter)), 0);
    }
}
