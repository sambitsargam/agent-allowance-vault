# Reference: Agent Allowance Vault

Machine-readable command templates for every operation. All commands assume:

```bash
export PRIVATE_KEY=0xYOUR_KEY
export RPC=https://atlantic.dplabs-internal.com     # Pharos Atlantic, chainId 688689 (reachable)
# (Default testnet is testnet.dplabs-internal.com / 688688; Atlantic is the live fallback.)
export OWNER=$(cast wallet address --private-key $PRIVATE_KEY)
```

**Asset model:** the vault custodies ONE asset, fixed at deploy time:
- **`asset == address(0)` → native PHRS** (the chain's gas token). *This is the default and
  the recommended mode* — it uses the real testnet asset with no token to deploy.
- `asset == <ERC20 address>` → that ERC20 token.

Conventions:
- `$VAULT` = deployed AgentAllowanceVault address
- `$AGENT` = address granted spending power
- `$TOKEN` = ERC20 token address (only for ERC20 vaults)
- Amounts are in **base units** (wei). For native PHRS and 18-decimal tokens, convert human
  amounts with `cast to-wei <amount> ether`. Always confirm token decimals for ERC20.

---

## 0. (ERC20 vaults only) Deploy a test token (MockPROS)

> **Skip this for a native-PHRS vault.** Only needed if you want an ERC20-custody vault and
> have no real ERC20 to use.

### Overview
For testing an ERC20 vault, deploy `MockPROS` — a faucet ERC20 anyone can `drip()`.

### Command Template
```bash
# Deploy
forge create src/MockPROS.sol:MockPROS \
  --rpc-url $RPC --private-key $PRIVATE_KEY --broadcast

# Save the "Deployed to:" address
export TOKEN=<deployed_address>

# Mint yourself 10,000 mPROS
cast send $TOKEN "drip()" --rpc-url $RPC --private-key $PRIVATE_KEY
```

### Output Parsing
| Field | Description |
|-------|-------------|
| `Deployed to` | The token address → set as `$TOKEN` |
| `Transaction hash` | Deployment tx → explorer link |

### Agent Guidelines
1. Only do this on a testnet (chainId 688688 or 688689).
2. After `drip()`, confirm with `cast call $TOKEN "balanceOf(address)(uint256)" $OWNER`.

---

## 1. Deploy the vault

### Overview
Deploys one `AgentAllowanceVault` bound to a single asset. The deployer becomes the `owner`.
Pass `address(0)` to custody **native PHRS** (recommended), or an ERC20 address.

### Command Template
```bash
# Native PHRS vault (recommended — uses the real testnet asset)
forge create src/AgentAllowanceVault.sol:AgentAllowanceVault \
  --rpc-url $RPC --private-key $PRIVATE_KEY --broadcast \
  --constructor-args 0x0000000000000000000000000000000000000000

# …or an ERC20 vault
forge create src/AgentAllowanceVault.sol:AgentAllowanceVault \
  --rpc-url $RPC --private-key $PRIVATE_KEY --broadcast \
  --constructor-args $TOKEN

export VAULT=<deployed_address>
```

### Parameters
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `asset` | address | yes | `address(0)` for native PHRS, or an ERC20 token address. |

### Output Parsing
| Field | Description |
|-------|-------------|
| `Deployed to` | Vault address → set as `$VAULT` |
| `Transaction hash` | Explorer link |

### Agent Guidelines
1. Default to a **native PHRS** vault (`address(0)`) unless the user names an ERC20.
2. After deploy, verify `cast call $VAULT "owner()(address)"` equals `$OWNER` and check
   `cast call $VAULT "isNative()(bool)"`.
3. Proceed to verify the contract (section 15) so users can read it on the explorer.

---

## 2. Fund the vault

### Overview
Move funds into the vault. **Native PHRS** is a single `depositNative` call; **ERC20**
needs `approve` then `deposit`.

### Command Template
```bash
# Native PHRS vault — send PHRS as value
cast send $VAULT "depositNative()" --value $(cast to-wei 1 ether) \
  --rpc-url $RPC --private-key $PRIVATE_KEY
# (a plain `cast send $VAULT --value …` also works via receive())

# ERC20 vault — approve then deposit
cast send $TOKEN "approve(address,uint256)" $VAULT $(cast to-wei 1000 ether) \
  --rpc-url $RPC --private-key $PRIVATE_KEY
cast send $VAULT "deposit(uint256)" $(cast to-wei 1000 ether) \
  --rpc-url $RPC --private-key $PRIVATE_KEY
```

### Parameters
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `msg.value` (native) | uint256 | yes (native) | PHRS sent with `depositNative`. Must be > 0. |
| amount (ERC20) | uint256 | yes (ERC20) | Base-unit amount to deposit. Must be > 0. |

### Error Handling
| Error | Cause | Suggested Action |
|-------|-------|------------------|
| `ZeroAmount()` | value/amount == 0 | Pass a positive amount |
| `NotNativeVault()` | called `depositNative` on an ERC20 vault | Use `deposit(amount)` instead |
| `NotERC20Vault()` | called `deposit` on a native vault | Use `depositNative()` instead |
| `SafeERC20FailedOperation(address)` | ERC20 approval missing/insufficient, or token not a contract | Run the `approve` step first; check `$TOKEN` |

### Agent Guidelines
1. Pick the funding path based on `isNative()`.
2. Anyone may fund, but typically the owner does.
3. Confirm new balance with section 13.

---

## 3. Grant an agent an allowance

### Overview
Owner authorizes an agent to spend up to `cap` per rolling `period`, with an optional
`maxPerTx` and `expiry`. Re-granting overwrites the previous allowance and resets the
period.

### Command Template
```bash
# Example: 100 tokens/day cap, 40 max per tx, 1-day period, no expiry
cast send $VAULT \
  "grantAllowance(address,uint256,uint256,uint256,uint64)" \
  $AGENT \
  $(cast to-wei 100 ether) \
  $(cast to-wei 40 ether) \
  86400 \
  0 \
  --rpc-url $RPC --private-key $PRIVATE_KEY
```

### Parameters
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| agent | address | yes | Address that may spend. Non-zero. |
| cap | uint256 | yes | Max total spend per period (base units). `0` = agent can only use the approval queue. |
| maxPerTx | uint256 | yes | Max per single `pay`. `0` = no per-tx limit (still bounded by cap). |
| period | uint256 | yes | Period length in **seconds**. Must be > 0 (e.g. 86400 = 1 day, 3600 = 1 hour). |
| expiry | uint64 | yes | Unix timestamp after which the allowance is invalid. `0` = never expires. |

### Output Parsing
Emits `AllowanceGranted(agent, cap, maxPerTx, period, expiry)`.

### Error Handling
| Error | Cause | Suggested Action |
|-------|-------|------------------|
| `NotOwner()` | Caller isn't the owner | Use the owner key |
| `ZeroAddress()` | agent == 0 | Pass a real agent address |
| `InvalidPeriod()` | period == 0 | Pass a positive period (seconds) |

### Agent Guidelines
1. Translate human phrasing to seconds: "per day" → 86400, "per hour" → 3600,
   "per week" → 604800.
2. Convert human token amounts to base units with `cast to-wei`.
3. For an expiry like "for 30 days", compute `expiry = now + 2592000`:
   `EXP=$(( $(date +%s) + 2592000 ))`.
4. Echo back the human-readable policy for confirmation before sending.

---

## 4. Agent makes a payment

### Overview
The **agent** (not the owner) sends `amount` to `recipient` from the vault, within budget.

### Command Template
```bash
# Run with the AGENT's private key
cast send $VAULT "pay(address,uint256)" $RECIPIENT $(cast to-wei 25 ether) \
  --rpc-url $RPC --private-key $AGENT_PRIVATE_KEY
```

### Parameters
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| recipient | address | yes | Payout destination. Non-zero. |
| amount | uint256 | yes | Base-unit amount. Must be > 0, ≤ maxPerTx, ≤ remaining budget, ≤ vault balance. |

### Output Parsing
Emits `Paid(agent, recipient, amount, remaining)`. The return value `remaining` is the
budget left this period. Read it from the `Paid` log or re-query section 12.

### Error Handling
| Error | Cause | Suggested Action |
|-------|-------|------------------|
| `NotAuthorizedAgent()` | No active allowance for caller | Owner must `grantAllowance` first |
| `AllowanceExpired()` | Past `expiry` | Owner re-grants with a new expiry |
| `PerTxLimitExceeded(amount, maxPerTx)` | amount > maxPerTx | Split into smaller payments or use section 5 |
| `BudgetExceeded(amount, remaining)` | amount > remaining this period | Wait for period reset, or use section 5 (approval) |
| `InsufficientVaultBalance(amount, balance)` | Vault underfunded | Owner funds the vault (section 2) |
| `ContractPaused()` | Vault paused | Owner unpauses (section 9) |
| `NativeTransferFailed(to, amount)` | recipient rejected native PHRS (e.g. a contract with no `receive`) | Use a recipient that can accept native, or an ERC20 vault |
| `ZeroAddress()` / `ZeroAmount()` | bad args | Fix recipient/amount |

### Agent Guidelines
1. **Pre-flight:** read `remainingAllowance($AGENT)` (section 12) and `vaultBalance`
   (section 13). If `amount` exceeds either, do not broadcast — explain and offer the
   approval path (section 5).
2. Confirm recipient + human amount with the user before sending.
3. The budget auto-resets when a period elapses; you do not need to reset it manually.

---

## 5. Request an over-budget payment

### Overview
When a payment exceeds the agent's budget or per-tx limit, the agent **queues** it for
owner approval instead of failing. No funds move yet.

### Command Template
```bash
# Run with the AGENT's key
cast send $VAULT "requestPayment(address,uint256)" $RECIPIENT $(cast to-wei 250 ether) \
  --rpc-url $RPC --private-key $AGENT_PRIVATE_KEY
```

### Output Parsing
Emits `PaymentRequested(id, agent, recipient, amount)`. Capture the **`id`** (a uint256,
starting at 0 and incrementing). Read it from the log topics or:
```bash
cast logs --rpc-url $RPC --address $VAULT \
  "PaymentRequested(uint256,address,address,uint256)" --from-block latest
```

### Error Handling
| Error | Cause | Suggested Action |
|-------|-------|------------------|
| `NotAuthorizedAgent()` / `AllowanceExpired()` | Caller isn't an active agent | Owner grants/renews allowance |
| `ContractPaused()` | Vault paused | Owner unpauses |
| `ZeroAddress()` / `ZeroAmount()` | bad args | Fix recipient/amount |

### Agent Guidelines
1. Tell the user the request id and that it now needs **owner approval** (section 6).
2. Do not assume it will be approved.

---

## 6. Owner approves a pending payment

### Overview
Owner settles a queued payment. This is the explicit override of the agent's budget, so
it is **owner-only**. Still respects pause and vault balance.

### Command Template
```bash
cast send $VAULT "approvePayment(uint256)" $ID \
  --rpc-url $RPC --private-key $PRIVATE_KEY
```

### Parameters
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| id | uint256 | yes | The payment id from `PaymentRequested` |

### Output Parsing
Emits `PaymentApproved(id, recipient, amount)`. Funds transfer to recipient.

### Error Handling
| Error | Cause | Suggested Action |
|-------|-------|------------------|
| `NotOwner()` | Not the owner | Use owner key |
| `PaymentNotFound()` | Unknown id (recipient is zero) | Check the id |
| `PaymentAlreadySettled()` | Already executed or cancelled | Nothing to do |
| `InsufficientVaultBalance(amount, balance)` | Underfunded | Fund the vault first |
| `ContractPaused()` | Paused | Unpause first |

### Agent Guidelines
1. Before approving, show the owner the pending payment details (section 14 analog:
   `getPendingPayment(id)`).
2. Confirm explicitly — this bypasses the budget cap on purpose.

---

## 7. Cancel a pending payment

### Overview
Cancel a queued payment. Callable by the requesting **agent** or the **owner**.

### Command Template
```bash
cast send $VAULT "cancelPayment(uint256)" $ID \
  --rpc-url $RPC --private-key $PRIVATE_KEY   # owner OR requesting agent key
```

### Error Handling
| Error | Cause | Suggested Action |
|-------|-------|------------------|
| `PaymentNotFound()` | Unknown id | Check the id |
| `PaymentAlreadySettled()` | Already executed/cancelled | Nothing to do |
| `NotRequesterOrOwner()` | Caller is neither owner nor the requesting agent | Use the right key |

---

## 8. Revoke an agent

### Overview
Immediately disables an agent's spending. Idempotent.

### Command Template
```bash
cast send $VAULT "revokeAllowance(address)" $AGENT \
  --rpc-url $RPC --private-key $PRIVATE_KEY
```

### Error Handling
| Error | Cause | Suggested Action |
|-------|-------|------------------|
| `NotOwner()` | Not the owner | Use owner key |

### Agent Guidelines
After revoke, any `pay` by that agent reverts with `NotAuthorizedAgent`. Pending requests
can still be cancelled but not approved-then-spent beyond balance.

---

## 9. Pause / unpause

### Overview
Emergency stop: blocks all `pay`, `requestPayment`, and `approvePayment`.

### Command Template
```bash
cast send $VAULT "setPaused(bool)" true  --rpc-url $RPC --private-key $PRIVATE_KEY
cast send $VAULT "setPaused(bool)" false --rpc-url $RPC --private-key $PRIVATE_KEY
```

### Error Handling
| Error | Cause | Suggested Action |
|-------|-------|------------------|
| `NotOwner()` | Not the owner | Use owner key |

---

## 10. Withdraw funds (owner)

### Overview
Owner pulls tokens out of the vault.

### Command Template
```bash
cast send $VAULT "withdraw(address,uint256)" $TO $(cast to-wei 50 ether) \
  --rpc-url $RPC --private-key $PRIVATE_KEY
```

### Error Handling
| Error | Cause | Suggested Action |
|-------|-------|------------------|
| `NotOwner()` | Not the owner | Use owner key |
| `ZeroAddress()` / `ZeroAmount()` | bad args | Fix args |
| `InsufficientVaultBalance(amount, balance)` | More than held | Withdraw ≤ balance |

---

## 11. Transfer ownership (two-step)

### Overview
Safe two-step handover: current owner nominates, new owner accepts. Prevents sending
ownership to a wrong/dead address.

### Command Template
```bash
# Step 1 (current owner)
cast send $VAULT "transferOwnership(address)" $NEW_OWNER \
  --rpc-url $RPC --private-key $PRIVATE_KEY

# Step 2 (NEW owner's key)
cast send $VAULT "acceptOwnership()" \
  --rpc-url $RPC --private-key $NEW_OWNER_PRIVATE_KEY
```

### Error Handling
| Error | Cause | Suggested Action |
|-------|-------|------------------|
| `NotOwner()` | Step 1 not by owner, or step 2 not by the pending owner | Use the correct key |

---

## 12. Read an agent's remaining budget

### Overview
How much the agent can still spend this period (accounts for period reset, view-only).

### Command Template
```bash
cast call $VAULT "remainingAllowance(address)(uint256)" $AGENT --rpc-url $RPC
```

### Output Parsing
Returns a uint256 in base units. Convert: `cast from-wei <value>` for an 18-decimal token.
`0` means revoked, expired, or fully spent.

---

## 13. Read the vault balance

### Command Template
```bash
cast call $VAULT "vaultBalance()(uint256)" --rpc-url $RPC
```
Returns the vault's token balance (base units).

---

## 14. Inspect an allowance record

### Command Template
```bash
cast call $VAULT "getAllowance(address)((uint256,uint256,uint256,uint256,uint256,uint64,bool))" $AGENT --rpc-url $RPC
```

### Output Parsing
Tuple order: `(cap, maxPerTx, period, spent, periodStart, expiry, active)`.

Inspect a pending payment:
```bash
cast call $VAULT "getPendingPayment(uint256)((address,address,uint256,uint64,bool,bool))" $ID --rpc-url $RPC
# tuple: (agent, recipient, amount, createdAt, executed, cancelled)
```

---

## 15. Verify on PharosScan

### Overview
Publish source so users can read/interact on the Blockscout explorer. The vault is a
single self-contained file (no external imports) → verification is trivial.

### Command Template
```bash
sleep 10   # allow the indexer to catch up after deploy

forge verify-contract $VAULT \
  src/AgentAllowanceVault.sol:AgentAllowanceVault \
  --verifier blockscout \
  --verifier-url https://atlantic.pharosscan.xyz/api \
  --constructor-args $(cast abi-encode "constructor(address)" $ASSET) \
  --compiler-version 0.8.24
# $ASSET = 0x0000000000000000000000000000000000000000 for a native vault, else the ERC20 address.
```

> Note: PharosScan's verify API may sit behind a bot-protection checkpoint. If the CLI
> call is rejected, verify manually in the explorer web UI using
> `verification/standard-json-input.json` (compiler 0.8.24, optimizer 200, EVM paris).

### Agent Guidelines
1. Always `sleep 10` first (indexer delay).
2. Confirm the green "Verified" checkmark, then share
   `https://testnet.pharosscan.xyz/address/$VAULT`.

---

## 16. Query events

### Overview
Reconstruct payment history from logs.

### Command Template
```bash
# All payments executed within budget
cast logs --rpc-url $RPC --address $VAULT \
  "Paid(address,address,uint256,uint256)" --from-block 0

# All over-budget requests
cast logs --rpc-url $RPC --address $VAULT \
  "PaymentRequested(uint256,address,address,uint256)" --from-block 0

# Approvals
cast logs --rpc-url $RPC --address $VAULT \
  "PaymentApproved(uint256,address,uint256)" --from-block 0
```

### Full event reference
| Event | Signature | Topics / data |
|-------|-----------|---------------|
| `Deposited` | `Deposited(address,uint256)` | indexed from, amount |
| `Withdrawn` | `Withdrawn(address,uint256)` | indexed to, amount |
| `AllowanceGranted` | `AllowanceGranted(address,uint256,uint256,uint256,uint64)` | indexed agent, cap, maxPerTx, period, expiry |
| `AllowanceRevoked` | `AllowanceRevoked(address)` | indexed agent |
| `Paid` | `Paid(address,address,uint256,uint256)` | indexed agent, indexed recipient, amount, remaining |
| `PaymentRequested` | `PaymentRequested(uint256,address,address,uint256)` | indexed id, indexed agent, indexed recipient, amount |
| `PaymentApproved` | `PaymentApproved(uint256,address,uint256)` | indexed id, indexed recipient, amount |
| `PaymentCancelled` | `PaymentCancelled(uint256)` | indexed id |
| `Paused` | `Paused(bool)` | paused |
| `OwnershipTransferStarted` | `OwnershipTransferStarted(address,address)` | indexed previousOwner, indexed newOwner |
| `OwnershipTransferred` | `OwnershipTransferred(address,address)` | indexed previousOwner, indexed newOwner |

Query any of them by passing the signature to `cast logs`, e.g.:
```bash
cast logs --rpc-url $RPC --address $VAULT "AllowanceRevoked(address)" --from-block 0
```

### Agent Guidelines
Use `--from-block` near the deploy block for speed on a busy chain.
