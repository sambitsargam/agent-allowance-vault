# Reference: Query (read operations)

Read-only chain queries with `cast`. No private key needed; only `--rpc-url $RPC`.

## ERC20 balance
```bash
cast call $TOKEN "balanceOf(address)(uint256)" $ADDRESS --rpc-url $RPC
```
Convert base units to human: `cast from-wei <value>` (18-decimal tokens).

## ERC20 metadata
```bash
cast call $TOKEN "decimals()(uint8)" --rpc-url $RPC
cast call $TOKEN "symbol()(string)" --rpc-url $RPC
```

## Native PHRS balance (for gas)
```bash
cast balance $ADDRESS --rpc-url $RPC          # wei
cast balance $ADDRESS --rpc-url $RPC --ether  # PHRS
```

## Transaction status / receipt
```bash
cast tx $TXHASH --rpc-url $RPC
cast receipt $TXHASH --rpc-url $RPC
cast receipt $TXHASH status --rpc-url $RPC     # 1 = success, 0 = reverted
```

## Generic contract read
```bash
cast call $CONTRACT "someView(uint256)(address)" 42 --rpc-url $RPC
```

## Decode a revert reason
```bash
cast 4byte-decode <0x-error-data>     # map a 4-byte selector to a known error
```

### Agent Guidelines
1. Always run read pre-flight checks before a state-changing tx (balance, allowance, decimals).
2. Report `status = 0` as a failed tx and fetch the revert reason.
3. Print the explorer link: `https://testnet.pharosscan.xyz/tx/$TXHASH`.
