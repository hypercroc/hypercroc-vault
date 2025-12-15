// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IAdapter} from "../interfaces/IAdapter.sol";

abstract contract AdapterBase is IERC165, IAdapter {
    /// @notice Implementation of ERC165, supports IAdapter and IERC165
    /// @param interfaceId interface identifier
    function supportsInterface(bytes4 interfaceId) public pure virtual returns (bool) {
        return interfaceId == type(IAdapter).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
