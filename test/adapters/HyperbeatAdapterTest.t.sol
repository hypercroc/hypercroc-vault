// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {HyperCrocVaultFactory} from "../../contracts/HyperCrocVaultFactory.sol";
import {HyperCrocVault} from "../../contracts/HyperCrocVault.sol";
import {WithdrawalQueue} from "../../contracts/WithdrawalQueue.sol";
import {HyperbeatAdapter} from "../../contracts/adapters/hyperbeat/HyperbeatAdapter.sol";
import {AdapterBase} from "../../contracts/adapters/AdapterBase.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";
import {Asserts} from "../../contracts/libraries/Asserts.sol";
import {IExternalPositionAdapter} from "../../contracts/interfaces/IExternalPositionAdapter.sol";
import {IAdapter} from "../../contracts/interfaces/IAdapter.sol";

contract HyperbeatAdapterTest is Test {
    string private mainnetRpcUrl = vm.envString("HYPER_RPC_URL");

    IERC20 private constant USDT = IERC20(0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb);
    IERC20 private constant HB_USDT = IERC20(0x5e105266db42f78FA814322Bce7f388B4C2e61eb);

    address private constant Depositor = 0x6261F30144B259C74243D5f5D9230941186AC936;
    address private constant HBWithdrawalQueue = 0x240e0b2cb615Ded2FE90fDe265B15988Dc45B1c6;

    HyperbeatAdapter private adapter;
    HyperCrocVault private hyperCrocVault;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl));

        EulerRouterMock oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE(), address(HB_USDT), address(USDT));

        address hyperCrocVaultImplementation = address(new HyperCrocVault());
        address withdrawalQueueImplementation = address(new WithdrawalQueue());
        address hyperCrocVaultFactoryImplementation = address(new HyperCrocVaultFactory());

        bytes memory data = abi.encodeWithSelector(
            HyperCrocVaultFactory.initialize.selector, hyperCrocVaultImplementation, withdrawalQueueImplementation
        );
        ERC1967Proxy hyperCrocVaultFactoryProxy = new ERC1967Proxy(hyperCrocVaultFactoryImplementation, data);
        HyperCrocVaultFactory hyperCrocVaultFactory = HyperCrocVaultFactory(address(hyperCrocVaultFactoryProxy));

        (address deployedVault,) = hyperCrocVaultFactory.deployVault(
            address(USDT),
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

        adapter = new HyperbeatAdapter(address(USDT), address(HB_USDT), Depositor, HBWithdrawalQueue);
        hyperCrocVault.addAdapter(address(adapter));
        assertEq(hyperCrocVault.externalPositionAdapterPosition(address(adapter)), 0);

        hyperCrocVault.addTrackedAsset(address(HB_USDT));
    }

    function test_constructor() public {
        vm.expectRevert(Asserts.ZeroAddress.selector);
        new HyperbeatAdapter(address(0), address(1), address(1), address(1));

        vm.expectRevert(Asserts.ZeroAddress.selector);
        new HyperbeatAdapter(address(USDT), address(0), address(1), address(1));

        vm.expectRevert(Asserts.ZeroAddress.selector);
        new HyperbeatAdapter(address(USDT), address(HB_USDT), address(0), address(1));

        vm.expectRevert(Asserts.ZeroAddress.selector);
        new HyperbeatAdapter(address(USDT), address(HB_USDT), Depositor, address(0));

        HyperbeatAdapter _adapter = new HyperbeatAdapter(address(USDT), address(HB_USDT), Depositor, HBWithdrawalQueue);
        assertEq(address(_adapter.getUSDT()), address(USDT));
        assertEq(address(_adapter.getHbUSDT()), address(HB_USDT));
        assertEq(address(_adapter.getHyperbeatDepositor()), Depositor);
        assertEq(address(_adapter.getHyperbeatWithdrawalQueue()), HBWithdrawalQueue);
    }

    function test_supportsInterface() public view {
        assertTrue(adapter.supportsInterface(type(IAdapter).interfaceId));
    }

    function test_deposit() public {
        uint256 amount = 10_000 * 10 ** 6;

        deal(address(USDT), address(hyperCrocVault), amount);
        vm.prank(address(hyperCrocVault));
        uint256 output = adapter.deposit(amount, bytes32(0));
        assertNotEq(output, 0);

        assertEq(HB_USDT.balanceOf(address(hyperCrocVault)), output);
        assertEq(USDT.balanceOf(address(hyperCrocVault)), 0);
        assertEq(HB_USDT.balanceOf(address(adapter)), 0);
        assertEq(USDT.balanceOf(address(adapter)), 0);
        assertEq(address(adapter).balance, 0);
    }

    function test_depositAllExcept() public {
        uint256 kHYPEBalanceBefore = HB_USDT.balanceOf(address(hyperCrocVault));
        uint256 except = 10_000 * 10 ** 6;
        uint256 initialAmount = 15_000 * 10 ** 6;

        deal(address(USDT), address(hyperCrocVault), initialAmount);
        vm.prank(address(hyperCrocVault));
        uint256 output = adapter.depositAllExcept(except, bytes32(0));
        assertNotEq(output, 0);

        assertEq(HB_USDT.balanceOf(address(hyperCrocVault)), kHYPEBalanceBefore + output);
        assertEq(USDT.balanceOf(address(hyperCrocVault)), except);
        assertEq(HB_USDT.balanceOf(address(adapter)), 0);
        assertEq(USDT.balanceOf(address(adapter)), 0);
    }

    function test_instantWithdraw() public {
        uint256 amount = 5 ether;
        deal(address(HB_USDT), address(hyperCrocVault), amount);

        vm.prank(address(hyperCrocVault));
        uint256 output = adapter.instantWithdraw(amount);

        assertEq(HB_USDT.balanceOf(address(hyperCrocVault)), 0);
        assertEq(USDT.balanceOf(address(hyperCrocVault)), output);
        assertEq(HB_USDT.balanceOf(address(adapter)), 0);
        assertEq(USDT.balanceOf(address(adapter)), 0);
    }

    function test_instantWithdrawAllExcept() public {
        uint256 amount = 5 ether;
        uint256 except = 2 ether;
        deal(address(HB_USDT), address(hyperCrocVault), amount);

        vm.prank(address(hyperCrocVault));
        uint256 output = adapter.instantWithdrawAllExcept(except);

        assertEq(HB_USDT.balanceOf(address(hyperCrocVault)), except);
        assertEq(USDT.balanceOf(address(hyperCrocVault)), output);
        assertEq(HB_USDT.balanceOf(address(adapter)), 0);
        assertEq(USDT.balanceOf(address(adapter)), 0);
    }
}
