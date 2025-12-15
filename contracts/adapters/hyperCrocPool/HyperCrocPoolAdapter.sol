// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {AdapterBase} from "../AdapterBase.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";
import {IExternalPositionAdapter} from "../../interfaces/IExternalPositionAdapter.sol";
import {IHyperCrocVault} from "../../interfaces/IHyperCrocVault.sol";
import {IEulerPriceOracle} from "../../interfaces/IEulerPriceOracle.sol";
import {IHyperCrocPool} from "./interfaces/IHyperCrocPool.sol";
import {Asserts} from "../../libraries/Asserts.sol";
import {FP96} from "./FP96.sol";

/// @title Adapter for interaction with HyperCroc pools (Marginly protocol)
/// @notice Should be deployed for each vault
contract HyperCrocPoolAdapter is AdapterBase, IExternalPositionAdapter {
    using Asserts for address;

    bytes4 public constant getAdapterId = bytes4(keccak256("HyperCrocPoolAdapter"));

    using FP96 for FP96.FixedPoint;
    using SafeERC20 for IERC20;
    using Math for uint256;

    uint256 private constant SECONDS_IN_YEAR_X96 = 2500250661360148260042022567123353600;
    uint24 private constant ONE = 1e6;

    address private immutable i_vault;
    address[] private s_pools;
    mapping(address => uint256) private s_poolPosition;

    error HyperCrocPoolAdapter__NotAuthorized();
    error HyperCrocPoolAdapter__OracleNotExists(address base, address quote);
    error HyperCrocPoolAdapter__WrongHyperCrocPoolMode();
    error HyperCrocPoolAdapter__NotSupported();
    error HyperCrocPoolAdapter__NoPool();

    event PoolAdded(address indexed pool);
    event PoolRemoved(address indexed pool);
    event HyperCrocPoolDeposit(
        address indexed vault, address indexed pool, address indexed token, uint256 amount, int256 positionAmount
    );
    event HyperCrocPoolLong(address indexed vault, address indexed pool, uint256 amount);
    event HyperCrocPoolShort(address indexed vault, address indexed pool, uint256 amount);
    event HyperCrocPoolClosePosition(address indexed vault, address indexed pool);
    event HyperCrocPoolSellCollateral(address indexed vault, address indexed pool);
    event HyperCrocPoolWithdraw(address indexed vault, address indexed pool, address indexed asset, uint256 amount);

    constructor(address vault) {
        vault.assertNotZeroAddress();
        i_vault = vault;
    }

    modifier onlyVault() {
        _onlyVault();
        _;
    }

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return super.supportsInterface(interfaceId) || interfaceId == type(IExternalPositionAdapter).interfaceId;
    }

    /// @notice Deposits an amount into a Marginly pool
    /// @param asset The asset to deposit
    /// @param amount The amount to deposit
    /// @param positionAmount Position amount
    /// @param amountInQuote If 'positionAmount' in in quote token
    /// @param pool The pool to deposit into
    /// @param limitPriceX96 The limit price for the position
    /// @param swapCallData The swap call data
    function deposit(
        address asset,
        uint256 amount,
        int256 positionAmount,
        bool amountInQuote,
        address pool,
        uint256 limitPriceX96,
        uint256 swapCallData
    ) external onlyVault {
        _deposit(asset, amount, positionAmount, amountInQuote, pool, limitPriceX96, swapCallData);
    }

    /// @notice Deposits all amount except given amount into a Marginly pool
    function depositAllExcept(
        address asset,
        uint256 except,
        int256 positionAmount,
        bool amountInQuote,
        address pool,
        uint256 limitPriceX96,
        uint256 swapCallData
    ) external onlyVault {
        uint256 amount = IERC20(asset).balanceOf(msg.sender) - except;
        _deposit(asset, amount, positionAmount, amountInQuote, pool, limitPriceX96, swapCallData);
    }

    ///@notice Opens a long position
    ///@param amount The amount to open a long position
    /// @param amountInQuote If 'amount' in in quote token
    ///@param pool The pool to open a long position in
    ///@param limitPriceX96 The limit price for the position
    ///@param swapCallData The swap call data
    function long(uint256 amount, bool amountInQuote, address pool, uint256 limitPriceX96, uint256 swapCallData)
        external
        onlyVault
    {
        IHyperCrocPool(pool).execute(
            IHyperCrocPool.CallType.Long, amount, int256(0), limitPriceX96, amountInQuote, address(0), swapCallData
        );

        // long - quoteToken in debt, check oracle for quoteToken
        _assertOracleExists(IHyperCrocPool(pool).quoteToken(), IHyperCrocVault(msg.sender).asset());

        emit HyperCrocPoolLong(msg.sender, pool, amount);
    }

    ///@notice Opens a short position
    ///@param amount The amount to open a short position
    /// @param amountInQuote If 'amount' in in quote token
    ///@param pool The pool to open a short position in
    ///@param limitPriceX96 The limit price for the position
    ///@param swapCallData The swap call data
    function short(uint256 amount, bool amountInQuote, address pool, uint256 limitPriceX96, uint256 swapCallData)
        external
        onlyVault
    {
        IHyperCrocPool(pool).execute(
            IHyperCrocPool.CallType.Short, amount, int256(0), limitPriceX96, amountInQuote, address(0), swapCallData
        );

        // short - baseToken in debt, check oracle for baseToken
        _assertOracleExists(IHyperCrocPool(pool).baseToken(), IHyperCrocVault(msg.sender).asset());

        emit HyperCrocPoolShort(msg.sender, pool, amount);
    }

    ///@notice Closes a position
    ///@param pool The pool to close a position in
    ///@param withdrawal If withdrawal of remaining collateral is required
    ///@param limitPriceX96 The limit price for the position
    ///@param swapCallData The swap call data
    function closePosition(address pool, bool withdrawal, uint256 limitPriceX96, uint256 swapCallData)
        external
        onlyVault
    {
        address asset;
        if (withdrawal) {
            IHyperCrocPool.Position memory position = IHyperCrocPool(pool).positions(address(this));
            asset = position._type == IHyperCrocPool.PositionType.Long
                ? IHyperCrocPool(pool).baseToken()
                : IHyperCrocPool(pool).quoteToken();
        }

        IHyperCrocPool(pool).execute(
            IHyperCrocPool.CallType.ClosePosition, 0, int256(0), limitPriceX96, withdrawal, address(0), swapCallData
        );
        emit HyperCrocPoolClosePosition(msg.sender, pool);

        if (withdrawal) {
            uint256 amount = IERC20(asset).balanceOf(address(this));
            IERC20(asset).safeTransfer(msg.sender, amount);
            _removePool(pool);

            emit HyperCrocPoolWithdraw(msg.sender, pool, asset, amount);
        }
    }

    ///@notice Sell position collateral
    ///@param pool The pool to sell collateral in
    ///@param withdrawal If withdrawal of remaining collateral is required
    ///@param limitPriceX96 The limit price for collateral sale
    ///@param swapCallData The swap call data
    function sellCollateral(address pool, bool withdrawal, uint256 limitPriceX96, uint256 swapCallData)
        external
        onlyVault
    {
        address asset;
        if (withdrawal) {
            IHyperCrocPool.Position memory position = IHyperCrocPool(pool).positions(address(this));
            asset = position._type == IHyperCrocPool.PositionType.Long
                ? IHyperCrocPool(pool).quoteToken()
                : IHyperCrocPool(pool).baseToken();
        }

        IHyperCrocPool(pool).execute(
            IHyperCrocPool.CallType.SellCollateral, 0, int256(0), limitPriceX96, withdrawal, address(0), swapCallData
        );
        emit HyperCrocPoolSellCollateral(msg.sender, pool);

        if (withdrawal) {
            uint256 amount = IERC20(asset).balanceOf(address(this));
            IERC20(asset).safeTransfer(msg.sender, amount);
            _removePool(pool);

            emit HyperCrocPoolWithdraw(msg.sender, pool, asset, amount);
        }
    }

    /// @notice Withdraws an amount from pool
    /// @param asset The asset to withdraw
    /// @param amount The amount to withdraw
    /// @param pool The pool to withdraw from
    function withdraw(address asset, uint256 amount, address pool) external onlyVault returns (uint256 amountOut) {
        IHyperCrocPool.CallType callType = IHyperCrocPool(pool).quoteToken() == asset
            ? IHyperCrocPool.CallType.WithdrawQuote
            : IHyperCrocPool.CallType.WithdrawBase;

        IHyperCrocPool(pool).execute(callType, amount, int256(0), 0, false, address(0), 0);
        amountOut = IERC20(asset).balanceOf(address(this));
        IERC20(asset).safeTransfer(msg.sender, amountOut);

        IHyperCrocPool.Position memory position = IHyperCrocPool(pool).positions(address(this));
        if (position._type == IHyperCrocPool.PositionType.Uninitialized) {
            _removePool(pool);
        }

        emit HyperCrocPoolWithdraw(msg.sender, pool, asset, amountOut);
    }

    /// @notice Withdraws an amount when pool in emergency mode
    /// @param pool The pool to withdraw from
    function emergencyWithdraw(address pool) external onlyVault {
        IHyperCrocPool.Position memory position = IHyperCrocPool(pool).positions(address(this));
        IHyperCrocPool.Mode mode = IHyperCrocPool(pool).mode();

        IERC20 asset;
        if (mode == IHyperCrocPool.Mode.ShortEmergency) {
            if (position._type == IHyperCrocPool.PositionType.Short) {
                _removePool(pool);
                return;
            }
            asset = IERC20(IHyperCrocPool(pool).baseToken());
        } else if (mode == IHyperCrocPool.Mode.LongEmergency) {
            if (position._type == IHyperCrocPool.PositionType.Long) {
                _removePool(pool);
                return;
            }
            asset = IERC20(IHyperCrocPool(pool).quoteToken());
        } else {
            revert HyperCrocPoolAdapter__WrongHyperCrocPoolMode();
        }

        IHyperCrocPool(pool).execute(IHyperCrocPool.CallType.EmergencyWithdraw, 0, int256(0), 0, false, address(0), 0);

        uint256 amount = asset.balanceOf(address(this));
        asset.safeTransfer(msg.sender, amount);

        position = IHyperCrocPool(pool).positions(address(this));
        if (position._type == IHyperCrocPool.PositionType.Uninitialized) {
            _removePool(pool);
        }

        emit HyperCrocPoolWithdraw(msg.sender, pool, address(asset), amount);
    }

    /// @notice Returns managed assets by the vault in adapter Protocol
    function getManagedAssets() external view returns (address[] memory assets, uint256[] memory amounts) {
        uint256 length = s_pools.length;
        assets = new address[](length);
        amounts = new uint256[](length);

        for (uint256 i; i < length;) {
            IHyperCrocPool pool = IHyperCrocPool(s_pools[i]);
            IHyperCrocPool.Position memory position = pool.positions(address(this));

            if (position._type == IHyperCrocPool.PositionType.Short || position.discountedBaseAmount == 0) {
                //isQuote
                assets[i] = pool.quoteToken();
                uint256 discountedBaseDebt =
                    position._type == IHyperCrocPool.PositionType.Short ? position.discountedBaseAmount : 0;
                amounts[i] = _estimateCollateral(pool, true, position.discountedQuoteAmount, discountedBaseDebt);
            } else {
                assets[i] = pool.baseToken();
                uint256 discountedQuoteDebt =
                    position._type == IHyperCrocPool.PositionType.Long ? position.discountedQuoteAmount : 0;
                amounts[i] = _estimateCollateral(pool, false, position.discountedBaseAmount, discountedQuoteDebt);
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Returns debt assets managed by the vault in adapter Protocol
    function getDebtAssets() external view returns (address[] memory assets, uint256[] memory amounts) {
        uint256 length = s_pools.length;
        assets = new address[](length);
        amounts = new uint256[](length);

        for (uint256 i; i < length;) {
            IHyperCrocPool pool = IHyperCrocPool(s_pools[i]);
            IHyperCrocPool.Position memory position = pool.positions(address(this));

            if (position._type == IHyperCrocPool.PositionType.Long) {
                assets[i] = pool.quoteToken();
                amounts[i] = _estimateDebtCoeff(pool, true).mul(position.discountedQuoteAmount);
            } else if (position._type == IHyperCrocPool.PositionType.Short) {
                assets[i] = pool.baseToken();
                amounts[i] = _estimateDebtCoeff(pool, false).mul(position.discountedBaseAmount);
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Returns the vault address
    function getVault() external view returns (address) {
        return i_vault;
    }

    /// @notice Returns all connected pools
    function getPools() external view returns (address[] memory pools) {
        return s_pools;
    }

    /// @notice Returns position of pool
    function getPoolPosition(address pool) external view returns (uint256) {
        return s_poolPosition[pool];
    }

    function _onlyVault() private view {
        if (msg.sender != i_vault) {
            revert HyperCrocPoolAdapter__NotAuthorized();
        }
    }

    function _addPool(address pool) internal {
        if (s_poolPosition[pool] != 0) {
            return;
        }

        s_pools.push(pool);
        s_poolPosition[pool] = s_pools.length;

        emit PoolAdded(pool);
    }

    function _removePool(address pool) internal {
        uint256 poolPosition = s_poolPosition[pool];
        if (poolPosition == 0) {
            revert HyperCrocPoolAdapter__NoPool();
        }

        uint256 poolIndex = poolPosition - 1;
        uint256 poolsLastIndex = s_pools.length - 1;

        if (poolIndex != poolsLastIndex) {
            address replacement = s_pools[poolsLastIndex];
            s_pools[poolIndex] = replacement;
            s_poolPosition[replacement] = poolIndex + 1;
        }

        s_pools.pop();
        delete s_poolPosition[pool];

        emit PoolRemoved(pool);
    }

    /// @dev A little modified MarginlyPool.accruedInterest() function
    /// @dev https://github.com/eq-lab/marginly/blob/main/packages/contracts/contracts/MarginlyPool.sol#L1019
    /// @dev Instead of calling MarginlyPool.reinit() we make calculations on our side
    /// @dev Reinit simulation without margin calls
    function _estimateCollateral(IHyperCrocPool pool, bool isQuote, uint256 discountedCollateral, uint256 discountedDebt)
        private
        view
        returns (uint256)
    {
        uint256 secondsPassed = block.timestamp - pool.lastReinitTimestampSeconds();

        if (isQuote) {
            FP96.FixedPoint memory quoteCollateralCoeff = pool.quoteCollateralCoeff();
            FP96.FixedPoint memory quoteDelevCoeff = pool.quoteDelevCoeff();

            uint256 currentQuoteCollateral =
                quoteCollateralCoeff.mul(discountedCollateral) - quoteDelevCoeff.mul(discountedDebt);
            if (secondsPassed == 0) {
                return currentQuoteCollateral;
            }

            FP96.FixedPoint memory quoteAccruedInterestFactor = _estimateQuoteAccruedInterestFactor(pool, secondsPassed);
            uint256 realQuoteDebtDelta =
                quoteAccruedInterestFactor.sub(FP96.one()).mul(pool.quoteDebtCoeff().mul(pool.discountedQuoteDebt()));
            uint256 realQuoteCollateral = quoteCollateralCoeff.mul(pool.discountedQuoteCollateral())
                - quoteDelevCoeff.mul(pool.discountedBaseDebt());

            FP96.FixedPoint memory factor = FP96.one().add(FP96.fromRatio(realQuoteDebtDelta, realQuoteCollateral));

            return factor.mul(currentQuoteCollateral);
        } else {
            FP96.FixedPoint memory baseCollateralCoeff = pool.baseCollateralCoeff();
            FP96.FixedPoint memory baseDelevCoeff = pool.baseDelevCoeff();
            uint256 currentBaseCollateral =
                baseCollateralCoeff.mul(discountedCollateral) - baseDelevCoeff.mul(discountedDebt);

            if (secondsPassed == 0) {
                return currentBaseCollateral;
            }

            FP96.FixedPoint memory baseAccruedInterestFactor = _estimateBaseAccruedInterestFactor(pool, secondsPassed);
            uint256 realBaseDebtDelta =
                baseAccruedInterestFactor.sub(FP96.one()).mul(pool.baseDebtCoeff().mul(pool.discountedBaseDebt()));
            uint256 realBaseCollateral = baseCollateralCoeff.mul(pool.discountedBaseCollateral())
                - baseDelevCoeff.mul(pool.discountedQuoteDebt());

            FP96.FixedPoint memory factor = FP96.one().add(FP96.fromRatio(realBaseDebtDelta, realBaseCollateral));

            return factor.mul(currentBaseCollateral);
        }
    }

    function _estimateDebtCoeff(IHyperCrocPool pool, bool isLong) private view returns (FP96.FixedPoint memory) {
        uint256 secondsPassed = block.timestamp - pool.lastReinitTimestampSeconds();
        if (secondsPassed == 0) {
            return isLong ? pool.quoteDebtCoeff() : pool.baseDebtCoeff();
        }

        if (isLong) {
            return pool.quoteDebtCoeff().mul(_estimateQuoteAccruedInterestFactor(pool, secondsPassed));
        } else {
            return pool.baseDebtCoeff().mul(_estimateBaseAccruedInterestFactor(pool, secondsPassed));
        }
    }

    function _assertOracleExists(address base, address quote) internal view {
        IEulerPriceOracle eulerOracle = IEulerPriceOracle(IHyperCrocVault(msg.sender).oracle());
        if (
            _callOracle(eulerOracle, _getOneToken(base), base, quote) == 0
                && _callOracle(eulerOracle, _getOneToken(quote), quote, base) == 0
        ) revert HyperCrocPoolAdapter__OracleNotExists(base, quote);
    }

    function _getOneToken(address token) private view returns (uint256) {
        return 10 ** IERC20Metadata(token).decimals();
    }

    function _callOracle(IEulerPriceOracle eulerOracle, uint256 baseAmount, address baseToken, address quoteToken)
        private
        view
        returns (uint256)
    {
        return eulerOracle.getQuote(baseAmount, baseToken, quoteToken);
    }

    function _estimateQuoteAccruedInterestFactor(IHyperCrocPool pool, uint256 secondsPassed)
        private
        view
        returns (FP96.FixedPoint memory)
    {
        FP96.FixedPoint memory systemLeverage = FP96.FixedPoint({inner: pool.longLeverageX96()});
        return _estimateAccruedInterestFactor(pool, secondsPassed, systemLeverage);
    }

    function _estimateBaseAccruedInterestFactor(IHyperCrocPool pool, uint256 secondsPassed)
        private
        view
        returns (FP96.FixedPoint memory)
    {
        FP96.FixedPoint memory systemLeverage = FP96.FixedPoint({inner: pool.shortLeverageX96()});
        return _estimateAccruedInterestFactor(pool, secondsPassed, systemLeverage);
    }

    function _estimateAccruedInterestFactor(
        IHyperCrocPool pool,
        uint256 secondsPassed,
        FP96.FixedPoint memory systemLeverage
    ) private view returns (FP96.FixedPoint memory) {
        IHyperCrocPool.MarginlyParams memory params = pool.params();
        FP96.FixedPoint memory secondsInYear = FP96.FixedPoint({inner: SECONDS_IN_YEAR_X96});

        FP96.FixedPoint memory onePlusIR =
            FP96.fromRatio(params.interestRate, ONE).mul(systemLeverage).div(secondsInYear).add(FP96.one());
        FP96.FixedPoint memory accruedRateDt = FP96.powTaylor(onePlusIR, secondsPassed);

        FP96.FixedPoint memory onePlusFee = FP96.fromRatio(params.fee, ONE).div(secondsInYear).add(FP96.one());
        FP96.FixedPoint memory feeDt = FP96.powTaylor(onePlusFee, secondsPassed);

        return accruedRateDt.mul(feeDt);
    }

    function _deposit(
        address asset,
        uint256 amount,
        int256 positionAmount,
        bool amountInQuote,
        address pool,
        uint256 limitPriceX96,
        uint256 swapCallData
    ) private {
        address quoteToken = IHyperCrocPool(pool).quoteToken();
        IHyperCrocPool.CallType callType =
            asset == quoteToken ? IHyperCrocPool.CallType.DepositQuote : IHyperCrocPool.CallType.DepositBase;

        //Both token deposits not supported
        IHyperCrocPool.Position memory position = IHyperCrocPool(pool).positions(address(this));
        if (position._type == IHyperCrocPool.PositionType.Lend) {
            if (position.discountedBaseAmount != 0) {
                if (callType == IHyperCrocPool.CallType.DepositQuote) revert HyperCrocPoolAdapter__NotSupported();
            } else {
                if (callType == IHyperCrocPool.CallType.DepositBase) revert HyperCrocPoolAdapter__NotSupported();
            }
        }

        if (callType == IHyperCrocPool.CallType.DepositQuote && positionAmount < 0) {
            // depositQuote and long
            _assertOracleExists(quoteToken, IHyperCrocVault(msg.sender).asset());
        } else if (callType == IHyperCrocPool.CallType.DepositBase && positionAmount < 0) {
            // depositBase and short
            _assertOracleExists(IHyperCrocPool(pool).baseToken(), IHyperCrocVault(msg.sender).asset());
        }

        IAdapterCallback(msg.sender).adapterCallback(address(this), asset, amount);

        IERC20(asset).forceApprove(address(pool), amount);
        IHyperCrocPool(pool).execute(
            callType, amount, positionAmount, limitPriceX96, amountInQuote, address(0), swapCallData
        );

        _addPool(pool);

        emit HyperCrocPoolDeposit(msg.sender, pool, asset, amount, positionAmount);
    }
}
