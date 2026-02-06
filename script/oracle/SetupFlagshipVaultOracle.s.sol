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
import {IPMarket} from "@pendle/core-v2/interfaces/IPMarket.sol";
import {IPPrincipalToken} from "@pendle/core-v2/interfaces/IPPrincipalToken.sol";
import {SetupEulerOracleBase} from "./SetupEulerOracleBase.sol";

///@dev forge script script/oracle/SetupFlagshipVaultOracle.s.sol:SetupFlagshipVaultOracle -vvvv --account testDeployer --rpc-url $HYPER_RPC_URL
contract SetupFlagshipVaultOracle is SetupEulerOracleBase {
    using stdJson for string;

    function run() external {
        eulerRouter = EulerRouter(getAddress("EulerOracle"));
        setupFlagshipVaultOracle();
    }

    function setupFlagshipVaultOracle() public {
        // _setupPrice_USDT__USD();
        // _setupPrice_wHYPE__USDT();
        // _setupPrice_UETH__USDT();
        // _setupPrice_UBTC__USDT();
        // _setupPrice_kHYPE__USDT();
        // _setupPrice_hUSDT__USDT();
        // _setupPrice_hbUSDT__USDT();
        // _setupPrice_xHYPE__USDT();
    }

    function _setupPrice_USDT__USD() private {
        address USDT = getAddress("USDT");

        _addChainlink_USDT__USD();
        _checkOraclePrice(USDT, USD);
    }

    function _setupPrice_hUSDT__USDT() private {
        address hUSDT = getAddress("hUSDT");
        address USDT = getAddress("USDT");

        _addHyperlend_hUsdt_USDT_price();
        _checkOraclePrice(hUSDT, USDT);
    }

    function _setupPrice_hbUSDT__USDT() private {
        address hbUSDT = getAddress("hbUSDT");
        address USDT = getAddress("USDT");

        _addRedstone_hbUSDT__USDT();
        _checkOraclePrice(hbUSDT, USDT);
    }

    function _setupPrice_wHYPE__USDT() private {
        address wHYPE = getAddress("wHYPE");
        address USDT = getAddress("USDT");

        _addCrossOracle_wHYPE__USDT();
        _checkOraclePrice(wHYPE, USDT);
    }

    function _setupPrice_UETH__USDT() private {
        address UETH = getAddress("UETH");
        address USDT = getAddress("USDT");

        _addCrossOracle_UETH__USDT();
        _checkOraclePrice(UETH, USDT);
    }

    function _setupPrice_UBTC__USDT() private {
        address UBTC = getAddress("UBTC");
        address USDT = getAddress("USDT");

        _addCrossOracle_UBTC__USDT();
        _checkOraclePrice(UBTC, USDT);
    }

    function _setupPrice_kHYPE__USDT() private {
        address kHYPE = getAddress("kHYPE");
        address USDT = getAddress("USDT");

        _addCrossOracle_kHYPE__USDT();
        _checkOraclePrice(kHYPE, USDT);
    }

    function _setupPrice_xHYPE__USDT() private {
        address xHYPE = getAddress("xHYPE");
        address USDT = getAddress("USDT");

        _addCrossOracle_xHYPE__USDT();
        _checkOraclePrice(xHYPE, USDT);
    }

    function _addHyperlend_hUsdt_USDT_price() private returns (address) {
        address hUSDT = getAddress("hUSDT");
        address USDT = getAddress("USDT");
        uint256 baseDecimals = ERC20(hUSDT).decimals();
        uint256 rate = 10 ** baseDecimals; // fixed conversion rate between hUSDT and USDT

        return _deployFixedRateOracle(hUSDT, USDT, rate);
    }

     function _addPyth_xHYPE__USDC() private returns (address) {
        address pyth = getAddress("PythOracle");
        address xHYPE = getAddress("xHYPE");
        address USDC = getAddress("USDC");
        bytes32 pythFeedId = getBytes32("PythFeedId_xHYPE_USDC");
        uint256 maxStaleness = 15 minutes;
        uint256 maxConfWidth = 100;

        return _deployPythOracle(xHYPE, USDC, pyth, pythFeedId, maxStaleness, maxConfWidth);
    }

    function _addRedstone_hbUSDT__USDT() private returns (address) {
        address hbUSDT = getAddress("hbUSDT");
        address USDT = getAddress("USDT");
        address redstoneFeed = getAddress("RedstoneFeed_hbUSDT_USDT");
        uint256 maxStaleness = 1 days;

        return _deployChainlinkOracle(hbUSDT, USDT, redstoneFeed, maxStaleness);
    }

    function _addChainlink_USDT__USD() private returns (address) {
        address USDT = getAddress("USDT");
        address chainlinkFeed = getAddress("ChainlinkFeed_USDT_USD");
        uint256 maxStaleness = 1 days;

        return _deployChainlinkOracle(USDT, USD, chainlinkFeed, maxStaleness);
    }

    function _addChainlink_USDC__USD() private returns (address) {
        address USDC = getAddress("USDC");
        address chainlinkFeed = getAddress("ChainlinkFeed_USDC_USD");
        uint256 maxStaleness = 1 days;

        return _deployChainlinkOracle(USDC, USD, chainlinkFeed, maxStaleness);
    }

    function _addCrossOracle_wHYPE__USDT() private returns (address) {
        address wHYPE = getAddress("wHYPE");
        address USDT = getAddress("USDT");
        address chainlinkFeed = getAddress("ChainlinkFeed_HYPE_USD");
        uint256 maxStaleness = 1 days;

        address hypeUsdOracle = _deployChainlinkOracle(wHYPE, USD, chainlinkFeed, maxStaleness);
        address usdtUsdOracle = getAddress("Chainlink_USDT_USD_oracle");

        return _deployCrossOracle(wHYPE, USD, USDT, hypeUsdOracle, usdtUsdOracle);
    }

    function _addCrossOracle_UETH__USDT() private returns (address) {
        address UETH = getAddress("UETH");
        address USDT = getAddress("USDT");
        address chainlinkFeed = getAddress("ChainlinkFeed_UETH_USD");
        uint256 maxStaleness = 1 days;

        address hypeUsdOracle = _deployChainlinkOracle(UETH, USD, chainlinkFeed, maxStaleness);
        address usdtUsdOracle = getAddress("Chainlink_USDT_USD_oracle");

        return _deployCrossOracle(UETH, USD, USDT, hypeUsdOracle, usdtUsdOracle);
    }

    function _addCrossOracle_UBTC__USDT() private returns (address) {
        address UBTC = getAddress("UBTC");
        address USDT = getAddress("USDT");
        address chainlinkFeed = getAddress("ChainlinkFeed_UBTC_USD");
        uint256 maxStaleness = 1 days;

        address hypeUsdOracle = _deployChainlinkOracle(UBTC, USD, chainlinkFeed, maxStaleness);
        address usdtUsdOracle = getAddress("Chainlink_USDT_USD_oracle");

        return _deployCrossOracle(UBTC, USD, USDT, hypeUsdOracle, usdtUsdOracle);
    }

    function _addCrossOracle_USDT__USDC() private returns (address) {
        address USDC = getAddress("USDC");
        address USDT = getAddress("USDT");

        address usdcUsdOracle = getAddress("Chainlink_USDC_USD_oracle");
        address usdtUsdOracle = getAddress("Chainlink_USDT_USD_oracle");

        return _deployCrossOracle(USDT, USD, USDC, usdtUsdOracle, usdcUsdOracle);
    }

    function _addCrossOracle_kHYPE__USDT() private returns (address) {
        address kHYPE = getAddress("kHYPE");
        address wHYPE = getAddress("wHYPE");
        address USDT = getAddress("USDT");
        address chainlinkFeed = getAddress("ChainlinkFeed_kHYPE_HYPE");
        uint256 maxStaleness = 1 days;
        address kHYPEwHYPEOracle = _deployChainlinkOracle(kHYPE, wHYPE, chainlinkFeed, maxStaleness);
        address wHYPEUsdtOracle = getAddress("Cross_wHYPE_USDT_oracle");

        return _deployCrossOracle(kHYPE, wHYPE, USDT, kHYPEwHYPEOracle, wHYPEUsdtOracle);
    }

    function _addCrossOracle_xHYPE__USDT() private returns (address) {
        address xHYPE = getAddress("xHYPE");
        address USDT = getAddress("USDT");
        address USDC = getAddress("USDC");
        address xHypeUsdcOracle = _addPyth_xHYPE__USDC();
        _checkOraclePrice(xHYPE, USDC);
        address usdtUsdcOracle = _addCrossOracle_USDT__USDC();

        return _deployCrossOracle(xHYPE, USDC, USDT, xHypeUsdcOracle, usdtUsdcOracle);
    }

    function _addChainlink_UETH__USD() private returns (address) {
        address UETH = getAddress("UETH");
        address chainlinkFeed = getAddress("ChainlinkFeed_UETH_USD");
        uint256 maxStaleness = 1 days;

        return _deployChainlinkOracle(UETH, USD, chainlinkFeed, maxStaleness);
    }

    function _addChainlink_UBTC__USD() private returns (address) {
        address UBTC = getAddress("UBTC");
        address chainlinkFeed = getAddress("ChainlinkFeed_UBTC_USD");
        uint256 maxStaleness = 1 days;

        return _deployChainlinkOracle(UBTC, USD, chainlinkFeed, maxStaleness);
    }
}
