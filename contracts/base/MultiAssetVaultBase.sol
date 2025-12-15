// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

import {Asserts} from "../libraries/Asserts.sol";
import {FeeCollector} from "./FeeCollector.sol";
import {WithdrawalQueue} from "../WithdrawalQueue.sol";
import {AdapterActionExecutor} from "./AdapterActionExecutor.sol";
import {IEulerPriceOracle} from "../interfaces/IEulerPriceOracle.sol";

abstract contract MultiAssetVaultBase is ERC4626Upgradeable, FeeCollector, AdapterActionExecutor {
    using Asserts for address;
    using Asserts for uint256;
    using Math for uint256;

    /// @custom:storage-location erc7201:hyperCroc.storage.MultiAssetVaultBase
    struct MultiAssetVaultBaseStorage {
        uint256 minDeposit;
        uint8 maxTrackedAssets;
        IERC20[] trackedAssets;
        // if 0, then token is not tracked, otherwise 'trackedAssetsArrayIndex = trackedAssetPosition - 1'
        mapping(address asset => uint256) trackedAssetPosition;
    }

    // keccak256(abi.encode(uint256(keccak256("hyperCroc.storage.MultiAssetVaultBase")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MultiAssetVaultBaseStorageLocation =
        0xb4929dcfd4273b77f5c4c898159c6e34254f398e5914813e7e6f7d3d9f3fbf00;

    function _getMultiAssetVaultBaseStorage() private pure returns (MultiAssetVaultBaseStorage storage $) {
        assembly {
            $.slot := MultiAssetVaultBaseStorageLocation
        }
    }

    event NewTrackedAssetAdded(address indexed newTrackedAsset, uint256 indexed position);
    event TrackedAssetRemoved(
        address indexed trackedAssetRemoved, uint256 indexed position, address indexed replacement
    );
    event MinimalDepositSet(uint256 minDeposit);
    event MaxTrackedAssetsSet(uint8 maxTrackedAssets);

    error AlreadyTracked(uint256 index);
    error NotTrackedAsset();
    error NotZeroBalance(uint256 balance);
    error LessThanMinDeposit(uint256 minDeposit);
    error ExceedsTrackedAssetsLimit();

    function __MultiAssetVaultBase_init(
        IERC20 asset,
        string calldata lpName,
        string calldata lpSymbol,
        address feeCollector
    ) internal onlyInitializing {
        __ERC4626_init(asset);
        __ERC20_init(lpName, lpSymbol);
        __FeeCollector_init(feeCollector);
    }

    /// @inheritdoc ERC4626Upgradeable
    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        uint256 _totalAssets = _totalAssetsWithFeeCollection();
        uint256 shares = _convertToShares(assets, _totalAssets, totalSupply(), Math.Rounding.Floor);
        _deposit(msg.sender, receiver, assets, shares);

        return shares;
    }

    /// @inheritdoc ERC4626Upgradeable
    function mint(uint256 shares, address receiver) public override returns (uint256) {
        uint256 _totalAssets = _totalAssetsWithFeeCollection();
        uint256 assets = _convertToAssets(shares, _totalAssets, totalSupply(), Math.Rounding.Ceil);
        _deposit(msg.sender, receiver, assets, shares);

        return assets;
    }

    /// @inheritdoc ERC4626Upgradeable
    function withdraw(uint256 assets, address receiver, address owner) public override onlyQueue returns (uint256) {
        uint256 _totalAssets = _totalAssetsWithFeeCollection();

        uint256 shares = _convertToShares(assets, _totalAssets, totalSupply(), Math.Rounding.Ceil);
        _withdraw(msg.sender, receiver, owner, assets, shares);

        return shares;
    }

    /// @inheritdoc ERC4626Upgradeable
    function redeem(uint256 shares, address receiver, address owner) public override onlyQueue returns (uint256) {
        uint256 _totalAssets = _totalAssetsWithFeeCollection();
        uint256 assets = _convertToAssets(shares, _totalAssets, totalSupply(), Math.Rounding.Floor);
        _withdraw(msg.sender, receiver, owner, assets, shares);

        return assets;
    }

    function requestWithdrawal(uint256 assets) external returns (uint256 requestId) {
        uint256 _totalAssets = _totalAssetsWithFeeCollection();
        uint256 _totalSupply = totalSupply();

        uint256 maxAssets = _convertToAssets(balanceOf(msg.sender), _totalAssets, _totalSupply, Math.Rounding.Floor);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxWithdraw(msg.sender, assets, maxAssets);
        }

        uint256 shares = _convertToShares(assets, _totalAssets, _totalSupply, Math.Rounding.Ceil);
        shares.assertNotZeroAmount();

        address queue = _getWithdrawalQueue();
        _transfer(msg.sender, queue, shares);
        return WithdrawalQueue(queue).requestWithdrawal(shares, msg.sender);
    }

    function requestRedeem(uint256 shares) external returns (uint256 requestId) {
        shares.assertNotZeroAmount();

        uint256 maxShares = maxRedeem(msg.sender);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(msg.sender, shares, maxShares);
        }

        _totalAssetsWithFeeCollection();

        address queue = _getWithdrawalQueue();
        _transfer(msg.sender, queue, shares);
        return WithdrawalQueue(queue).requestWithdrawal(shares, msg.sender);
    }

    function addTrackedAsset(address newTrackedAsset) external onlyOwner {
        newTrackedAsset.assertNotZeroAddress();

        MultiAssetVaultBaseStorage storage $ = _getMultiAssetVaultBaseStorage();

        if ($.trackedAssets.length == $.maxTrackedAssets) revert ExceedsTrackedAssetsLimit();

        if ($.trackedAssetPosition[newTrackedAsset] != 0) {
            revert AlreadyTracked($.trackedAssetPosition[newTrackedAsset]);
        }

        _assertOracleExists(newTrackedAsset, asset());

        $.trackedAssets.push(IERC20(newTrackedAsset));

        uint256 position = $.trackedAssets.length;
        $.trackedAssetPosition[newTrackedAsset] = position;

        emit NewTrackedAssetAdded(newTrackedAsset, position);
    }

    function removeTrackedAsset(address trackedAsset) external onlyOwner {
        MultiAssetVaultBaseStorage storage $ = _getMultiAssetVaultBaseStorage();

        uint256 position = $.trackedAssetPosition[trackedAsset];
        if (position == 0) revert NotTrackedAsset();

        uint256 currentBalance = IERC20(trackedAsset).balanceOf(address(this));
        if (currentBalance != 0) revert NotZeroBalance(currentBalance);

        address replacement;
        uint256 _trackedAssetsCount = $.trackedAssets.length;
        if (position != _trackedAssetsCount) {
            replacement = address($.trackedAssets[_trackedAssetsCount - 1]);
            $.trackedAssets[position - 1] = IERC20(replacement);
            $.trackedAssetPosition[replacement] = position;
        }

        $.trackedAssets.pop();
        delete $.trackedAssetPosition[trackedAsset];

        emit TrackedAssetRemoved(trackedAsset, position, replacement);
    }

    function setMinimalDeposit(uint256 minDeposit) external onlyOwner {
        MultiAssetVaultBaseStorage storage $ = _getMultiAssetVaultBaseStorage();
        minDeposit.assertNotSameValue($.minDeposit);

        $.minDeposit = minDeposit;
        emit MinimalDepositSet(minDeposit);
    }

    function setMaxTrackedAssets(uint8 _maxTrackedAssets) external onlyOwner {
        MultiAssetVaultBaseStorage storage $ = _getMultiAssetVaultBaseStorage();
        if (_maxTrackedAssets < $.trackedAssets.length) revert WrongValue();
        $.maxTrackedAssets = _maxTrackedAssets;
        emit MaxTrackedAssetsSet(_maxTrackedAssets);
    }

    /// @inheritdoc ERC4626Upgradeable
    function totalAssets() public view override(AdapterActionExecutor, ERC4626Upgradeable) returns (uint256) {
        unchecked {
            address asset = asset();
            IEulerPriceOracle eulerOracle = oracle();
            uint256 balance = _tokenBalance(IERC20(asset));

            IERC20[] storage trackedAssets = _getMultiAssetVaultBaseStorage().trackedAssets;
            uint256 length = trackedAssets.length;

            for (uint256 i; i < length; ++i) {
                IERC20 trackedAsset = trackedAssets[i];
                uint256 trackedAssetBalance = _tokenBalance(trackedAsset);
                balance += _callOracle(eulerOracle, trackedAssetBalance, address(trackedAsset), asset);
            }

            balance += _getExternalPositionAdaptersTotalAssets(eulerOracle, asset);

            return balance;
        }
    }

    function trackedAssetPosition(address trackedAsset) external view returns (uint256) {
        return _getMultiAssetVaultBaseStorage().trackedAssetPosition[trackedAsset];
    }

    function trackedAssetsCount() external view returns (uint256) {
        return _getMultiAssetVaultBaseStorage().trackedAssets.length;
    }

    function minimalDeposit() external view returns (uint256) {
        return _getMultiAssetVaultBaseStorage().minDeposit;
    }

    function maxTrackedAssets() external view returns (uint8) {
        return _getMultiAssetVaultBaseStorage().maxTrackedAssets;
    }

    /// @inheritdoc ERC4626Upgradeable
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        uint256 minDeposit = _getMultiAssetVaultBaseStorage().minDeposit;
        if (minDeposit == 0) {
            assets.assertNotZeroAmount();
        } else if (assets < minDeposit) {
            revert LessThanMinDeposit(minDeposit);
        }

        super._deposit(caller, receiver, assets, shares);
    }

    function _totalAssetsWithFeeCollection() private returns (uint256 _totalAssets) {
        _totalAssets = totalAssets();
        _collectFees(_totalAssets);
    }

    /**
     * @inheritdoc ERC4626Upgradeable
     * @dev Avoid calling this in non-view methods.
     *      Both totalAssets and totalSupply estimations are computationally heavy
     *      and are definitely calculated somewhere else.
     */
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view override returns (uint256) {
        (uint256 _totalAssets, uint256 _totalSupply) = _estimateTotalAssetsAndSupply();
        return _convertToShares(assets, _totalAssets, _totalSupply, rounding);
    }

    /**
     * @inheritdoc ERC4626Upgradeable
     * @dev Avoid calling this in non-view methods.
     *      Both totalAssets and totalSupply estimations are computationally heavy
     *      and are definitely calculated somewhere else.
     */
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view override returns (uint256) {
        (uint256 _totalAssets, uint256 _totalSupply) = _estimateTotalAssetsAndSupply();
        return _convertToAssets(shares, _totalAssets, _totalSupply, rounding);
    }

    function _convertToShares(uint256 assets, uint256 _totalAssets, uint256 _totalSupply, Math.Rounding rounding)
        private
        view
        returns (uint256)
    {
        return assets.mulDiv(_totalSupply + 10 ** _decimalsOffset(), _totalAssets + 1, rounding);
    }

    function _convertToAssets(uint256 shares, uint256 _totalAssets, uint256 _totalSupply, Math.Rounding rounding)
        private
        view
        returns (uint256)
    {
        return shares.mulDiv(_totalAssets + 1, _totalSupply + 10 ** _decimalsOffset(), rounding);
    }

    function _estimateTotalAssetsAndSupply() private view returns (uint256 _totalAssets, uint256 _totalSupply) {
        _totalAssets = totalAssets();
        _totalSupply = totalSupply();
        (uint256 feeShares,,) = _calculateFees(_totalAssets, _totalSupply);
        _totalSupply += feeShares;
    }

    function _tokenBalance(IERC20 token) private view returns (uint256) {
        return token.balanceOf(address(this));
    }
}
