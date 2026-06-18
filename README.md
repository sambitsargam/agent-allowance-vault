# Agent Allowance Vault

A [Pharos Skill Engine](https://docs.pharos.xyz/tooling-and-infrastructure/pharos-skill-engine-guide)
skill that lets you give an AI agent a **spending allowance instead of your private key**. The
agent pays from a shared vault within limits you set on-chain; anything over the limit waits for
your approval.

## What it can do

- **Fund a vault** with native PHRS (or any ERC20) that an agent can spend from.
- **Grant an agent a budget**: a rolling spending cap per period, a max per transaction, and an
  expiry. The contract enforces all three — the agent literally cannot exceed them.
- **Let the agent pay** merchants/recipients autonomously within the budget.
- **Queue over-budget payments** for one-click owner approval (the agent escalates instead of
  being blocked).
- **Stay in control**: revoke an agent instantly, pause everything, withdraw, or hand over
  ownership (two-step).

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
export RPC=https://atlantic.dplabs-internal.com   # Atlantic testnet (688689)
export OWNER=$(cast wallet address --private-key $PRIVATE_KEY)
```

### 3. Use it as a skill
Point your agent at `SKILL.md`; it matches your request to `references/agent-allowance-vault.md`
and runs the right `cast`/`forge` command. Example:

> "Give agent 0xABC… a budget of 100 PHRS per day, max 40 per payment, then pay 25 to 0xDEF…"

The agent calls `grantAllowance(...)` then `pay(...)`; an over-budget request becomes
`requestPayment(...)` for you to `approvePayment(...)`.

### 4. …or run the core flow directly (native PHRS vault)
```bash
# deploy a native vault (asset = address(0))
forge create src/AgentAllowanceVault.sol:AgentAllowanceVault --rpc-url $RPC --private-key $PRIVATE_KEY \
  --broadcast --constructor-args 0x0000000000000000000000000000000000000000
# fund it
cast send $VAULT "depositNative()" --value $(cast to-wei 1 ether) --rpc-url $RPC --private-key $PRIVATE_KEY
# grant an agent: 0.5 cap / 0.2 max-per-tx / 1-day period / no expiry
cast send $VAULT "grantAllowance(address,uint256,uint256,uint256,uint64)" $AGENT \
  $(cast to-wei 0.5 ether) $(cast to-wei 0.2 ether) 86400 0 --rpc-url $RPC --private-key $PRIVATE_KEY
# agent pays within budget
cast send $VAULT "pay(address,uint256)" $RECIPIENT $(cast to-wei 0.1 ether) --rpc-url $RPC --private-key $AGENT_KEY
```
Full command reference: [`references/agent-allowance-vault.md`](references/agent-allowance-vault.md).
Run the whole lifecycle locally: `./scripts/demo.sh`.

## Functions

| Function | Who | What |
|----------|-----|------|
| `depositNative()` / `deposit(amount)` | anyone | fund the vault (native / ERC20) |
| `grantAllowance(agent, cap, maxPerTx, period, expiry)` | owner | set an agent's budget |
| `pay(recipient, amount)` | agent | pay within budget (reverts if over) |
| `requestPayment(recipient, amount)` | agent | queue an over-budget payment |
| `approvePayment(id)` / `cancelPayment(id)` | owner / either | settle or drop a queued payment |
| `revokeAllowance(agent)` · `setPaused(bool)` · `withdraw(to, amount)` | owner | controls |
| `remainingAllowance(agent)` · `vaultBalance()` | anyone | reads |

## Networks

| Network | chainId | RPC |
|---------|---------|-----|
| Atlantic testnet (default) | 688689 | `https://atlantic.dplabs-internal.com` |
| Mainnet | 1672 | `https://rpc.pharos.xyz` |

A live native-PHRS vault on Atlantic is in [DEPLOYMENT.md](DEPLOYMENT.md).

## Notes
- The vault custodies **native PHRS** by default (`asset = address(0)`) or any ERC20.
- Built with Foundry + Solidity 0.8.24; single self-contained contract (no imports).
- Reference implementation for testnet/hackathon use — audit before mainnet value.

## License
MIT
