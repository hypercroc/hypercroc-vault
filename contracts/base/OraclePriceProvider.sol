// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {Asserts} from "../libraries/Asserts.sol";
import {IEulerPriceOracle} from "../interfaces/IEulerPriceOracle.sol";
import {VaultAccessControl} from "./VaultAccessControl.sol";

abstract contract OraclePriceProvider is Initializable, VaultAccessControl {
    using Asserts for address;

    /// @custom:storage-location erc7201:hyperCroc.storage.OraclePriceProvider
    struct OraclePriceProviderStorage {
        IEulerPriceOracle eulerOracle;
    }

    // keccak256(abi.encode(uint256(keccak256("hyperCroc.storage.OraclePriceProvider")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OraclePriceProviderStorageLocation =
        0x915411155a1c14a9e152cb55b4d59555a72a2626bf44e042bd6db07323e1cc00;

    function _getOraclePriceProviderStorage() private pure returns (OraclePriceProviderStorage storage $) {
        assembly {
            $.slot := OraclePriceProviderStorageLocation
        }
    }

    event OracleSet(address indexed oracle);

    error OracleNotExist(address base, address quote);

    function __OraclePriceProvider_init(address eulerOracle) internal onlyInitializing {
        _setOracle(eulerOracle);
    }

    function setOracle(address eulerOracle) external onlyOwner {
        _setOracle(eulerOracle);
    }

    function oracle() public view virtual returns (IEulerPriceOracle) {
        return _getOraclePriceProviderStorage().eulerOracle;
    }

    /**
     * @dev Two-sided price assertion is done to avoid getting zero quote amount for some cheap-vs-expensive token pair
     *      e.g. PEPE/BTC (in terms of decimals): 10^18 PEPE costs $10^(-5), 10^8 BTC costs $100_000 =>
     *      => 1 BTC costs $10^(-3) > $10^(-5) => 10^18 PEPE < 1 BTC => getQuote(10^18, PEPE, BTC) returns 0
     */
    function _assertOracleExists(address base, address quote) internal view {
        IEulerPriceOracle eulerOracle = _getOraclePriceProviderStorage().eulerOracle;
        if (
            _callOracle(eulerOracle, _getOneToken(base), base, quote) == 0
                && _callOracle(eulerOracle, _getOneToken(quote), quote, base) == 0
        ) revert OracleNotExist(base, quote);
    }

    function _callOracle(IEulerPriceOracle eulerOracle, uint256 baseAmount, address baseToken, address quoteToken)
        internal
        view
        returns (uint256)
    {
        if (baseAmount == 0) {
            return 0;
        }
        return eulerOracle.getQuote(baseAmount, baseToken, quoteToken);
    }

    function _setOracle(address eulerOracle) private {
        eulerOracle.assertNotZeroAddress();
        OraclePriceProviderStorage storage $ = _getOraclePriceProviderStorage();
        eulerOracle.assertNotSameValue(address($.eulerOracle));
        $.eulerOracle = IEulerPriceOracle(eulerOracle);

        emit OracleSet(eulerOracle);
    }

    function _getOneToken(address token) private view returns (uint256) {
        return 10 ** IERC20Metadata(token).decimals();
    }
}
