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
import {ResolvAdapter} from "../../contracts/adapters/resolv/ResolvAdapter.sol";
import {AdapterBase} from "../../contracts/adapters/AdapterBase.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";

contract ResolvAdapterTest is Test {
    using Math for uint256;

    uint256 public constant FORK_BLOCK = 22515980;

    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC4626 private constant WSTUSR = IERC4626(0x1202F5C7b4B9E47a1A484E8B270be34dbbC75055);
    IERC20 private constant USR = IERC20(0x66a1E37c9b0eAddca17d3662D6c05F4DECf3e110);

    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    ResolvAdapter private adapter;
    HyperCrocVault private hyperCrocVault;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl), FORK_BLOCK);

        EulerRouterMock oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE(), address(USR), address(USDC));
        oracle.setPrice(oracle.ONE().mulDiv(95, 100), address(WSTUSR), address(USDC));

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

        adapter = new ResolvAdapter(address(WSTUSR));
        hyperCrocVault.addAdapter(address(adapter));
        assertEq(hyperCrocVault.externalPositionAdapterPosition(address(adapter)), 0);

        deal(address(USR), address(hyperCrocVault), 10 ** 24);

        hyperCrocVault.addTrackedAsset(address(USR));
        hyperCrocVault.addTrackedAsset(address(WSTUSR));
    }

    function testSetup() public view {
        assertEq(adapter.wstUSR(), address(WSTUSR));
        assertEq(adapter.USR(), address(USR));
    }

    function testDeposit() public {
        uint256 usrBalanceBefore = USR.balanceOf(address(hyperCrocVault));
        uint256 depositAmount = 1000 * 10 ** 18;
        vm.prank(address(hyperCrocVault));
        uint256 expectedLpTokens = adapter.deposit(depositAmount);

        assertEq(usrBalanceBefore - USR.balanceOf(address(hyperCrocVault)), depositAmount);
        assertEq(WSTUSR.balanceOf(address(hyperCrocVault)), expectedLpTokens);
        assertEq(USR.balanceOf(address(adapter)), 0);
        assertEq(WSTUSR.balanceOf(address(adapter)), 0);
    }

    function testRedeem() public {
        uint256 usdeBalanceBefore = USR.balanceOf(address(hyperCrocVault));
        uint256 depositAmount = 1000 * 10 ** 18;
        vm.prank(address(hyperCrocVault));
        uint256 expectedLpTokens = adapter.deposit(depositAmount);

        vm.prank(address(hyperCrocVault));
        adapter.redeem(expectedLpTokens);

        assertApproxEqAbs(USR.balanceOf(address(hyperCrocVault)), usdeBalanceBefore, 1);
        assertEq(WSTUSR.balanceOf(address(hyperCrocVault)), 0);
        assertEq(USR.balanceOf(address(adapter)), 0);
        assertEq(WSTUSR.balanceOf(address(adapter)), 0);
    }
}
