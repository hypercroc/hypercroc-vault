// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "lib/forge-std/src/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {HyperCrocVaultFactory} from "../contracts/HyperCrocVaultFactory.sol";
import {HyperCrocVault} from "../contracts/HyperCrocVault.sol";
import {WithdrawalQueue} from "../contracts/WithdrawalQueue.sol";
import {MintableERC20} from "./mocks/MintableERC20.t.sol";
import {AdapterMock} from "./mocks/AdapterMock.t.sol";
import {EulerRouterMock} from "./mocks/EulerRouterMock.t.sol";
import {ExternalPositionAdapterMock} from "./mocks/ExternalPositionAdapterMock.t.sol";

contract TestSetUp is Test {
    using Math for uint256;

    string internal constant LP_NAME = "lpName";
    string internal constant LP_SYMBOL = "lpSymbol";

    string internal constant WITHDRAWAL_QUEUE_NAME = "withdrawalQueueName";
    string internal constant WITHDRAWAL_QUEUE_SYMBOL = "withdrawalQueueSymbol";

    address internal constant NO_ACCESS = address(0xDEAD);
    address internal constant VAULT_MANAGER = address(0x123456789);
    address internal constant FINALIZER = address(0x1234567890);
    address internal constant FEE_COLLECTOR = address(0xFEE);
    address internal constant USER = address(0x987654321);

    HyperCrocVaultFactory internal hyperCrocVaultFactoryImplementation;
    ERC1967Proxy internal hyperCrocVaultFactoryProxy;
    HyperCrocVaultFactory internal hyperCrocVaultFactory;

    HyperCrocVault internal hyperCrocVaultImplementation;
    HyperCrocVault internal hyperCrocVault;

    WithdrawalQueue internal withdrawalQueueImplementation;
    WithdrawalQueue internal withdrawalQueue;

    MintableERC20 internal asset;
    MintableERC20 internal trackedAsset;
    MintableERC20 internal externalPositionManagedAsset;
    MintableERC20 internal externalPositionDebtAsset;

    AdapterMock internal adapter;
    ExternalPositionAdapterMock internal externalPositionAdapter;
    EulerRouterMock internal oracle;

    function setUp() public virtual {
        _createOracleMock();
        _createAssets();
        _createAdapterMocks();
        _createHyperCrocVaultFactory();
        _deployHyperCrocVault();
    }

    function testInitialize() public view {
        assert(hyperCrocVaultFactory.isHyperCrocVault(address(hyperCrocVault)));

        UpgradeableBeacon vaultBeacon = UpgradeableBeacon(hyperCrocVaultFactory.vaultBeacon());
        assertEq(vaultBeacon.implementation(), address(hyperCrocVaultImplementation));
        assertEq(vaultBeacon.owner(), address(this));

        UpgradeableBeacon withdrawalQueueBeacon = UpgradeableBeacon(hyperCrocVaultFactory.withdrawalQueueBeacon());
        assertEq(withdrawalQueueBeacon.implementation(), address(withdrawalQueueImplementation));
        assertEq(withdrawalQueueBeacon.owner(), address(this));

        assertEq(address(hyperCrocVault.asset()), address(asset));
        assertEq(hyperCrocVault.owner(), address(this));
        assertEq(hyperCrocVault.name(), LP_NAME);
        assertEq(hyperCrocVault.symbol(), LP_SYMBOL);
        assertEq(hyperCrocVault.getFeeCollectorStorage().feeCollector, FEE_COLLECTOR);
        assertEq(hyperCrocVault.getFeeCollectorStorage().highWaterMarkPerShare, 10 ** hyperCrocVault.decimals());
        assertEq(address(hyperCrocVault.oracle()), address(oracle));
        assertEq(hyperCrocVault.withdrawalQueue(), address(withdrawalQueue));
        assertEq(hyperCrocVault.owner(), address(this));
        assert(hyperCrocVault.isVaultManager(VAULT_MANAGER));

        assertEq(address(withdrawalQueue.hyperCrocVault()), address(hyperCrocVault));
        assertEq(withdrawalQueue.owner(), address(this));
        assert(withdrawalQueue.isFinalizer(FINALIZER));
        assertEq(withdrawalQueue.name(), WITHDRAWAL_QUEUE_NAME);
        assertEq(withdrawalQueue.symbol(), WITHDRAWAL_QUEUE_SYMBOL);
    }

    function _createHyperCrocVaultFactory() private {
        hyperCrocVaultImplementation = new HyperCrocVault();
        withdrawalQueueImplementation = new WithdrawalQueue();

        hyperCrocVaultFactoryImplementation = new HyperCrocVaultFactory();
        bytes memory data = abi.encodeWithSelector(
            HyperCrocVaultFactory.initialize.selector,
            address(hyperCrocVaultImplementation),
            address(withdrawalQueueImplementation)
        );
        hyperCrocVaultFactoryProxy = new ERC1967Proxy(address(hyperCrocVaultFactoryImplementation), data);
        hyperCrocVaultFactory = HyperCrocVaultFactory(address(hyperCrocVaultFactoryProxy));
    }

    function _deployHyperCrocVault() private {
        (address vault, address queue) = hyperCrocVaultFactory.deployVault(
            address(asset),
            LP_NAME,
            LP_SYMBOL,
            WITHDRAWAL_QUEUE_NAME,
            WITHDRAWAL_QUEUE_SYMBOL,
            FEE_COLLECTOR,
            address(oracle)
        );

        hyperCrocVault = HyperCrocVault(vault);
        withdrawalQueue = WithdrawalQueue(queue);

        hyperCrocVault.addVaultManager(VAULT_MANAGER, true);
        withdrawalQueue.addFinalizer(FINALIZER, true);

        hyperCrocVault.setMaxExternalPositionAdapters(type(uint8).max);
        hyperCrocVault.setMaxTrackedAssets(type(uint8).max);
    }

    function _createOracleMock() private {
        oracle = new EulerRouterMock();
    }

    function _createAssets() private {
        asset = new MintableERC20("USDTest", "USDTest", 6);

        trackedAsset = new MintableERC20("ETHest", "ETHest", 18);
        oracle.setPrice(oracle.ONE().mulDiv(2000, 10 ** 12), address(trackedAsset), address(asset));

        externalPositionManagedAsset = new MintableERC20("aUSDTest", "aUSDTest", 6);
        oracle.setPrice(oracle.ONE(), address(externalPositionManagedAsset), address(asset));

        externalPositionDebtAsset = new MintableERC20("variableDebtUSDTest", "variableDebtUSDTest", 6);
        oracle.setPrice(oracle.ONE(), address(externalPositionDebtAsset), address(asset));
    }

    function _createAdapterMocks() private {
        adapter = new AdapterMock();
        externalPositionAdapter =
            new ExternalPositionAdapterMock(address(externalPositionManagedAsset), address(externalPositionDebtAsset));
    }
}
