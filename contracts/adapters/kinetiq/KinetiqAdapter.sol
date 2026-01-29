// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IExternalPositionAdapter} from "../../interfaces/IExternalPositionAdapter.sol";
import {AdapterBase} from "../AdapterBase.sol";
import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";
import {Asserts} from "../../libraries/Asserts.sol";
import {IWETH9} from "../../interfaces/IWETH9.sol";
import {IStakingManager} from "./interfaces/IStakingManager.sol";

contract KinetiqAdapter is AdapterBase, IExternalPositionAdapter {
    using SafeERC20 for IERC20;
    using Asserts for address;

    struct WithdrawalQueue {
        uint256 start;
        uint256 end;
        mapping(uint256 index => uint256) requests;
    }

    bytes4 public constant getAdapterId = bytes4(keccak256("KinetiqAdapter"));

    IWETH9 private immutable i_wHYPE;
    IStakingManager private immutable i_stakingManager;
    IERC20 private immutable i_kHYPE;
    mapping(address vault => WithdrawalQueue) private s_queues;

    event KinetiqWithdrawalRequested(address indexed vault, uint256 indexed requestId, uint256 wstEthAmount);
    event KinetiqWithdrawalClaimed(address indexed vault, uint256 indexed requestId, uint256 wethAmount);

    error KinetiqAdapter__NoWithdrawRequestInQueue();

    constructor(address wHYPE, address stakingManager) {
        wHYPE.assertNotZeroAddress();
        stakingManager.assertNotZeroAddress();

        i_wHYPE = IWETH9(wHYPE);
        i_stakingManager = IStakingManager(stakingManager);
        i_kHYPE = IERC20(IStakingManager(stakingManager).kHYPE());
    }

    receive() external payable {}

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IExternalPositionAdapter).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @notice Stake wHYPE to receive kHYPE
    /// @param amount Amount of wHYPE to stake
    /// @return kHYPEAmount Amount of kHYPE received after staking
    function stake(uint256 amount) external returns (uint256 kHYPEAmount) {
        kHYPEAmount = _stake(i_wHYPE, amount);
    }

    /// @notice Stake all wHYPE except the given amount to receive kHYPE
    /// @param except Amount to be left
    /// @return kHYPEAmount Amount of kHYPE received after staking
    function stakeAllExcept(uint256 except) external returns (uint256 kHYPEAmount) {
        IWETH9 wHYPE = i_wHYPE;
        uint256 amount = wHYPE.balanceOf(msg.sender) - except;
        kHYPEAmount = _stake(wHYPE, amount);
    }

    /// @notice Request withdrawal of Hype from Kinetiq
    /// @param kHYPEAmount Amount of kHYPE to withdraw
    function requestWithdrawal(uint256 kHYPEAmount) external {
        _requestWithdrawal(i_kHYPE, kHYPEAmount);
    }

    /// @notice Request withdrawal all kHYPE except given amount
    /// @param except Amount of kHYPE to be left
    function requestWithdrawalAllExcept(uint256 except) external {
        IERC20 kHYPE = i_kHYPE;
        uint256 amount = kHYPE.balanceOf(msg.sender) - except;
        _requestWithdrawal(kHYPE, amount);
    }

    /// @notice Claim withdrawal
    /// @dev The function receives HYPE from the Kinetiq and wraps it into wHYPE if request was finalized
    function claimWithdrawal() external returns (uint256 wHYPEAmount) {
        IWETH9 wHYPE = i_wHYPE;
        uint256 requestId = _dequeueWithdrawalRequest();

        i_stakingManager.confirmWithdrawal(requestId);

        wHYPEAmount = address(this).balance;
        wHYPE.deposit{value: wHYPEAmount}();
        IERC20(wHYPE).safeTransfer(msg.sender, wHYPEAmount);

        emit KinetiqWithdrawalClaimed(msg.sender, requestId, wHYPEAmount);
    }

    /// @notice Check if there first withdrawal request is finalized and ready for claim
    /// @param vault Address of the vault to check
    /// @return true if request is claimable
    function isClaimable(address vault) external view returns (bool) {
        WithdrawalQueue storage queue = s_queues[vault];
        uint256 queueStart = queue.start;
        uint256 queueLength = queue.end - queueStart;
        if (queueLength == 0) return false;

        IStakingManager stakingManager = i_stakingManager;
        uint256 delay = stakingManager.withdrawalDelay();
        IStakingManager.WithdrawalRequest memory request =
            stakingManager.withdrawalRequests(address(this), queue.requests[queueStart]);

        if (block.timestamp < request.timestamp + delay) return false;
        return address(stakingManager).balance >= request.hypeAmount;
    }

    function getManagedAssets() external view returns (address[] memory assets, uint256[] memory amounts) {
        return getManagedAssets(msg.sender);
    }

    /// @dev Returns non zero value when vault has pending withdrawal requests
    /// @param vault Address of the vault
    function getManagedAssets(address vault) public view returns (address[] memory assets, uint256[] memory amounts) {
        WithdrawalQueue storage queue = s_queues[vault];
        uint256 queueStart = queue.start;
        uint256 queueLength = queue.end - queueStart;
        if (queueLength == 0) {
            return (assets, amounts);
        }

        assets = new address[](1);
        assets[0] = address(i_wHYPE);

        amounts = new uint256[](1);

        IStakingManager stakingManager = i_stakingManager;
        for (uint256 i; i < queueLength; ++i) {
            IStakingManager.WithdrawalRequest memory request =
                stakingManager.withdrawalRequests(address(this), queue.requests[queueStart + i]);
            amounts[0] += request.hypeAmount;

            unchecked {
                ++i;
            }
        }
        
    }

    function getDebtAssets() external view returns (address[] memory assets, uint256[] memory amounts) {}

    function getWHYPE() external view returns (address) {
        return address(i_wHYPE);
    }

    function getKHYPE() external view returns (address) {
        return address(i_kHYPE);
    }

    function getKinetiqStakingManager() external view returns (address) {
        return address(i_stakingManager);
    }

    function getWithdrawalQueueRequest(address vault, uint256 index) external view returns (uint256 requestId) {
        WithdrawalQueue storage queue = s_queues[vault];
        if (index < queue.start || index >= queue.end) revert KinetiqAdapter__NoWithdrawRequestInQueue();

        requestId = queue.requests[index];
    }

    function getWithdrawalQueueStart(address vault) external view returns (uint256 start) {
        WithdrawalQueue storage queue = s_queues[vault];
        start = queue.start;
    }

    function getWithdrawalQueueEnd(address vault) external view returns (uint256 end) {
        WithdrawalQueue storage queue = s_queues[vault];
        end = queue.end;
    }

    function _enqueueWithdrawalRequest(uint256 requestId) private {
        WithdrawalQueue storage queue = s_queues[msg.sender];
        unchecked {
            queue.requests[queue.end++] = requestId;
        }
    }

    function _dequeueWithdrawalRequest() private returns (uint256 requestId) {
        WithdrawalQueue storage queue = s_queues[msg.sender];
        uint256 queueStart;
        unchecked {
            queueStart = queue.start++;
        }
        if (queueStart == queue.end) revert KinetiqAdapter__NoWithdrawRequestInQueue();

        requestId = queue.requests[queueStart];
        delete queue.requests[queueStart];
    }

    function _stake(IWETH9 wHYPE, uint256 amount) private returns (uint256 kHYPEAmount) {
        IAdapterCallback(msg.sender).adapterCallback(address(this), address(wHYPE), amount);
        wHYPE.withdraw(amount);
        i_stakingManager.stake{value: amount}();

        IERC20 kHYPE = i_kHYPE;
        kHYPEAmount = kHYPE.balanceOf(address(this));
        kHYPE.safeTransfer(msg.sender, kHYPEAmount);

        emit Swap(msg.sender, address(wHYPE), amount, address(kHYPE), kHYPEAmount);
    }

    function _requestWithdrawal(IERC20 kHYPE, uint256 kHYPEAmount) private {
        IAdapterCallback(msg.sender).adapterCallback(address(this), address(kHYPE), kHYPEAmount);
        
        IStakingManager stakingManager = i_stakingManager;
        kHYPE.forceApprove(address(stakingManager), kHYPEAmount);

        uint256 requestId = stakingManager.nextWithdrawalId(address(this));
        stakingManager.queueWithdrawal(kHYPEAmount);

        _enqueueWithdrawalRequest(requestId);

        emit KinetiqWithdrawalRequested(msg.sender, requestId, kHYPEAmount);
    }
}
