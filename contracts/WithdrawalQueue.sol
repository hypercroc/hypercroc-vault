// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";

import {WithdrawalQueueBase} from "./base/WithdrawalQueueBase.sol";

/// @custom:oz-upgrades-unsafe-allow constructor
contract WithdrawalQueue is ERC721Upgradeable, WithdrawalQueueBase {
    using SafeERC20 for IERC4626;

    event WithdrawalRequested(uint256 indexed requestId, address indexed receiver, uint256 shares);
    event WithdrawalClaimed(uint256 indexed requestId, address indexed receiver, uint256 claimedAssets);
    event RequestsFinalized(uint256 lastFinalizedRequest);

    error NotRequestOwner();
    error NotFinalized();
    error Forbidden();

    constructor() {
        _disableInitializers();
    }

    function initialize(address owner, address hyperCrocVault, string calldata name, string calldata symbol)
        external
        initializer
    {
        __ERC721_init(name, symbol);
        __WithdrawalQueueBase_init(owner, hyperCrocVault);
    }

    function requestWithdrawal(uint256 shares, address receiver) external onlyHyperCrocVault returns (uint256 requestId) {
        requestId = _enqueueRequest(shares);
        _safeMint(receiver, requestId);

        emit WithdrawalRequested(requestId, receiver, shares);
    }

    function claimWithdrawal(uint256 requestId, address receiver) external returns (uint256 claimedAssets) {
        if (msg.sender != ownerOf(requestId)) revert NotRequestOwner();
        if (!_isFinalized(requestId)) revert NotFinalized();

        uint256 requestedShares = _removeRequest(requestId);
        claimedAssets = _getHyperCrocVault().redeem(requestedShares, receiver, address(this));

        _burn(requestId);

        emit WithdrawalClaimed(requestId, receiver, claimedAssets);
    }

    function finalizeRequests(uint256 requestId) external onlyFinalizer {
        _finalizeRequests(requestId);
        emit RequestsFinalized(requestId);
    }

    function renounceOwnership() public pure override {
        revert Forbidden();
    }
}
