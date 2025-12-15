// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Vm} from "lib/forge-std/src/Vm.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {TestSetUp} from "./TestSetUp.t.sol";
import {HyperCrocVaultFactory} from "../contracts/HyperCrocVaultFactory.sol";

contract HyperCrocVaultFactoryTest is TestSetUp {
    function test_deployVaultOnlyOwner() public {
        vm.prank(NO_ACCESS);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, NO_ACCESS));
        hyperCrocVaultFactory.deployVault(
            address(asset),
            LP_NAME,
            LP_SYMBOL,
            WITHDRAWAL_QUEUE_NAME,
            WITHDRAWAL_QUEUE_SYMBOL,
            FEE_COLLECTOR,
            address(oracle)
        );
    }

    function test_renounceOwnership() public {
        vm.expectRevert(abi.encodeWithSelector(HyperCrocVaultFactory.Forbidden.selector));
        hyperCrocVaultFactory.renounceOwnership();
    }
}
