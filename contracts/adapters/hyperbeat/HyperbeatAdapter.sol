// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IExternalPositionAdapter} from "../../interfaces/IExternalPositionAdapter.sol";
import {AdapterBase} from "../AdapterBase.sol";
import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";
import {Asserts} from "../../libraries/Asserts.sol";
import {IDepositor} from "./interfaces/IDepositor.sol";
import {IWithdrawalQueue} from "./interfaces/IWithdrawalQueue.sol";
import {IPricer} from "./interfaces/IPricer.sol";

contract HyperbeatAdapter is AdapterBase, IExternalPositionAdapter {
    using SafeERC20 for IERC20;
    using Asserts for address;

    struct WithdrawalQueue {
        uint256 start;
        uint256 end;
        mapping(uint256 index => IWithdrawalQueue.WithdrawalRequest) requests;
    }

    bytes4 public constant getAdapterId = bytes4(keccak256("HyperbeatAdapter"));

    event Hyperbeat__WithdrawalRequested(address indexed vault, uint256 hbUsdtAmount, uint256 minUsdtOut, uint64 deadline);
    event HyperbeatAdapter__ProcessedWithdrawalClaimed(address indexed vault, uint256 usdtAmount);
    event HyperbeatAdapter__RejectedWithdrawalClaimed(address indexed vault, uint256 hbUsdtAmount);
    event HyperbeatAdapter__WithdrawalCancelled(address indexed vault, uint256 hbUsdtAmount);
    event HyperbeatAdapter__RequestOrderSwapped(uint256 indexed x, uint256 indexed y);

    error NoAccess();
    error HyperbeatAdapter__WrongIndexes(uint256 x, uint256 y);
    error HyperbeatAdapter__NoWithdrawRequestInQueue();

    address private immutable i_hyperCrocVault;
    IERC20 private immutable i_usdt;
    IERC20 private immutable i_hbUSDT;
    IDepositor private immutable i_depositor;
    IWithdrawalQueue private immutable i_withdrawalQueue;

    WithdrawalQueue s_queue;

    uint256 public hbUSDTRequested;

    modifier onlyVault() {
        if (msg.sender != i_hyperCrocVault) revert NoAccess();
        _;
    }

    constructor(address hyperCrocVault, address usdt, address hbUSDT, address depositor, address withdrawalQueue) {
        hyperCrocVault.assertNotZeroAddress();
        usdt.assertNotZeroAddress();
        hbUSDT.assertNotZeroAddress();
        depositor.assertNotZeroAddress();
        withdrawalQueue.assertNotZeroAddress();

        i_hyperCrocVault = hyperCrocVault;
        i_usdt = IERC20(usdt);
        i_hbUSDT = IERC20(hbUSDT);
        i_depositor = IDepositor(depositor);
        i_withdrawalQueue = IWithdrawalQueue(withdrawalQueue);
    }

    /// @notice Deposit USDT to receive hbUSDT
    /// @param amount Amount of USDT to deposit
    /// @return hbUSDTAmount Amount of hbUSDT received
    function deposit(uint256 amount, bytes32 refCode) external onlyVault returns (uint256 hbUSDTAmount) {
        hbUSDTAmount = _deposit(i_usdt, amount, refCode);
    }

    /// @notice Deposit all USDT except the given amount
    /// @param except Amount to be left
    /// @return hbUSDTAmount Amount of hbUSDT received
    function depositAllExcept(uint256 except, bytes32 refCode)
        external
        onlyVault
        returns (uint256 hbUSDTAmount)
    {
        IERC20 usdt = i_usdt;
        uint256 amount = usdt.balanceOf(msg.sender) - except;
        hbUSDTAmount = _deposit(usdt, amount, refCode);
    }

    /// @notice Instantly withdraws hbUSDT token to USDT
    /// @dev Extra fees applied by Hyperbeat
    /// @param hbUSTAmount Amount of hbUSDT to withdraw
    /// @return withdrawn Amount of USDT redeemed
    function instantWithdraw(uint256 hbUSTAmount) external onlyVault returns (uint256 withdrawn) {
        return _instantWithdraw(i_hbUSDT, hbUSTAmount);
    }

    /// @notice Instantly withdraws hbUSDT token to USDT except given amount
    /// @dev Extra fees applied by Hyperbeat
    /// @param except Amount of hbUSDT to be left
    /// @return withdrawn Amount of USDT redeemed
    function instantWithdrawAllExcept(uint256 except) external onlyVault returns (uint256 withdrawn) {
        IERC20 hbUSDT = i_hbUSDT;
        uint256 amount = hbUSDT.balanceOf(msg.sender) - except;
        return _instantWithdraw(hbUSDT, amount);
    }

    function requestWithdrawal(uint256 amount, uint64 deadline) external onlyVault {
        _requestWithdrawal(i_hbUSDT, amount, deadline);
    }

    function requestWithdrawalAllExcept(uint256 except, uint64 deadline) external onlyVault {
        IERC20 hbUSDT = i_hbUSDT;
        uint256 amount = hbUSDT.balanceOf(msg.sender) - except;
        _requestWithdrawal(i_hbUSDT, amount, deadline);
    }

     function claimProcessedWithdrawal() external onlyVault {
        IWithdrawalQueue.WithdrawalRequest memory request = _dequeueWithdrawalRequest();

        hbUSDTRequested -= request.amount;

        uint256 usdtAmount = request.baseAssetAmount;
        i_usdt.safeTransfer(msg.sender, usdtAmount);

        emit HyperbeatAdapter__ProcessedWithdrawalClaimed(msg.sender, usdtAmount);
    }

    function claimRejectedWithdrawal() external onlyVault {
        IWithdrawalQueue.WithdrawalRequest memory request = _dequeueWithdrawalRequest();

        uint256 hbUsdtAmount = request.amount;
        hbUSDTRequested -= hbUsdtAmount;

        i_hbUSDT.safeTransfer(msg.sender, hbUsdtAmount);

        emit HyperbeatAdapter__RejectedWithdrawalClaimed(msg.sender, hbUsdtAmount);
    }

    function cancelWithdrawal() external onlyVault {
        IWithdrawalQueue.WithdrawalRequest memory request = _dequeueWithdrawalRequest();

        i_withdrawalQueue.cancelWithdrawalRequestAndClaimShares(request);

        uint256 hbUsdtAmount = request.amount;
        hbUSDTRequested -= hbUsdtAmount;

        i_hbUSDT.safeTransfer(msg.sender, hbUsdtAmount);

        emit HyperbeatAdapter__WithdrawalCancelled(msg.sender, hbUsdtAmount);
    }

    function swapRequestsOrder(uint256 x, uint256 y) external onlyVault {
        if (x == y) revert HyperbeatAdapter__WrongIndexes(x, y);

        WithdrawalQueue storage queue = s_queue;
        uint256 maxIndex = x > y ? x : y;

        if (maxIndex >= s_queue.end) revert HyperbeatAdapter__WrongIndexes(x, y);

        IWithdrawalQueue.WithdrawalRequest memory requestX = queue.requests[x];

        queue.requests[x] = queue.requests[y];
        queue.requests[y] = requestX;

        emit HyperbeatAdapter__RequestOrderSwapped(x, y);
    }

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IExternalPositionAdapter).interfaceId || super.supportsInterface(interfaceId);
    }

    function getManagedAssets() external view returns (address[] memory assets, uint256[] memory amounts) {
        return getManagedAssets(msg.sender);
    }

    /// @dev Returns non zero value when vault has pending withdrawal requests
    /// @param vault Address of the vault
    function getManagedAssets(address vault) public view returns (address[] memory assets, uint256[] memory amounts) {
        if (vault != i_hyperCrocVault) return (assets, amounts);
        
        uint256 _hbUSDTRequested = hbUSDTRequested;
        if (_hbUSDTRequested != 0) {
            assets = new address[](1);
            assets[0] = address(i_hbUSDT);

            amounts = new uint256[](1);
            amounts[0] = _hbUSDTRequested;
        }
    }

    function getDebtAssets() external view returns (address[] memory assets, uint256[] memory amounts) {}

    function getHyperCrocVault() external view returns (address) {
        return i_hyperCrocVault;
    }

    function getUSDT() external view returns (address) {
        return address(i_usdt);
    }

    function getHbUSDT() external view returns (address) {
        return address(i_hbUSDT);
    }

    function getHyperbeatDepositor() external view returns (address) {
        return address(i_depositor);
    }

    function getHyperbeatWithdrawalQueue() external view returns (address) {
        return address(i_withdrawalQueue);
    }

    function claimable(address vault) external view returns (address asset, uint256 claimableAmount) {
        if (vault != i_hyperCrocVault) return (address(0), 0);

        uint256 queueStart = s_queue.start;
        if (queueStart == s_queue.end) return (address(0), 0);

        IWithdrawalQueue.WithdrawalRequest storage request = s_queue.requests[queueStart];
        if (!_isActive(keccak256(abi.encode(request)))) {
            return (address(i_usdt), request.baseAssetAmount);
        }

    }

    function getRequest(uint256 index) external view returns (IWithdrawalQueue.WithdrawalRequest memory) {
        return s_queue.requests[index];
    }

    function getQueueStart() external view returns (uint256) {
        return s_queue.start;
    }

    function getQueueEnd() external view returns (uint256) {
        return s_queue.end;
    }

    function _deposit(IERC20 usdt, uint256 amount, bytes32 refCode)
        private
        returns (uint256 hbUSDTAmount)
    {
        IAdapterCallback(msg.sender).adapterCallback(address(this), address(usdt), amount);

        IDepositor depositor = i_depositor;
        usdt.forceApprove(address(depositor), amount);
        depositor.deposit(address(usdt), address(this), amount, refCode);

        hbUSDTAmount = _transferAll(i_hbUSDT);

        emit Swap(msg.sender, address(usdt), amount, address(i_hbUSDT), hbUSDTAmount);
    }

    function _instantWithdraw(IERC20 hbUSDT, uint256 hbUSDTAmount) private returns (uint256 withdrawn) {
        IAdapterCallback(msg.sender).adapterCallback(address(this), address(hbUSDT), hbUSDTAmount);
        
        IWithdrawalQueue withdrawalQueue = i_withdrawalQueue;
        hbUSDT.forceApprove(address(withdrawalQueue), hbUSDTAmount);

        withdrawalQueue.instantWithdraw(address(this), hbUSDTAmount);
        withdrawn = _transferAll(i_usdt);
    
        emit Swap(msg.sender, address(hbUSDT), hbUSDTAmount, address(i_usdt), withdrawn);
    }

    function _requestWithdrawal(IERC20 hbUSDT, uint256 hbUSDTAmount, uint64 deadline) private {
        IAdapterCallback(msg.sender).adapterCallback(address(this), address(hbUSDT), hbUSDTAmount);
        
        IWithdrawalQueue withdrawalQueue = i_withdrawalQueue;
        hbUSDT.forceApprove(address(withdrawalQueue), hbUSDTAmount);

        IPricer pricer = IPricer(withdrawalQueue.pricer());
        uint256 minAmountOut = pricer.getAssetAmount(address(i_usdt), hbUSDTAmount);

        IWithdrawalQueue.WithdrawalRequest memory request = 
            withdrawalQueue.createWithdrawalRequest(address(this), hbUSDTAmount, minAmountOut, deadline);

        _enqueueWithdrawalRequest(request);
        hbUSDTRequested += hbUSDTAmount;
    
        emit Hyperbeat__WithdrawalRequested(msg.sender, hbUSDTAmount, minAmountOut, deadline);
    }

    function _enqueueWithdrawalRequest(IWithdrawalQueue.WithdrawalRequest memory request) private {
        WithdrawalQueue storage queue = s_queue;
        unchecked {
            queue.requests[queue.end++] = request;
        }
    }

    function _dequeueWithdrawalRequest() private returns (IWithdrawalQueue.WithdrawalRequest memory) {
        WithdrawalQueue storage queue = s_queue;
        uint256 queueStart;
        unchecked {
            queueStart = queue.start++;
        }
        if (queueStart == queue.end) revert HyperbeatAdapter__NoWithdrawRequestInQueue();

        return queue.requests[queueStart];
    }

    /// @dev can consume lots of gas, avoid calling it in non-view methods
    function _isActive(bytes32 requestId) private view returns (bool) {
        bytes32[] memory activeWithdrawals = i_withdrawalQueue.getActiveWithdrawals();

        uint256 n = activeWithdrawals.length;

        for (uint256 i; i < n;) {
            if (activeWithdrawals[i] == requestId) return true;
            unchecked {
                ++i;
            }
        }

        return false;
    }

    function _transferAll(IERC20 token) private returns (uint256 transferAmount) {
        transferAmount = token.balanceOf(address(this));
        token.safeTransfer(msg.sender, transferAmount);
    }
}
