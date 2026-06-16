# Reference: Contract (deploy & verify)

Generic deployment/verification with `forge`. For the vault-specific flow, see
[agent-allowance-vault.md](agent-allowance-vault.md).

## Deploy
```bash
forge create src/Path.sol:ContractName \
  --rpc-url $RPC --private-key $PRIVATE_KEY --broadcast \
  --constructor-args arg1 arg2
```
Capture the `Deployed to:` address.

## Deploy via script (repeatable, logged)
```bash
forge script script/DeployVault.s.sol:DeployVault \
  --rpc-url $RPC --private-key $PRIVATE_KEY --broadcast \
  --sig "run(address)" $TOKEN
```

## Verify on PharosScan (Blockscout)
```bash
sleep 10   # indexer delay
forge verify-contract $ADDRESS src/Path.sol:ContractName \
  --verifier blockscout \
  --verifier-url https://testnet.pharosscan.xyz/api \
  --compiler-version 0.8.24 \
  --constructor-args $(cast abi-encode "constructor(address)" $TOKEN)
```

## Encode constructor args
```bash
cast abi-encode "constructor(address)" $TOKEN
```

### Networks
Read `assets/networks.json`. Defaults:
- **Pharos Testnet** — chainId `688688`, RPC `https://testnet.dplabs-internal.com`,
  explorer `https://testnet.pharosscan.xyz`
- **Pharos Atlantic Testnet** — chainId `688689`, RPC `https://atlantic.dplabs-internal.com`,
  explorer `https://atlantic.pharosscan.xyz`

### Agent Guidelines
1. Always verify after deploy so users can read the source on the explorer.
2. The vault is a single self-contained file (no imports) → no `--libraries` or flattening needed.
3. Match `--compiler-version` to `foundry.toml` (`0.8.24`).
