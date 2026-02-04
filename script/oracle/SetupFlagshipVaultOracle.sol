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
contract SetupUltraSafeVaultOracle is SetupEulerOracleBase {
    using stdJson for string;

    function run() external {
        eulerRouter = EulerRouter(getAddress("EulerOracle"));
        setupFlagshipVaultOracle();
    }

    function setupFlagshipVaultOracle() public {
        _setupPrice_hUSDT__USDT();
    }

    function _setupPrice_hUSDT__USDT() private {
        address hUSDT = getAddress("hUSDT");
        address USDT = getAddress("USDT");

        _addHyperlend_hUsdt_USDT_price();
        _checkOraclePrice(hUSDT, USDT);
    }

    function _addHyperlend_hUsdt_USDT_price() private returns (address) {
        address hUSDT = getAddress("hUSDT");
        address USDT = getAddress("USDT");
        uint256 baseDecimals = ERC20(hUSDT).decimals();
        uint256 rate = 10 ** baseDecimals; // fixed conversion rate between aUSDC and USDC

        return _deployFixedRateOracle(hUSDT, USDT, rate);
    }

    function _addRedstone_hbUSDT__USDT() private returns (address) {
        address hbUSDT = getAddress("hbUSDT");
        address USDT = getAddress("USDT");
        bytes redstoneFeedId = getBytes32("RedstoneFeedId_hbUSDT_USDT");
        uint8 redstoneFeedDecimals = getUint8("RedstoneFeedDecimals_hbUSDT_USDT");
        uint256 maxStaleness = 1.5 days;

        return _deployRedstoneOracle(USDT, USD, chainlinkFeed, maxStaleness);
    }

     function _addPyth_xHYPE__USDC() private returns (address) {
        address pyth = getAddress("PythOracle");
        address xHYPE = getAddress("xHYPE");
        address USDC = getAddress("USDC");
        bytes pythFeedId = getBytes32("PythFeedId_xHYPE_USDC");
        uint256 maxStaleness = 1.5 days;
        uint256 maxConfWidth = 100;

        return _deployPythOracle(pyth, xHYPE, USDC, pythFeedId, maxStaleness, maxConfWidth);
    }

    function _addChainlink_USDT__USD() private returns (address) {
        address USDT = getAddress("USDT");
        address chainlinkFeed = getAddress("ChainlinkFeed_USDT_USD");
        uint256 maxStaleness = 1.5 days;

        return _deployChainlinkOracle(USDT, USD, chainlinkFeed, maxStaleness);
    }

    function _addChainlink_HYPE__USD() private returns (address) {
        address HYPE = getAddress("HYPE");
        address chainlinkFeed = getAddress("ChainlinkFeed_HYPE_USD");
        uint256 maxStaleness = 1.5 days;

        return _deployChainlinkOracle(HYPE, USD, chainlinkFeed, maxStaleness);
    }

    function _addChainlink_kHYPE__HYPE() private returns (address) {
        address HYPE = getAddress("HYPE");
        address kHYPE = getAddress("kHYPE");
        address chainlinkFeed = getAddress("ChainlinkFeed_kHYPE_HYPE");
        uint256 maxStaleness = 1.5 days;

        return _deployChainlinkOracle(kHYPE, HYPE, chainlinkFeed, maxStaleness);
    }

    function _addChainlink_UETH__USD() private returns (address) {
        address UETH = getAddress("UETH");
        address chainlinkFeed = getAddress("ChainlinkFeed_UETH_USD");
        uint256 maxStaleness = 1.5 days;

        return _deployChainlinkOracle(UETH, USD, chainlinkFeed, maxStaleness);
    }

    function _addChainlink_UBTC__USD() private returns (address) {
        address UBTC = getAddress("UBTC");
        address chainlinkFeed = getAddress("ChainlinkFeed_UBTC_USD");
        uint256 maxStaleness = 1.5 days;

        return _deployChainlinkOracle(UBTC, USD, chainlinkFeed, maxStaleness);
    }
}
