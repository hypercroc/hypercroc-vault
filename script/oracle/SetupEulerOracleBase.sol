// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {DeployHelper} from "../helper/DeployHelper.sol";
import {EulerRouter} from "euler-price-oracle/EulerRouter.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {PendleUniversalOracle} from "euler-price-oracle/adapter/pendle/PendleUniversalOracle.sol";
import {FixedRateOracle} from "euler-price-oracle/adapter/fixed/FixedRateOracle.sol";
import {CrossAdapter} from "euler-price-oracle/adapter/CrossAdapter.sol";
import {CurveEMAOracle} from "euler-price-oracle/adapter/curve/CurveEMAOracle.sol";
import {LidoFundamentalOracle} from "euler-price-oracle/adapter/lido/LidoFundamentalOracle.sol";
import {ChainlinkOracle} from "euler-price-oracle/adapter/chainlink/ChainlinkOracle.sol";
import {IPMarket} from "@pendle/core-v2/interfaces/IPMarket.sol";
import {IPPrincipalToken} from "@pendle/core-v2/interfaces/IPPrincipalToken.sol";

abstract contract SetupEulerOracleBase is Script, DeployHelper {
    using stdJson for string;

    EulerRouter internal eulerRouter;

    /// @dev For testing purposes, when  EulerRouter is not deployed yet
    function _deployEulerRouter() internal returns (EulerRouter) {
        address oracleGovernor = getAddress("EulerOracleGovernor");

        vm.startBroadcast();
        EulerRouter _eulerRouter = new EulerRouter(address(1), oracleGovernor);
        vm.stopBroadcast();

        console.log("EulerRouter deployed at:", address(_eulerRouter));

        return _eulerRouter;
    }

    function _deployPendleUniversalOracle(address pendleMarket, address base, address quote, uint32 twapWindow)
        internal
        returns (address)
    {
        address pendleOracle = getAddress("PendleOracle");
        address deployedOracle = _getOracleConfig(base, quote);
        if (deployedOracle != address(0)) {
            return deployedOracle;
        }

        vm.startBroadcast();
        PendleUniversalOracle pendleUniversalOracle =
            new PendleUniversalOracle(pendleOracle, pendleMarket, base, quote, twapWindow);
        eulerRouter.govSetConfig(base, quote, address(pendleUniversalOracle));

        vm.stopBroadcast();

        return address(pendleUniversalOracle);
    }

    function _deployFixedRateOracle(address base, address quote, uint256 rate) internal returns (address) {
        address deployedOracle = _getOracleConfig(base, quote);
        if (deployedOracle != address(0)) {
            return deployedOracle;
        }

        vm.startBroadcast();
        FixedRateOracle fixedRateOracle = new FixedRateOracle(base, quote, rate);
        eulerRouter.govSetConfig(base, quote, address(fixedRateOracle));
        vm.stopBroadcast();

        return address(fixedRateOracle);
    }

    function _deployCrossOracle(
        address base,
        address cross,
        address quote,
        address oracleBaseCross,
        address oracleCrossQuote
    ) internal returns (address) {
        address deployedOracle = _getOracleConfig(base, quote);
        if (deployedOracle != address(0)) {
            return deployedOracle;
        }

        vm.startBroadcast();
        CrossAdapter crossOracle = new CrossAdapter(base, cross, quote, oracleBaseCross, oracleCrossQuote);
        eulerRouter.govSetConfig(base, quote, address(crossOracle));
        vm.stopBroadcast();

        return address(crossOracle);
    }

    function _deployCurveEmaOracle(address curvePool, address base, address quote, uint256 priceOracleIndex)
        internal
        returns (address)
    {
        address deployedOracle = _getOracleConfig(base, quote);
        if (deployedOracle != address(0)) {
            return deployedOracle;
        }

        vm.startBroadcast();
        CurveEMAOracle curveOracle = new CurveEMAOracle(curvePool, base, priceOracleIndex);
        eulerRouter.govSetConfig(base, quote, address(curveOracle));
        vm.stopBroadcast();

        _checkOraclePrice(base, quote);

        return address(curveOracle);
    }

    function _deployLidoFundamentalOracle() internal returns (address lidoFundamentalOracleAddress) {
        address base = getAddress("WSTETH");
        address quote = getAddress("WETH");

        address deployedOracle = _getOracleConfig(base, quote);
        if (deployedOracle != address(0)) {
            return deployedOracle;
        }

        vm.startBroadcast();
        LidoFundamentalOracle lidoFundamentalOracle = new LidoFundamentalOracle();
        eulerRouter.govSetConfig(base, quote, address(lidoFundamentalOracle));
        vm.stopBroadcast();

        lidoFundamentalOracleAddress = address(lidoFundamentalOracle);
    }

    function _deployChainlinkOracle(address base, address quote, address feed, uint256 maxStaleness)
        internal
        returns (address chainlinkOracle)
    {
        address deployedOracle = _getOracleConfig(base, quote);
        if (deployedOracle != address(0)) {
            return deployedOracle;
        }

        vm.startBroadcast();
        ChainlinkOracle oracle = new ChainlinkOracle(base, quote, feed, maxStaleness);
        eulerRouter.govSetConfig(base, quote, address(oracle));
        vm.stopBroadcast();

        chainlinkOracle = address(oracle);
    }

    function _addResolvedVault(address vault) internal returns (address) {
        if (_isResolvedVault(vault)) {
            return address(eulerRouter);
        }

        vm.startBroadcast();
        eulerRouter.govSetResolvedVault(vault, true);
        vm.stopBroadcast();
        return address(eulerRouter);
    }

    function _isResolvedVault(address vault) internal view returns (bool) {
        address asset = eulerRouter.resolvedVaults(vault);
        return asset != address(0);
    }

    function _getOracleConfig(address base, address quote) internal view returns (address oracle) {
        return eulerRouter.getConfiguredOracle(base, quote);
    }

    function _getRequiredOracle(address base, address quote) internal view returns (address oracle) {
        oracle = _getOracleConfig(base, quote);
        if (oracle == address(0)) {
            revert(string.concat("No oracle configured for pair", ERC20(base).symbol(), "/", ERC20(quote).symbol()));
        }
    }

    function _checkOraclePrice(address base, address quote) internal view {
        uint256 inAmount = 1 * 10 ** ERC20(base).decimals();
        uint256 price = eulerRouter.getQuote(inAmount, base, quote);

        string memory baseToken = _getLogTokenName(base);
        string memory quoteToken = _getLogTokenName(quote);

        console.log(string.concat("Oracle price for ", baseToken, "/", quoteToken, " ", vm.toString(price)));
    }

    function _getLogTokenName(address token) internal view returns (string memory) {
        ERC20 tokenContract = ERC20(token);
        if (keccak256(abi.encodePacked(tokenContract.name())) == keccak256(abi.encodePacked("Pendle Market"))) {
            (, IPPrincipalToken pt,) = IPMarket(token).readTokens();
            return string.concat("Pendle LP ", pt.symbol());
        } else {
            return tokenContract.symbol();
        }
    }
}
