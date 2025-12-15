// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ChainValues} from "./ChainValues.sol";

abstract contract DeployHelper is Script, ChainValues {
    using stdJson for string;
    using Strings for uint256;

    function _getDeploymentPath(string memory deploymentName) internal view returns (string memory) {
        bool isDryRunMode = vm.isContext(VmSafe.ForgeContext.ScriptDryRun);

        string memory root = vm.projectRoot();
        string memory chainDir = string.concat(vm.toString(block.chainid), "-", getChainName());
        string memory path = isDryRunMode
            ? string.concat(root, "/script/deployment/", chainDir, "/dry-run/", deploymentName)
            : string.concat(root, "/script/deployment/", chainDir, "/", deploymentName);
        return path;
    }

    function _createEmptyDeploymentFile(string memory path) internal {
        vm.writeFile(path, "{}");
    }

    function _saveInDeploymentFile(string memory path, string memory valueKey, address value) internal {
        if (!vm.exists(path)) {
            _createEmptyDeploymentFile(path);
        }

        string memory obj = "";
        string memory jsonFile = vm.readFile(path);
        vm.serializeJson(obj, jsonFile);
        string memory output = vm.serializeAddress(obj, valueKey, value);

        vm.writeJson(output, path);
    }

    function _readAddressFromDeployment(string memory deploymentFile, string memory valueKey)
        internal
        view
        returns (address)
    {
        string memory path = _getDeploymentPath(deploymentFile);
        if (!vm.exists(path)) {
            return address(0);
        }
        string memory jsonFile = vm.readFile(path);

        // Assume we need to read AaveAdapter address from json {"AaveAdapter": "0x..."}
        // Read value from json by key ".AaveAdapter", "." mean root level
        string memory jsonKey = string.concat(".", valueKey);
        if (!jsonFile.keyExists(jsonKey)) {
            return address(0);
        }

        address targetAddress = jsonFile.readAddress(jsonKey);
        if (targetAddress.code.length == 0) {
            return address(0);
        }

        return targetAddress;
    }
}
