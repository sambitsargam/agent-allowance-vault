# Reference: Transaction (write operations)

State-changing calls with `cast send`. **Foundry does not read env vars automatically** —
pass `--private-key $PRIVATE_KEY` and `--rpc-url $RPC` on every command.

## Anatomy of a write
```bash
cast send $CONTRACT "fn(type1,type2)" arg1 arg2 \
  --rpc-url $RPC --private-key $PRIVATE_KEY
```

## Amount conversion
```bash
cast to-wei 1.5 ether      # human -> base units (18 decimals)
cast from-wei 1500000000000000000   # base units -> human
```
For non-18-decimal tokens, scale manually by `10^decimals`.

## Gas controls (optional)
```bash
--gas-limit 300000
--gas-price $(cast gas-price --rpc-url $RPC)
--priority-gas-price 1gwei
```

## Native PHRS transfer
```bash
cast send $TO --value $(cast to-wei 0.1 ether) \
  --rpc-url $RPC --private-key $PRIVATE_KEY
```

## Simulate before sending (dry run)
```bash
cast call $CONTRACT "fn(type)" arg --rpc-url $RPC --from $OWNER
```
If the simulation reverts, the real tx will too — surface the error instead of broadcasting.

### Agent Guidelines
1. **Simulate with `cast call` first** for anything risky; only `cast send` after it passes.
2. Never hardcode or log the private key. Read it from `$PRIVATE_KEY` only.
3. After sending, fetch the receipt, check `status`, and print the explorer link.
4. Confirm recipient + human amount with the user before broadcasting value transfers.
