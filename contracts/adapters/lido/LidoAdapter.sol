// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IExternalPositionAdapter} from "../../interfaces/IExternalPositionAdapter.sol";
import {AdapterBase} from "../AdapterBase.sol";
import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";
import {Asserts} from "../../libraries/Asserts.sol";
import {IWETH9} from "../../interfaces/IWETH9.sol";
import {IWstETH} from "./interfaces/IWstETH.sol";
import {ILidoWithdrawalQueue} from "./interfaces/ILidoWithdrawalQueue.sol";

contract LidoAdapter is AdapterBase, IExternalPositionAdapter {
    using SafeERC20 for IERC20;
    using Asserts for address;

    struct WithdrawalQueue {
        uint256 start;
        uint256 end;
        mapping(uint256 index => uint256) requests;
    }

    bytes4 public constant getAdapterId = bytes4(keccak256("LidoAdapter"));

    IWstETH private immutable i_wstETH;
    IWETH9 private immutable i_WETH;
    ILidoWithdrawalQueue private immutable i_lidoWithdrawalQueue;
    mapping(address vault => WithdrawalQueue) private s_queues;

    event LidoWithdrawalRequested(address indexed vault, uint256 indexed requestId, uint256 wstEthAmount);
    event LidoWithdrawalClaimed(address indexed vault, uint256 indexed requestId, uint256 wethAmount);

    error LidoAdapter__StakeFailed();
    error LidoAdapter__NoWithdrawRequestInQueue();

    constructor(address weth, address wstETH, address lidoWithdrawalQueue) {
        weth.assertNotZeroAddress();
        wstETH.assertNotZeroAddress();
        lidoWithdrawalQueue.assertNotZeroAddress();

        i_WETH = IWETH9(weth);
        i_wstETH = IWstETH(wstETH);
        i_lidoWithdrawalQueue = ILidoWithdrawalQueue(lidoWithdrawalQueue);
    }

    receive() external payable {}

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IExternalPositionAdapter).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @notice Stake WETH to receive wstETH
    /// @param amount Amount of WETH to stake
    /// @return wstETHAmount Amount of wstETH received after staking
    function stake(uint256 amount) external returns (uint256 wstETHAmount) {
        wstETHAmount = _stake(i_WETH, amount);
    }

    /// @notice Stake all WETH except the given amount to receive wstETH
    /// @param except Amount to be left
    /// @return wstETHAmount Amount of wstETH received after staking
    function stakeAllExcept(uint256 except) external returns (uint256 wstETHAmount) {
        IWETH9 weth = i_WETH;
        uint256 amount = weth.balanceOf(msg.sender) - except;
        wstETHAmount = _stake(weth, amount);
    }

    /// @notice Request withdrawal of ETH from Lido
    /// @param wstETHAmount Amount of wstETH to withdraw
    /// @dev The amount must be greater than or equal to the minimum withdrawal amount defined by Lido 100 Wei
    /// @dev The amount must be less than or equal to the maximum withdrawal amount defined by Lido 1000 ether
    function requestWithdrawal(uint256 wstETHAmount) external {
        _requestWithdrawal(i_wstETH, wstETHAmount);
    }

    /// @notice Request withdrawal all wstETH except given amount
    /// @param except Amount of wstETH to be left
    function requestWithdrawalAllExcept(uint256 except) external {
        IWstETH wstETH = i_wstETH;
        uint256 amount = wstETH.balanceOf(msg.sender) - except;
        _requestWithdrawal(wstETH, amount);
    }

    /// @notice Claim withdrawal
    /// @dev The function receives ETH from the Lido and wraps it into WETH if request was finalized
    function claimWithdrawal() external returns (uint256 wethAmount) {
        IWETH9 weth = i_WETH;
        uint256 requestId = _dequeueWithdrawalRequest();

        ILidoWithdrawalQueue(i_lidoWithdrawalQueue).claimWithdrawal(requestId);
        wethAmount = address(this).balance;
        weth.deposit{value: wethAmount}();
        IERC20(weth).safeTransfer(msg.sender, wethAmount);

        emit LidoWithdrawalClaimed(msg.sender, requestId, wethAmount);
    }

    /// @notice Check if there first withdrawal request is finalized and ready for claim
    /// @param vault Address of the vault to check
    /// @return true if request is claimable
    function isClaimable(address vault) external view returns (bool) {
        WithdrawalQueue storage queue = s_queues[vault];
        uint256 queueStart = queue.start;
        uint256 queueLength = queue.end - queueStart;
        if (queueLength == 0) return false;

        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = queue.requests[queueStart];

        ILidoWithdrawalQueue.WithdrawalRequestStatus memory status =
            i_lidoWithdrawalQueue.getWithdrawalStatus(requestIds)[0];

        return status.isFinalized && !status.isClaimed;
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
        assets[0] = address(i_WETH);

        amounts = new uint256[](1);

        uint256[] memory requestIds = new uint256[](queueLength);
        unchecked {
            for (uint256 i = 0; i < queueLength; ++i) {
                requestIds[i] = queue.requests[queueStart + i];
            }
        }

        ILidoWithdrawalQueue lidoWithdrawalQueue = i_lidoWithdrawalQueue;
        ILidoWithdrawalQueue.WithdrawalRequestStatus[] memory statuses =
            lidoWithdrawalQueue.getWithdrawalStatus(requestIds);
        unchecked {
            for (uint256 i = 0; i < queueLength; ++i) {
                amounts[0] += statuses[i].amountOfStETH;
            }
        }
    }

    function getDebtAssets() external view returns (address[] memory assets, uint256[] memory amounts) {}

    function getWETH() external view returns (address) {
        return address(i_WETH);
    }

    function getWstETH() external view returns (address) {
        return address(i_wstETH);
    }

    function getLidoWithdrawalQueue() external view returns (address) {
        return address(i_lidoWithdrawalQueue);
    }

    function getWithdrawalQueueRequest(address vault, uint256 index) external view returns (uint256 requestId) {
        WithdrawalQueue storage queue = s_queues[vault];
        if (index < queue.start || index >= queue.end) revert LidoAdapter__NoWithdrawRequestInQueue();

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
        if (queueStart == queue.end) revert LidoAdapter__NoWithdrawRequestInQueue();

        requestId = queue.requests[queueStart];
        delete queue.requests[queueStart];
    }

    function _stake(IWETH9 weth, uint256 amount) private returns (uint256 wstETHAmount) {
        IWstETH wstETH = i_wstETH;

        IAdapterCallback(msg.sender).adapterCallback(address(this), address(weth), amount);
        weth.withdraw(amount);
        // stake ETH and wrap it into wstETH
        (bool success,) = address(wstETH).call{value: amount}("");
        if (!success) {
            revert LidoAdapter__StakeFailed();
        }
        wstETHAmount = IERC20(wstETH).balanceOf(address(this));
        IERC20(wstETH).safeTransfer(msg.sender, wstETHAmount);

        emit Swap(msg.sender, address(weth), amount, address(wstETH), wstETHAmount);
    }

    function _requestWithdrawal(IWstETH wstETH, uint256 wstETHAmount) private {
        IAdapterCallback(msg.sender).adapterCallback(address(this), address(wstETH), wstETHAmount);

        ILidoWithdrawalQueue withdrawalQueue = i_lidoWithdrawalQueue;
        IERC20(wstETH).forceApprove(address(withdrawalQueue), wstETHAmount);

        uint256 maxLidoWithdrawal = wstETH.getWstETHByStETH(withdrawalQueue.MAX_STETH_WITHDRAWAL_AMOUNT());
        uint256 additionalWithdrawalsNumber = wstETHAmount / maxLidoWithdrawal;
        uint256 length = additionalWithdrawalsNumber + 1;
        uint256[] memory amounts = new uint256[](additionalWithdrawalsNumber + 1);
        unchecked {
            for (uint256 i; i < additionalWithdrawalsNumber; ++i) {
                amounts[i] = maxLidoWithdrawal;
            }
        }
        amounts[additionalWithdrawalsNumber] = wstETHAmount % maxLidoWithdrawal;

        uint256[] memory requestIds = withdrawalQueue.requestWithdrawalsWstETH(amounts, address(0));
        for (uint256 i = 0; i < length;) {
            emit LidoWithdrawalRequested(msg.sender, requestIds[i], amounts[i]);
            _enqueueWithdrawalRequest(requestIds[i]);

            unchecked {
                ++i;
            }
        }
    }
}
