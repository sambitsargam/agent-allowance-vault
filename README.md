# Agent Allowance Vault

**Agent Allowance Vault** lets you give an AI agent a **spending allowance instead of your
private key**. You fund a vault (native PHRS or any ERC20), grant an agent an on-chain budget,
and the agent pays from the vault on your behalf — but never beyond the limits you set. Spend
above the budget is queued for your one-click approval. The guardrails are enforced by the
contract, not by the agent's prompt.

## What you can do

- **Fund a vault** with native PHRS or any ERC20 for an agent to spend from.
- **Grant an agent a budget**: a rolling spending cap per period, a max per transaction, and an
  expiry — all enforced on-chain, so the agent literally cannot exceed them.
- **Let the agent pay** recipients autonomously within budget.
- **Queue over-budget payments** for one-click owner approval instead of blocking the agent.
- **Stay in control**: revoke an agent instantly, pause all spending, withdraw, or transfer
  ownership (two-step) at any time.

## How to use it

### 1. Install & build
```bash
curl -L https://foundry.paradigm.xyz | bash && foundryup
forge install foundry-rs/forge-std
forge build
```

### 2. Set your key & network
```bash
export PRIVATE_KEY=0xYOUR_KEY
export RPC=https://atlantic.dplabs-internal.com   # Atlantic testnet (688689); mainnet: https://rpc.pharos.xyz
export OWNER=$(cast wallet address --private-key $PRIVATE_KEY)
```

### 3. Run it
Point your agent at [`SKILL.md`](SKILL.md). It maps your request to
[`references/agent-allowance-vault.md`](references/agent-allowance-vault.md) and runs the exact
`cast`/`forge` command. You can also run any command directly from the reference file.

## Examples

**Talk to the agent in plain English:**

| You say | The agent does |
|---------|----------------|
| "Deploy a vault and fund it with 1 PHRS" | deploys the native vault, calls `depositNative` |
| "Give agent 0xABC… 100 PHRS/day, max 40 per payment" | `grantAllowance(0xABC…, 100, 40, 86400, 0)` |
| "Pay 25 PHRS to 0xDEF…" | `pay(0xDEF…, 25)` (within budget) |
| "Pay 500 PHRS to 0xDEF…" (over budget) | `requestPayment(...)` → you `approvePayment(id)` |
| "Cut off agent 0xABC… now" | `revokeAllowance(0xABC…)` |
| "Freeze the vault" | `setPaused(true)` |

**Or run the core flow directly (native PHRS vault):**
```bash
# deploy a native vault (asset = address(0))
forge create src/AgentAllowanceVault.sol:AgentAllowanceVault --rpc-url $RPC --private-key $PRIVATE_KEY \
  --broadcast --constructor-args 0x0000000000000000000000000000000000000000
# fund it, then grant an agent a budget and let it pay
cast send $VAULT "depositNative()" --value $(cast to-wei 1 ether) --rpc-url $RPC --private-key $PRIVATE_KEY
cast send $VAULT "grantAllowance(address,uint256,uint256,uint256,uint64)" $AGENT \
  $(cast to-wei 0.5 ether) $(cast to-wei 0.2 ether) 86400 0 --rpc-url $RPC --private-key $PRIVATE_KEY
cast send $VAULT "pay(address,uint256)" $RECIPIENT $(cast to-wei 0.1 ether) --rpc-url $RPC --private-key $AGENT_KEY
```

Run the full lifecycle locally with `./scripts/demo.sh`. Every command, with parameters and
error notes, is in [`references/agent-allowance-vault.md`](references/agent-allowance-vault.md).
Live vault on Atlantic is in [DEPLOYMENT.md](DEPLOYMENT.md).
