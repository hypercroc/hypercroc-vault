// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {DeployHelper} from "./helper/DeployHelper.sol";
import {EulerRouter} from "euler-price-oracle/EulerRouter.sol";

interface IEulerRouterFactory {
    function deploy(address governor) external returns (address);
}

///@dev forge script script/DeployEulerOracle.s.sol:DeployEulerOracle -vvvv --account hyperCrocDeployer --rpc-url $ETH_RPC_URL --broadcast --verify --delay 7 --retries 15 --verifier etherscan --etherscan-api-key $ETHERSCAN_KEY --verifier-url https://api.etherscan.io/api
contract DeployEulerOracle is Script, DeployHelper {
    string public constant DEPLOYMENT_FILE = "price-oracle.json";

    function run() external {
        _deployWithFactory();
    }

    function _deployWithFactory() internal {
        /* 
        * We use EulerOracleFactory from euler.finance to deploy euler price oracle 
        */
        address eulerOracleFactory = getAddress("EulerOracleFactory");
        address eulerOracleGovernor = getAddress("EulerOracleGovernor");

        vm.broadcast();
        address eulerOracle = IEulerRouterFactory(eulerOracleFactory).deploy(eulerOracleGovernor);

        _saveDeployment(eulerOracle);
    }

    function _deployStandalone() internal {
        /* 
        * For standalone deployment
        */
        address evcAddress = getAddress("EulerEVC");
        address eulerOracleGovernor = getAddress("EulerOracleGovernor");

        vm.broadcast();
        EulerRouter eulerOracle = new EulerRouter(evcAddress, eulerOracleGovernor);

        _saveDeployment(address(eulerOracle));
    }

    function _saveDeployment(address eulerOracle) internal {
        string memory path = _getDeploymentPath(DEPLOYMENT_FILE);
        if (!vm.exists(path)) {
            _createEmptyDeploymentFile(path);
        }

        _saveInDeploymentFile(path, "EulerOracle", eulerOracle);
    }
}
