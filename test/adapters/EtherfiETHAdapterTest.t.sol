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
import {EtherfiETHAdapter} from "../../contracts/adapters/etherfi/EtherfiETHAdapter.sol";
import {AdapterBase} from "../../contracts/adapters/AdapterBase.sol";
import {IAtomicQueue} from "../../contracts/adapters/etherfi/interfaces/IAtomicQueue.sol";
import {ILiquidityPool} from "../../contracts/adapters/etherfi/interfaces/ILiquidityPool.sol";
import {IweETH} from "../../contracts/adapters/etherfi/interfaces/IweETH.sol";
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

contract EtherfiETHAdapterTest is Test {
    using Math for uint256;

    uint256 public constant FORK_BLOCK = 22515980;

    address private constant ETHERFI_ADMIN = 0xcD425f44758a08BaAB3C4908f3e3dE5776e45d7a;
    ILiquidityPool private constant ETHERFI_LIQUIDITY_POOL = ILiquidityPool(0x308861A430be4cce5502d0A12724771Fc6DaF216);
    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 private constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 private constant WEETH = IERC20(0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee);

    IERC20 private eETH;

    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    EtherfiETHAdapter private adapter;
    HyperCrocVault private hyperCrocVault;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl), FORK_BLOCK);

        eETH = IERC20(ETHERFI_LIQUIDITY_POOL.eETH());

        EulerRouterMock oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE().mulDiv(2000, 10 ** 12), address(WETH), address(USDC));
        oracle.setPrice(oracle.ONE().mulDiv(2500, 10 ** 12), address(WEETH), address(USDC));

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

        adapter = new EtherfiETHAdapter(address(WETH), address(WEETH), address(ETHERFI_LIQUIDITY_POOL));
        hyperCrocVault.addAdapter(address(adapter));
        assertNotEq(hyperCrocVault.externalPositionAdapterPosition(address(adapter)), 0);

        deal(address(WETH), address(hyperCrocVault), 10 ether);

        hyperCrocVault.addTrackedAsset(address(WEETH));
        hyperCrocVault.addTrackedAsset(address(WETH));
    }

    function testDepositEth() public {
        uint256 wethBalanceBefore = WETH.balanceOf(address(hyperCrocVault));

        uint256 depositAmount = 1 ether;
        vm.prank(address(hyperCrocVault));
        uint256 weETHAmount = adapter.deposit(depositAmount);

        assertEq(wethBalanceBefore - WETH.balanceOf(address(hyperCrocVault)), depositAmount);
        assertEq(eETH.balanceOf(address(hyperCrocVault)), 0);
        assertEq(WEETH.balanceOf(address(hyperCrocVault)), weETHAmount);

        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(eETH.balanceOf(address(adapter)), 0);
        assertEq(WEETH.balanceOf(address(adapter)), 0);

        vm.prank(address(hyperCrocVault));
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(WETH));
        assertEq(amounts[0], 0);

        (assets, amounts) = adapter.getManagedAssets(address(hyperCrocVault));
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(WETH));
        assertEq(amounts[0], 0);

        _assertNoDebtAssets();
    }

    function testDepositAllExcept() public {
        uint256 wethBalanceBefore = WETH.balanceOf(address(hyperCrocVault));

        uint256 except = 2 ether;
        uint256 depositAmount = wethBalanceBefore - except;
        vm.prank(address(hyperCrocVault));
        uint256 weETHAmount = adapter.depositAllExcept(except);

        assertEq(wethBalanceBefore - WETH.balanceOf(address(hyperCrocVault)), depositAmount);
        assertEq(eETH.balanceOf(address(hyperCrocVault)), 0);
        assertEq(WEETH.balanceOf(address(hyperCrocVault)), weETHAmount);

        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(eETH.balanceOf(address(adapter)), 0);
        assertEq(WEETH.balanceOf(address(adapter)), 0);

        vm.prank(address(hyperCrocVault));
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(WETH));
        assertEq(amounts[0], 0);

        (assets, amounts) = adapter.getManagedAssets(address(hyperCrocVault));
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(WETH));
        assertEq(amounts[0], 0);

        _assertNoDebtAssets();
    }

    function testRequestWithdrawEth() public {
        uint256 wethBalanceBefore = WETH.balanceOf(address(hyperCrocVault));
        uint256 depositAmount = 1 ether;
        vm.prank(address(hyperCrocVault));
        uint256 weethAmount = adapter.deposit(depositAmount);

        vm.prank(address(hyperCrocVault));
        uint256 requestId = adapter.requestWithdraw(weethAmount);

        IWithdrawRequestNFTAdmin nft = IWithdrawRequestNFTAdmin(ETHERFI_LIQUIDITY_POOL.withdrawRequestNFT());
        assertEq(requestId, nft.nextRequestId() - 1);

        assertEq(wethBalanceBefore - WETH.balanceOf(address(hyperCrocVault)), depositAmount);
        assertEq(eETH.balanceOf(address(hyperCrocVault)), 0);
        assertEq(WEETH.balanceOf(address(hyperCrocVault)), 0);

        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(eETH.balanceOf(address(adapter)), 0);
        assertEq(WEETH.balanceOf(address(adapter)), 0);

        vm.prank(address(hyperCrocVault));
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(WETH));
        assertApproxEqAbs(amounts[0], depositAmount, 2);

        _assertNoDebtAssets();
    }

    function testWithdrawAllExcept() public {
        uint256 wethBalanceBefore = WETH.balanceOf(address(hyperCrocVault));
        uint256 depositAmount = 4 ether;
        vm.prank(address(hyperCrocVault));
        uint256 weethAmount = adapter.deposit(depositAmount);

        uint256 except = 1 ether;
        vm.prank(address(hyperCrocVault));
        uint256 requestId = adapter.requestWithdrawAllExcept(except);

        IWithdrawRequestNFTAdmin nft = IWithdrawRequestNFTAdmin(ETHERFI_LIQUIDITY_POOL.withdrawRequestNFT());
        assertEq(requestId, nft.nextRequestId() - 1);

        assertEq(wethBalanceBefore - WETH.balanceOf(address(hyperCrocVault)), depositAmount);
        assertEq(eETH.balanceOf(address(hyperCrocVault)), 0);
        assertEq(WEETH.balanceOf(address(hyperCrocVault)), except);

        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(eETH.balanceOf(address(adapter)), 0);
        assertEq(WEETH.balanceOf(address(adapter)), 0);

        vm.prank(address(hyperCrocVault));
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(WETH));
        assertApproxEqAbs(amounts[0], IweETH(address(WEETH)).getEETHByWeETH(weethAmount - except), 2);

        _assertNoDebtAssets();
    }

    function testClaimWithdrawEth() public {
        uint256 wethBalanceBefore = WETH.balanceOf(address(hyperCrocVault));
        uint256 depositAmount = 1 ether;
        vm.prank(address(hyperCrocVault));
        uint256 weethAmount = adapter.deposit(depositAmount);

        vm.prank(address(hyperCrocVault));
        adapter.requestWithdraw(weethAmount);
        assert(!adapter.claimPossible(address(hyperCrocVault)));

        IWithdrawRequestNFTAdmin nft = IWithdrawRequestNFTAdmin(ETHERFI_LIQUIDITY_POOL.withdrawRequestNFT());
        uint256 lastRequest = nft.nextRequestId() - 1;
        vm.prank(ETHERFI_ADMIN);
        nft.finalizeRequests(lastRequest);

        assert(adapter.claimPossible(address(hyperCrocVault)));

        vm.prank(address(hyperCrocVault));
        adapter.claimWithdraw();

        assert(!adapter.claimPossible(address(hyperCrocVault)));

        assertApproxEqAbs(WETH.balanceOf(address(hyperCrocVault)), wethBalanceBefore, 2);
        assertEq(eETH.balanceOf(address(hyperCrocVault)), 0);
        assertEq(WETH.balanceOf(address(adapter)), 0);
        assertEq(eETH.balanceOf(address(adapter)), 0);

        vm.prank(address(hyperCrocVault));
        (address[] memory assets, uint256[] memory amounts) = adapter.getManagedAssets();
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(WETH));
        assertEq(amounts[0], 0);

        (assets, amounts) = adapter.getManagedAssets(address(hyperCrocVault));
        assertEq(assets.length, 1);
        assertEq(amounts.length, 1);
        assertEq(assets[0], address(WETH));
        assertEq(amounts[0], 0);

        _assertNoDebtAssets();
    }

    function testClaimWithdrawEthNotFinalized() public {
        uint256 depositAmount = 1 ether;
        vm.prank(address(hyperCrocVault));
        uint256 weethAmount = adapter.deposit(depositAmount);

        vm.prank(address(hyperCrocVault));
        adapter.requestWithdraw(weethAmount);

        vm.prank(address(hyperCrocVault));
        vm.expectRevert("Request is not finalized");
        adapter.claimWithdraw();
    }

    function testClaimNoRequests() public {
        vm.prank(address(hyperCrocVault));
        vm.expectRevert(abi.encodeWithSelector(EtherfiETHAdapter.NoWithdrawRequestInQueue.selector));
        adapter.claimWithdraw();
    }

    function _assertNoDebtAssets() private {
        vm.prank(address(hyperCrocVault));
        (address[] memory assets, uint256[] memory amounts) = adapter.getDebtAssets();
        assertEq(assets.length, 0);
        assertEq(amounts.length, 0);
    }
}
