// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AdapterBase} from "../AdapterBase.sol";
import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";
import {IExternalPositionAdapter} from "../../interfaces/IExternalPositionAdapter.sol";
import {Asserts} from "../../libraries/Asserts.sol";
import {IDepositPipe} from "./interfaces/IDepositPipe.sol";
import {IRedemptionPipe} from "./interfaces/IRedemptionPipe.sol";

contract LiminalAdapter is AdapterBase, IExternalPositionAdapter {
    using SafeERC20 for IERC20;
    using Asserts for address;

    bytes4 public constant getAdapterId = bytes4(keccak256("LiminalAdapter"));

    event LiminalWithdrawalRequested(address indexed vault, uint256 xHypeAmount);

    error NoAccess();

    address public immutable i_hyperCrocVault;
    IERC20 private immutable i_depositAsset;
    IERC20 private immutable i_xHYPE;
    address private immutable i_usdc;
    IDepositPipe private immutable i_depositPipe;
    IRedemptionPipe private immutable i_redemptionPipe;

    modifier onlyVault() {
        if (msg.sender != i_hyperCrocVault) revert NoAccess();
        _;
    }

    constructor(address hyperCrocVault, address usdc, address xHYPE, address depositPipe, address redemptionPipe) {
        hyperCrocVault.assertNotZeroAddress();
        usdc.assertNotZeroAddress();
        xHYPE.assertNotZeroAddress();
        depositPipe.assertNotZeroAddress();
        redemptionPipe.assertNotZeroAddress();

        i_hyperCrocVault = hyperCrocVault;
        i_usdc = usdc;
        i_xHYPE = IERC20(xHYPE);
        i_depositPipe = IDepositPipe(depositPipe);
        i_redemptionPipe = IRedemptionPipe(redemptionPipe);
        i_depositAsset = IERC20(IDepositPipe(depositPipe).asset());
    }

    /// @notice Deposit 'i_depositAsset' to receive xHYPE
    /// @param amount Amount of 'i_depositAsset' to deposit
    /// @return xHYPEAmount Amount of xHYPE received
    function deposit(uint256 amount, uint256 minShares) external onlyVault returns (uint256 xHYPEAmount) {
        xHYPEAmount = _deposit(i_depositAsset, amount, minShares);
    }

    /// @notice Stake all 'i_depositAsset' except the given amount
    /// @param except Amount to be left
    /// @return xHYPEAmount Amount of xHYPE received
    function depositAllExcept(uint256 except, uint256 minShares) external onlyVault returns (uint256 xHYPEAmount) {
        IERC20 depositAsset = i_depositAsset;
        uint256 amount = depositAsset.balanceOf(msg.sender) - except;
        xHYPEAmount = _deposit(depositAsset, amount, minShares);
    }

    /// @notice Redeems xHype token to USDC
    /// @param xHYPEAmount Amount of kHYPE to withdraw
    /// @return usdcRedeemed Amount of USDC redeemed
    function redeem(uint256 xHYPEAmount) external onlyVault returns (uint256 usdcRedeemed) {
        return _redeem(i_xHYPE, xHYPEAmount);
    }

    /// @notice Redeems all xHype token except given amount
    /// @param except Amount of xHYPE to be left
    /// @return usdcRedeemed Amount of USDC redeemed
    function redeemAllExcept(uint256 except) external onlyVault returns (uint256 usdcRedeemed) {
        IERC20 xHYPE = i_xHYPE;
        uint256 amount = xHYPE.balanceOf(msg.sender) - except;
        return _redeem(xHYPE, amount);
    }

    /// @notice Requests redemption of xHype token to USDC
    /// @param xHYPEAmount Amount of kHYPE to withdraw
    function requestRedeem(uint256 xHYPEAmount) external onlyVault {
        _requestRedeem(i_xHYPE, xHYPEAmount);
    }

    /// @notice Requests redemption of all xHype token except given amount
    /// @param except Amount of xHYPE to be left
    function requestRedeemAllExcept(uint256 except) external onlyVault {
        IERC20 xHYPE = i_xHYPE;
        uint256 amount = xHYPE.balanceOf(msg.sender) - except;
        _requestRedeem(xHYPE, amount);
    }

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IExternalPositionAdapter).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IExternalPositionAdapter
    function getManagedAssets() external view returns (address[] memory assets, uint256[] memory amounts) {
        return _getManagedAssets(msg.sender);
    }

    function getManagedAssets(address vault)
        external
        view
        returns (address[] memory assets, uint256[] memory amounts)
    {
        return _getManagedAssets(vault);
    }

    /// @inheritdoc IExternalPositionAdapter
    function getDebtAssets() external pure returns (address[] memory assets, uint256[] memory amounts) {}

    function getHyperCrocVault() external view returns (address) {
        return i_hyperCrocVault;
    }

    function getUSDC() external view returns (address) {
        return i_usdc;
    }

    function getDepositAsset() external view returns (address) {
        return address(i_depositAsset);
    }

    function getXHYPE() external view returns (address) {
        return address(i_xHYPE);
    }

    function getLiminalDepositPipe() external view returns (address) {
        return address(i_depositPipe);
    }

    function getLiminalRedemptionPipe() external view returns (address) {
        return address(i_redemptionPipe);
    }

    function _deposit(IERC20 depositAsset, uint256 amount, uint256 minShares) private returns (uint256 xHYPEAmount) {
        IAdapterCallback(msg.sender).adapterCallback(address(this), address(depositAsset), amount);
        IDepositPipe depositPipe = i_depositPipe;
        depositAsset.forceApprove(address(depositPipe), amount);
        xHYPEAmount = depositPipe.deposit(amount, msg.sender, minShares);
        emit Swap(msg.sender, address(depositAsset), amount, address(i_xHYPE), xHYPEAmount);
    }

    function _redeem(IERC20 xHYPE, uint256 xHYPEAmount) private returns (uint256 usdcRedeemed) {
        IAdapterCallback(msg.sender).adapterCallback(address(this), address(xHYPE), xHYPEAmount);
        
        IRedemptionPipe redemptionPipe = i_redemptionPipe;
        xHYPE.forceApprove(address(redemptionPipe), xHYPEAmount);

        usdcRedeemed = redemptionPipe.redeem(xHYPEAmount, msg.sender, address(this));
        emit Swap(msg.sender, address(xHYPE), xHYPEAmount, i_usdc, usdcRedeemed);
    }

    function _requestRedeem(IERC20 xHYPE, uint256 xHYPEAmount) private {
        IAdapterCallback(msg.sender).adapterCallback(address(this), address(xHYPE), xHYPEAmount);
        
        IRedemptionPipe redemptionPipe = i_redemptionPipe;
        xHYPE.forceApprove(address(redemptionPipe), xHYPEAmount);

        redemptionPipe.requestRedeem(xHYPEAmount, msg.sender, address(this), address(this));
        emit LiminalWithdrawalRequested(msg.sender, xHYPEAmount);
    }

    function _getManagedAssets(address vault)
        private
        view
        returns (address[] memory assets, uint256[] memory amounts)
    {
        if (vault != i_hyperCrocVault) return (assets, amounts);

        uint256 amount = i_redemptionPipe.pendingRedeemRequest(address(this));
        if (amount != 0) {
            assets = new address[](1);
            assets[0] = address(i_xHYPE);

            amounts = new uint256[](1);
            amounts[0] = amount;
        }
    }
}
