// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";
import {IExternalPositionAdapter} from "../../interfaces/IExternalPositionAdapter.sol";
import {Asserts} from "../../libraries/Asserts.sol";
import {AdapterBase} from "../AdapterBase.sol";
import {ILayerZeroTellerWithRateLimiting} from "./interfaces/ILayerZeroTellerWithRateLimiting.sol";
import {IAtomicQueue} from "./interfaces/IAtomicQueue.sol";

contract EtherfiBTCAdapter is AdapterBase, IExternalPositionAdapter {
    using SafeERC20 for IERC20;
    using Asserts for address;

    bytes4 public constant getAdapterId = bytes4(keccak256("EtherfiBTCAdapter"));

    event EtherfiBTCRequestWithdraw(
        address indexed vault,
        address indexed from,
        address indexed to,
        uint96 amount,
        uint88 atomicPrice,
        uint64 deadline
    );
    event EtherfiBTCRequestClaimed(address indexed vault, uint256 wbtcClaimed);
    event EtherfiBTCRequestCancel(address indexed vault, uint256 ebtcReturned);

    error NoAccess();

    address public immutable hyperCrocVault;
    IERC20 public immutable wBTC;
    IERC20 public immutable eBTC;
    ILayerZeroTellerWithRateLimiting public immutable teller;
    IAtomicQueue public immutable atomicQueue;

    modifier onlyVault() {
        if (msg.sender != hyperCrocVault) revert NoAccess();
        _;
    }

    constructor(address _hyperCrocVault, address _wBTC, address _eBTC, address _teller, address _atomicQueue) {
        _hyperCrocVault.assertNotZeroAddress();
        _wBTC.assertNotZeroAddress();
        _eBTC.assertNotZeroAddress();
        _teller.assertNotZeroAddress();
        _atomicQueue.assertNotZeroAddress();

        hyperCrocVault = _hyperCrocVault;
        wBTC = IERC20(_wBTC);
        eBTC = IERC20(_eBTC);
        teller = ILayerZeroTellerWithRateLimiting(_teller);
        atomicQueue = IAtomicQueue(_atomicQueue);
    }

    function deposit(uint256 amount, uint256 minShare) external onlyVault returns (uint256 shares) {
        shares = _deposit(wBTC, amount, minShare);
    }

    function depositAllExcept(uint256 except, uint256 minShare) external onlyVault returns (uint256 shares) {
        IERC20 _wBTC = wBTC;
        uint256 amount = _wBTC.balanceOf(msg.sender) - except;
        return _deposit(_wBTC, amount, minShare);
    }

    function requestWithdraw(uint96 amount, uint88 atomicPrice, uint64 deadline) external onlyVault {
        _requestWithdraw(eBTC, amount, atomicPrice, deadline);
    }

    function requestWithdrawAllExcept(uint96 except, uint88 atomicPrice, uint64 deadline) external onlyVault {
        IERC20 _eBTC = eBTC;
        uint96 amount = uint96(_eBTC.balanceOf(msg.sender) - except);
        return _requestWithdraw(_eBTC, amount, atomicPrice, deadline);
    }

    function claimWithdraw() external onlyVault returns (uint256 wbtcClaimed) {
        IERC20 _wBTC = wBTC;
        wbtcClaimed = _wBTC.balanceOf(address(this));
        _wBTC.safeTransfer(msg.sender, wbtcClaimed);

        emit EtherfiBTCRequestClaimed(msg.sender, wbtcClaimed);
    }

    function cancelWithdrawRequest() external onlyVault returns (uint256 ebtcReturned) {
        IERC20 _eBTC = eBTC;
        IAtomicQueue _atomicQueue = atomicQueue;

        IAtomicQueue.AtomicRequest memory defaultRequest;

        _atomicQueue.updateAtomicRequest(_eBTC, wBTC, defaultRequest);
        _eBTC.forceApprove(address(_atomicQueue), 0);

        ebtcReturned = _eBTC.balanceOf(address(this));
        eBTC.safeTransfer(msg.sender, ebtcReturned);

        emit EtherfiBTCRequestCancel(msg.sender, ebtcReturned);
    }

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IExternalPositionAdapter).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IExternalPositionAdapter
    function getManagedAssets() external view returns (address[] memory assets, uint256[] memory amounts) {
        return _getManagedAssets(msg.sender);
    }

    function getManagedAssets(address vault)
        external
        view
        returns (address[] memory assets, uint256[] memory amounts)
    {
        return _getManagedAssets(vault);
    }

    /// @inheritdoc IExternalPositionAdapter
    /// @dev there is no debt assets
    function getDebtAssets() external view returns (address[] memory assets, uint256[] memory amounts) {}

    function _getManagedAssets(address vault)
        private
        view
        returns (address[] memory assets, uint256[] memory amounts)
    {
        IERC20 _wBTC = wBTC;
        IERC20 _eBTC = eBTC;

        assets = new address[](2);
        assets[0] = address(_wBTC);
        assets[1] = address(_eBTC);

        amounts = new uint256[](2);
        if (vault == hyperCrocVault) {
            amounts[0] = _wBTC.balanceOf(address(this));
            amounts[1] = _eBTC.balanceOf(address(this));
        }
    }

    function _deposit(IERC20 _wBTC, uint256 amount, uint256 minShare) private returns (uint256 shares) {
        IERC20 _eBTC = eBTC;

        IAdapterCallback(msg.sender).adapterCallback(address(this), address(_wBTC), amount);
        _wBTC.forceApprove(address(_eBTC), amount);

        shares = teller.deposit(_wBTC, amount, minShare);
        _eBTC.safeTransfer(msg.sender, shares);

        emit Swap(msg.sender, address(_wBTC), amount, address(_eBTC), shares);
    }

    function _requestWithdraw(IERC20 _eBTC, uint96 amount, uint88 atomicPrice, uint64 deadline) private onlyVault {
        IERC20 _wBTC = wBTC;
        IAtomicQueue _atomicQueue = atomicQueue;

        IAtomicQueue.AtomicRequest memory currentRequest =
            _atomicQueue.getUserAtomicRequest(address(this), _eBTC, _wBTC);
        currentRequest.offerAmount = amount;
        currentRequest.deadline = deadline;
        currentRequest.atomicPrice = atomicPrice;

        _atomicQueue.updateAtomicRequest(_eBTC, _wBTC, currentRequest);

        IAdapterCallback(msg.sender).adapterCallback(address(this), address(_eBTC), amount);
        _eBTC.forceApprove(address(_atomicQueue), amount);

        emit EtherfiBTCRequestWithdraw(msg.sender, address(_eBTC), address(_wBTC), amount, atomicPrice, deadline);
    }
}
