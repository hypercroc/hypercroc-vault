// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";
import {IExternalPositionAdapter} from "../../interfaces/IExternalPositionAdapter.sol";
import {Asserts} from "../../libraries/Asserts.sol";
import {ERC4626AdapterBase} from "../ERC4626AdapterBase.sol";
import {IStakedUSDe} from "./interfaces/IStakedUSDe.sol";

contract EthenaAdapter is ERC4626AdapterBase, IExternalPositionAdapter {
    using SafeERC20 for IStakedUSDe;
    using Asserts for address;

    bytes4 public constant getAdapterId = bytes4(keccak256("EthenaAdapter"));

    event EthenaCooldown(address indexed vault, uint256 shares, uint256 assets, uint256 timestamp);
    event EthenaUnstake(address indexed vault);

    error NoAccess();

    address public immutable hyperCrocVault;

    modifier onlyVault() {
        if (msg.sender != hyperCrocVault) revert NoAccess();
        _;
    }

    constructor(address _hyperCrocVault, address _sUSDe) ERC4626AdapterBase(_sUSDe) {
        _hyperCrocVault.assertNotZeroAddress();
        hyperCrocVault = _hyperCrocVault;
    }

    function cooldownShares(uint256 shares) external onlyVault returns (uint256 assets) {
        IStakedUSDe _stakedUSDe = stakedUSDe();

        assets = _cooldownShares(_stakedUSDe, shares);
    }

    function cooldownSharesAllExcept(uint256 except) external onlyVault returns (uint256 assets) {
        IStakedUSDe _stakedUSDe = stakedUSDe();
        uint256 shares = _stakedUSDe.balanceOf(msg.sender) - except;

        assets = _cooldownShares(_stakedUSDe, shares);
    }

    function unstake() external onlyVault {
        IStakedUSDe _stakedUSDe = stakedUSDe();

        _stakedUSDe.unstake(msg.sender);
        emit EthenaUnstake(msg.sender);
    }

    function USDe() public view returns (address) {
        return _asset;
    }

    function stakedUSDe() public view returns (IStakedUSDe) {
        return IStakedUSDe(_vault);
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
    /// @dev there is no debt assets
    function getDebtAssets() external view returns (address[] memory assets, uint256[] memory amounts) {}

    function _cooldownShares(IStakedUSDe _stakedUsde, uint256 shares) private returns (uint256 assets) {
        IAdapterCallback(msg.sender).adapterCallback(address(this), address(_stakedUsde), shares);
        assets = _stakedUsde.cooldownShares(shares);
        emit EthenaCooldown(msg.sender, shares, assets, block.timestamp);
    }

    function _getManagedAssets(address vault)
        private
        view
        returns (address[] memory assets, uint256[] memory amounts)
    {
        if (vault != hyperCrocVault) return (assets, amounts);

        uint256 cooldownAmount = stakedUSDe().cooldowns(address(this)).underlyingAmount;
        if (cooldownAmount != 0) {
            assets = new address[](1);
            assets[0] = USDe();

            amounts = new uint256[](1);
            amounts[0] = cooldownAmount;
        }
    }
}
