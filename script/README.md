# Deploy

## Dry-run mode

Remove `--broadcast` and `--etherscan-api-key` options from script for run a deploy scripts in dry-run mode

If you want to run multiple scripts in dry-run mode run anvil fork an use `http://localhost:8545` as rpc-url in scripts. Set --gas-price option for reasonable value

```sh
anvil --rpc-url $ETH_RPC_URL --gas-price 1000000000
```

If you deploy in dry-run mode ensure `script/deployment/<chainid>/dry-run` directory exists

## Prerequisites

1. Fill `.env` file with correct values
2. Create dry-run directory `script/deployment/<chainid>/dry-run`
3. Run `source .env`

## Deployment steps

1. Deploy EulerOracle and save value to ChainValues

```sh
forge script script/DeployEulerOracle.s.sol:DeployEulerOracle -vvvv --account testDeployer --rpc-url $ETH_RPC_URL
--broadcast --verify --delay 7 --retries 15 --verifier etherscan --etherscan-api-key $ETHERSCAN_KEY --verifier-url https://api.etherscan.io/api
```

2. Deploy HyperCrocVault factory and save value to ChainValues

```sh
forge script script/DeployHyperCrocVaultFactory.s.sol:DeployHyperCrocVaultFactory -vvvv --account deployer --rpc-url $ETH_RPC_URL --broadcast --etherscan-api-key $ETHERSCAN_KEY --verify --delay 7 --retries 15
```

3. Before deploying a vault ensure addresses for HyperCrocVaultFactory, EulerOracle, FeeCollector and VaultManager are set in ChainValues

4. Ensure EulerOracle prices are set up for all tokens. For deploy and set up prices use `https://github.com/hyperCrocfi/euler-price-oracle` repo

5. Prepare DeployVault script for concrete vault with implemented getDeployConfig function and run deploy

```sh
forge script script/vault/DeployUSDCVaultExample.s.sol:DeployUSDCVaultExample -vvvv  --account deployer --rpc-url $ETH_RPC_URL --broadcast --etherscan-api-key $ETHERSCAN_KEY --verify --delay 7 --retries 15
```

6. Additionally you can deploy adapters and connect it to a vault

```sh
forge script script/DeployAdapter.s.sol:DeployAdapter -vvvv --account deployer --rpc-url $ETH_RPC_URL --broadcast --etherscan-api-key $ETHERSCAN_KEY --verify --delay 7 --retries 15
```
