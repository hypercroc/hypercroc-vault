// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {HyperCrocVaultFactory} from "contracts/HyperCrocVaultFactory.sol";
import {HyperCrocVault} from "contracts/HyperCrocVault.sol";
import {WithdrawalQueue} from "contracts/WithdrawalQueue.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {DeployHelper} from "./helper/DeployHelper.sol";

///@dev Before deploy: create directory "deployment/{chainId}/dry-run" for dry-run or create "deployment/{chainId}" for deploy
///@dev forge script script/DeployHyperCrocVaultFactory.s.sol:DeployHyperCrocVaultFactory -vvvv --account testDeployer --rpc-url $ETH_RPC_URL
contract DeployHyperCrocVaultFactory is Script, DeployHelper {
    using stdJson for string;

    string public constant DEPLOYMENT_FILE = "factory.json";

    struct FactoryDeployment {
        address factoryImplementation;
        address factoryProxy;
        address hyperCrocVaultImplementation;
        address withdrawalQueueImplementation;
    }

    function run() external {
        _createDeploymentFileIfNotExists();

        address deployedFactory = getDeployedFactoryAddress();
        if (deployedFactory != address(0)) {
            console.log("Factory already deployed at", vm.toString(deployedFactory));
            return;
        }

        deployFactory();
    }

    function getDeployedFactoryAddress() public view returns (address) {
        address factoryAddress = _getDeployment().factoryProxy;
        if (factoryAddress.code.length == 0) {
            return address(0);
        }

        return factoryAddress;
    }

    function deployFactory() public returns (address) {
        vm.startBroadcast();
        address hyperCrocVaultImplementation = address(new HyperCrocVault());
        address withdrawalQueueImplementation = address(new WithdrawalQueue());
        address hyperCrocVaultFactoryImplementation = address(new HyperCrocVaultFactory());

        bytes memory data = abi.encodeWithSelector(
            HyperCrocVaultFactory.initialize.selector, hyperCrocVaultImplementation, withdrawalQueueImplementation
        );

        ERC1967Proxy hyperCrocVaultFactoryProxy = new ERC1967Proxy(hyperCrocVaultFactoryImplementation, data);
        vm.stopBroadcast();

        FactoryDeployment memory deployment;
        deployment.factoryProxy = address(hyperCrocVaultFactoryProxy);
        deployment.factoryImplementation = hyperCrocVaultFactoryImplementation;
        deployment.hyperCrocVaultImplementation = hyperCrocVaultImplementation;
        deployment.withdrawalQueueImplementation = withdrawalQueueImplementation;

        _saveDeployment(deployment);

        return deployment.factoryProxy;
    }

    function _createDeploymentFileIfNotExists() private {
        string memory filePath = _getDeploymentPath(DEPLOYMENT_FILE);
        if (!vm.exists(filePath)) {
            FactoryDeployment memory deployment;
            _saveDeployment(deployment);
        }
    }

    function _getDeployment() private view returns (FactoryDeployment memory deployment) {
        string memory filePath = _getDeploymentPath(DEPLOYMENT_FILE);
        string memory jsonFile = vm.readFile(filePath);

        deployment.factoryImplementation = vm.parseJsonAddress(jsonFile, ".FactoryImplementation");
        deployment.factoryProxy = vm.parseJsonAddress(jsonFile, ".FactoryProxy");
        deployment.hyperCrocVaultImplementation = vm.parseJsonAddress(jsonFile, ".HyperCrocVaultImplementation");
        deployment.withdrawalQueueImplementation = vm.parseJsonAddress(jsonFile, ".WithdrawalQueueImplementation");
    }

    function _saveDeployment(FactoryDeployment memory deployment) private {
        string memory path = _getDeploymentPath(DEPLOYMENT_FILE);

        string memory obj = "";
        vm.serializeAddress(obj, "FactoryProxy", deployment.factoryProxy);
        vm.serializeAddress(obj, "FactoryImplementation", deployment.factoryImplementation);
        vm.serializeAddress(obj, "HyperCrocVaultImplementation", deployment.hyperCrocVaultImplementation);
        string memory output =
            vm.serializeAddress(obj, "WithdrawalQueueImplementation", deployment.withdrawalQueueImplementation);
        vm.writeJson(output, path);
    }
}
