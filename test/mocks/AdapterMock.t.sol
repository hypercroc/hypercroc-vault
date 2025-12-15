// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IAdapter} from "../../contracts/interfaces/IAdapter.sol";
import {IAdapterCallback} from "../../contracts/interfaces/IAdapterCallback.sol";

contract AdapterMock is IERC165, IAdapter, Test {
    uint256 public actionsExecuted = 0;
    bytes public recentCalldata;

    function action(bytes calldata data) external returns (uint256) {
        actionsExecuted += 1;
        recentCalldata = data;
        return actionsExecuted;
    }

    function slippage(address tokenToTake, uint256 amount) external {
        IAdapterCallback(msg.sender).adapterCallback(address(this), tokenToTake, amount);
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IAdapter).interfaceId;
    }

    function getAdapterId() external pure override returns (bytes4) {
        return bytes4(keccak256("AdapterMock"));
    }
}
