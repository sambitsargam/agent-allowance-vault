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

## Examples

Talk to the agent in plain English:

| You say | The agent does |
|---------|----------------|
| "Deploy a vault and fund it with 1 PHRS" | deploys the native vault, calls `depositNative` |
| "Give agent 0xABC… 100 PHRS/day, max 40 per payment" | `grantAllowance(0xABC…, 100, 40, 86400, 0)` |
| "Pay 25 PHRS to 0xDEF…" | `pay(0xDEF…, 25)` (within budget) |
| "Pay 500 PHRS to 0xDEF…" (over budget) | `requestPayment(...)` → you `approvePayment(id)` |
| "Cut off agent 0xABC… now" | `revokeAllowance(0xABC…)` |
| "Freeze the vault" | `setPaused(true)` |

## How to use it

Point your agent at [`SKILL.md`](SKILL.md) — it contains the setup, capability index, and the
exact `cast`/`forge` command for every operation. The agent matches your request to
[`references/agent-allowance-vault.md`](references/agent-allowance-vault.md) and runs it. Run
the full lifecycle locally with `./scripts/demo.sh`; live vault on Atlantic is in
[DEPLOYMENT.md](DEPLOYMENT.md).
