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

///@dev forge script script/oracle/SetupUltraSafeVaultOracle.s.sol:SetupUltraSafeVaultOracle -vvvv --account testDeployer --rpc-url $ETH_RPC_URL
contract SetupUltraSafeVaultOracle is SetupEulerOracleBase {
    using stdJson for string;

    function run() external {
        eulerRouter = EulerRouter(getAddress("EulerOracle"));
        setupUltraSafeVaultOracle();
    }

    function setupUltraSafeVaultOracle() public {
        /**
         * Setup prices for pairs:
         * aUSDC/USDC
         * LP_sUSDE_25Sep2025/USDC
         * LP_wstUSR_25Sep2025/USDC
         * LVVA-sUSDE/USDC (Technical vault to manage PT-sUSDE/sUSDE farming pools)
         * LVVA-wstUSR/USDC (Technical vault to manage PT-wstUSR/wstUSR farming Pools)
         */
        _setupPrice_aUSDC__USDC();
        _setupPrice_LP_sUSDE_25Sep2025__USDE();
        _setupPrice_LP_wstUSR_25Sep2025__USDC();
        //_setupPrice_LVVA_sUSDE__USDC();
        //_setupPrice_LVVA_wstUSR__USDC();
    }

    function _setupPrice_aUSDC__USDC() private {
        address aUSDC = getAddress("aUSDC");
        address USDC = getAddress("USDC");

        _addAave_aUsdc_USDC_price();
        _checkOraclePrice(aUSDC, USDC);
    }

    function _setupPrice_LP_sUSDE_25Sep2025__USDE() private {
        address USDE = getAddress("USDE");
        address USDC = getAddress("USDC");
        address LP_sUSDE_25Sep2025 = getAddress("PendleMarket_sUSDE_25sep2025");

        address lp_sUSDE25Sep2025_USDE_oracle = _addPendleOracle_LP_sUSDE_25Sep2025__USDE();
        _checkOraclePrice(LP_sUSDE_25Sep2025, USDE);

        address USDE_USD_oracle = getAddress("Chainlink_USDE_USD_oracle");
        address USDC_USD_oracle = getAddress("Chainlink_USDC_USD_oracle");
        address USDE_USDC_oracle = _deployCrossOracle(USDE, USD, USDC, USDE_USD_oracle, USDC_USD_oracle);
        _checkOraclePrice(USDE, USDC);

        _deployCrossOracle(LP_sUSDE_25Sep2025, USDE, USDC, lp_sUSDE25Sep2025_USDE_oracle, USDE_USDC_oracle);

        _checkOraclePrice(LP_sUSDE_25Sep2025, USDC);
    }

    function _setupPrice_LP_wstUSR_25Sep2025__USDC() private {
        address USR = getAddress("USR");
        address USDC = getAddress("USDC");
        address LP_wstUSR_25Sep2025 = getAddress("PendleMarket_wstUSR_25sep2025");

        address lp_wstUSR_25Sep2025_USR_oracle = _addPendleOracle_LP_wstUSR_25Sep2025__USR();
        _checkOraclePrice(LP_wstUSR_25Sep2025, USR);

        address USR_USD_oracle = _addChainlink_USR__USD();
        address USDC_USD_oracle = getAddress("Chainlink_USDC_USD_oracle");
        address USR_USDC_oracle = _deployCrossOracle(USR, USD, USDC, USR_USD_oracle, USDC_USD_oracle);
        _checkOraclePrice(USR, USDC);

        _deployCrossOracle(LP_wstUSR_25Sep2025, USR, USDC, lp_wstUSR_25Sep2025_USR_oracle, USR_USDC_oracle);

        _checkOraclePrice(LP_wstUSR_25Sep2025, USDC);
    }

    function _setupPrice_LVVA_sUSDE__USDC() private {
        address sUSDE = getAddress("sUSDE");
        address USDC = getAddress("USDC");
        address LVVA_sUSDE = getAddress("LVVA_sUSDE");

        address sUSDE_USDC_oracle = _getRequiredOracle(sUSDE, USDC);

        address LVVA_sUSDE_sUSDE_oracle = _addResolvedVault_LVVA_sUSDE_sUSDE();

        _deployCrossOracle(LVVA_sUSDE, sUSDE, USDC, LVVA_sUSDE_sUSDE_oracle, sUSDE_USDC_oracle);

        _checkOraclePrice(LVVA_sUSDE, USDC);
    }

    function _setupPrice_LVVA_wstUSR__USDC() private {
        address wstUSR = getAddress("WSTUSR");
        address USR = getAddress("USR");
        address USDC = getAddress("USDC");
        address LVVA_wstUSR = getAddress("LVVA_wstUSR");

        address wstUSR_USR_oracle = _addResolvedVault(getAddress("WSTUSR"));
        address USR_USDC_oracle = _getRequiredOracle(USR, USDC);

        _deployCrossOracle(LVVA_wstUSR, wstUSR, USDC, wstUSR_USR_oracle, USR_USDC_oracle);

        _checkOraclePrice(LVVA_wstUSR, USDC);
    }

    function _addPendleOracle_LP_sUSDE_25Sep2025__USDE() private returns (address) {
        address LP_sUSDE_25sep2025 = getAddress("PendleMarket_sUSDE_25sep2025");
        address USDE = getAddress("USDE");
        uint32 twapWindow = 5 minutes;

        return _deployPendleUniversalOracle(LP_sUSDE_25sep2025, LP_sUSDE_25sep2025, USDE, twapWindow);
    }

    function _addPendleOracle_LP_wstUSR_25Sep2025__USR() private returns (address) {
        address LP_wstUSR_25sep2025 = getAddress("PendleMarket_wstUSR_25sep2025");
        address USR = getAddress("USR");
        uint32 twapWindow = 5 minutes;

        return _deployPendleUniversalOracle(LP_wstUSR_25sep2025, LP_wstUSR_25sep2025, USR, twapWindow);
    }

    function _addAave_aUsdc_USDC_price() private returns (address) {
        address aUSDC = getAddress("aUSDC");
        address USDC = getAddress("USDC");
        uint256 baseDecimals = ERC20(aUSDC).decimals();
        uint256 rate = 10 ** baseDecimals; // fixed conversion rate between aUSDC and USDC

        return _deployFixedRateOracle(aUSDC, USDC, rate);
    }

    function _addCurveEma_USR_USDC() private returns (address) {
        address curvePool = getAddress("CurvePool_USR_USDC");
        address USDC = getAddress("USDC");
        address USR = getAddress("USR");
        uint256 priceOracleIndex = 0; // curve parameter type(uint256).max for price_oracle(), and index for price_oracle(priceOracleIndex)

        return _deployCurveEmaOracle(curvePool, USDC, USR, priceOracleIndex);
    }

    function _addChainlink_USR__USD() private returns (address) {
        address USR = getAddress("USR");
        address chainlinkFeed = getAddress("ChainlinkFeed_USR_USD");
        uint256 maxStaleness = 1.5 days;

        return _deployChainlinkOracle(USR, USD, chainlinkFeed, maxStaleness);
    }

    function _addResolvedVault_LVVA_sUSDE_sUSDE() private returns (address) {
        address LVVA_sUSDE = getAddress("LVVA_sUSDE");

        if (_isResolvedVault(LVVA_sUSDE)) {
            return address(eulerRouter);
        }

        vm.startBroadcast();
        eulerRouter.govSetResolvedVault(LVVA_sUSDE, true);
        vm.stopBroadcast();
        return address(eulerRouter);
    }
}
