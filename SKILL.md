# Agent Allowance Vault — Pharos Skill

> A Pharos Skill Engine skill that lets a human owner delegate **bounded, revocable
> spending power** to autonomous AI agents. Agents pay from a shared vault within an
> enforced budget; anything over budget is queued for one-click owner approval.
> Security guardrails are enforced on-chain, not by the agent.

---

## Prerequisites (check before doing anything)

1. **Foundry installed** — run `which cast` and `which forge`. If missing, install:
   `curl -L https://foundry.paradigm.xyz | bash && foundryup`
2. **Environment variables set:**
   ```bash
   export PRIVATE_KEY=0xYOUR_KEY          # never hardcode or commit this
   export RPC=https://atlantic.dplabs-internal.com  # Pharos Atlantic (chainId 688689, reachable)
   export OWNER=$(cast wallet address --private-key $PRIVATE_KEY)
   ```
3. **Network config** — read `assets/networks.json` for RPC URL, chain ID, and explorer.
   The default `pharos-testnet` (**688688**) endpoint may be access-gated; `pharos-atlantic`
   (**688689**) is the reachable live network used for deployment.
4. **Funds** — the owner needs PHRS (for gas, and to fund a native vault). Get test PHRS
   from the faucet in `assets/networks.json`. The vault custodies one asset: **native PHRS**
   by default (`asset = address(0)`, recommended) or any ERC20. Only deploy `MockPROS` if
   you specifically want an ERC20 vault.
5. **Foundry does NOT read env vars automatically** — always pass `--private-key
   $PRIVATE_KEY` and `--rpc-url $RPC` explicitly on every command.

---

## What this skill does

A merchant/owner funds one vault with **native PHRS** (or an ERC20), then grants each AI
agent an **allowance**: a rolling spending `cap` per `period`, an optional `maxPerTx`, and an
`expiry`. The agent calls `pay()` to send money autonomously — the contract rejects any
payment over the per-tx limit or remaining budget. For exceptional spends, the agent
calls `requestPayment()` and the owner settles it with `approvePayment()`. The owner can
`pause`, `revoke`, `withdraw`, and transfer ownership at any time.

This is the on-chain "spending limit" primitive that makes it **safe to let an AI agent
hold a wallet**.

---

## Capability Index

| User Need | Capability | Detailed Instructions |
|-----------|-----------|----------------------|
| Deploy a vault / set up agent payments / create spending vault | `forge create` | → [references/agent-allowance-vault.md#1-deploy-the-vault](references/agent-allowance-vault.md#1-deploy-the-vault) |
| (ERC20 only) Deploy a test token / mint mPROS | `forge create` + `cast send` | → [references/agent-allowance-vault.md#0-erc20-vaults-only-deploy-a-test-token-mockpros](references/agent-allowance-vault.md#0-erc20-vaults-only-deploy-a-test-token-mockpros) |
| Fund the vault / deposit PHRS / deposit tokens / top up | `cast send depositNative` (native) or `approve`+`deposit` (ERC20) | → [references/agent-allowance-vault.md#2-fund-the-vault](references/agent-allowance-vault.md#2-fund-the-vault) |
| Grant an agent an allowance / give agent a budget / set spending limit | `cast send grantAllowance` | → [references/agent-allowance-vault.md#3-grant-an-agent-an-allowance](references/agent-allowance-vault.md#3-grant-an-agent-an-allowance) |
| Agent pays / send payment / spend from vault / pay a merchant | `cast send pay` | → [references/agent-allowance-vault.md#4-agent-makes-a-payment](references/agent-allowance-vault.md#4-agent-makes-a-payment) |
| Over-budget payment / request approval / queue a big payment | `cast send requestPayment` | → [references/agent-allowance-vault.md#5-request-an-over-budget-payment](references/agent-allowance-vault.md#5-request-an-over-budget-payment) |
| Approve a payment / settle pending payment / sign off | `cast send approvePayment` | → [references/agent-allowance-vault.md#6-owner-approves-a-pending-payment](references/agent-allowance-vault.md#6-owner-approves-a-pending-payment) |
| Cancel a request / reject pending payment | `cast send cancelPayment` | → [references/agent-allowance-vault.md#7-cancel-a-pending-payment](references/agent-allowance-vault.md#7-cancel-a-pending-payment) |
| Revoke an agent / disable agent / cut off spending | `cast send revokeAllowance` | → [references/agent-allowance-vault.md#8-revoke-an-agent](references/agent-allowance-vault.md#8-revoke-an-agent) |
| Pause / freeze / emergency stop | `cast send setPaused` | → [references/agent-allowance-vault.md#9-pause--unpause](references/agent-allowance-vault.md#9-pause--unpause) |
| Withdraw funds / pull money out / empty vault | `cast send withdraw` | → [references/agent-allowance-vault.md#10-withdraw-funds-owner](references/agent-allowance-vault.md#10-withdraw-funds-owner) |
| Transfer ownership / change owner | `cast send transferOwnership` + `acceptOwnership` | → [references/agent-allowance-vault.md#11-transfer-ownership-two-step](references/agent-allowance-vault.md#11-transfer-ownership-two-step) |
| Check remaining budget / how much can the agent spend | `cast call remainingAllowance` | → [references/agent-allowance-vault.md#12-read-an-agents-remaining-budget](references/agent-allowance-vault.md#12-read-an-agents-remaining-budget) |
| Check vault balance / how much is in the vault | `cast call vaultBalance` | → [references/agent-allowance-vault.md#13-read-the-vault-balance](references/agent-allowance-vault.md#13-read-the-vault-balance) |
| Inspect an allowance / view agent limits | `cast call getAllowance` | → [references/agent-allowance-vault.md#14-inspect-an-allowance-record](references/agent-allowance-vault.md#14-inspect-an-allowance-record) |
| Verify the contract / publish source on explorer | `forge verify-contract` | → [references/agent-allowance-vault.md#15-verify-on-pharosscan](references/agent-allowance-vault.md#15-verify-on-pharosscan) |
| Watch events / see payment history | `cast logs` | → [references/agent-allowance-vault.md#16-query-events](references/agent-allowance-vault.md#16-query-events) |
| Generic ERC20 balance / tx status / chain reads | `cast` | → [references/query.md](references/query.md) |
| Generic send / gas / transfer | `cast send` | → [references/transaction.md](references/transaction.md) |
| Generic deploy / verify any contract | `forge` | → [references/contract.md](references/contract.md) |

---

## Safety rules for the agent (always follow)

- **Never** invent an allowance. If `pay()` reverts with `BudgetExceeded` or
  `PerTxLimitExceeded`, do **not** retry with a smaller hidden split unless the user
  intended that — surface the limit and offer `requestPayment` for approval.
- **Never** call `withdraw`, `grantAllowance`, `revokeAllowance`, `setPaused`,
  `transferOwnership`, or `approvePayment` unless the caller is the vault **owner**.
  These are owner-only and will revert with `NotOwner` otherwise.
- Always read `remainingAllowance(agent)` before a payment to set user expectations.
- Always confirm the **recipient address** and **human-readable amount** (divide by
  10^decimals) with the user before broadcasting a `pay`.
- After every state change, parse the tx receipt and print the
  `https://testnet.pharosscan.xyz/tx/<hash>` explorer link.
