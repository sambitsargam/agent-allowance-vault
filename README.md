# Agent Allowance Vault — a Pharos Skill Engine Skill

> **The on-chain spending-limit primitive that makes it safe to give an AI agent a wallet.**
>
> Built for the [Pharos Phase 1 Hackathon](https://dorahacks.io/hackathon/pharos-phase1/).
> *Skills first, agents second.*

A human owner funds one vault (with **native PHRS** or any ERC20) and delegates
**bounded, revocable** spending power to autonomous AI agents. Agents pay merchants
directly — but only within an on-chain budget:
a rolling spending cap, an optional per-transaction maximum, and an expiry. Anything over
budget is queued for one-click owner approval. The owner can pause, revoke, or withdraw at
any moment. **Every limit is enforced by the contract, not by the agent's prompt.**

This is packaged as a **Pharos Skill** — a self-contained knowledge + tooling bundle that
an AI agent reads to operate the contract through `cast`/`forge`, with no bespoke SDK.

---

## Why this wins the "agents handling payments" thesis

| Problem | This skill's answer |
|---------|--------------------|
| You can't hand an autonomous agent a raw private key — one hallucination drains the wallet. | The agent only ever holds a *spending allowance*, never the funds. Hard caps live on-chain. |
| Prompt-based "rules" aren't security. | `cap`, `maxPerTx`, `expiry`, pause, and owner-only controls are enforced in Solidity and covered by 17 tests + fuzzing. |
| Agents still need to handle exceptional spend. | A request/approve queue lets the agent escalate over-budget payments to the human without ever bypassing limits itself. |
| Judges score security (CertiK Skill Scanner). | Single self-contained contract, checks-effects-interactions, reentrancy guard, custom errors, two-step ownership, SafeERC20 — designed to scan clean. |

---

## Architecture: the 3-layer Pharos Skill

```
.
├── SKILL.md                         ← Layer 1: capability index (agent reads first)
├── references/
│   ├── agent-allowance-vault.md     ← Layer 2: exact cast/forge templates per operation
│   ├── query.md  transaction.md  contract.md
├── assets/                          ← Layer 3: contracts, configs, templates
│   ├── networks.json                ← Pharos RPCs, chain IDs, explorers
│   ├── tokens.json
│   └── agent-allowance-vault/
│       ├── AgentAllowanceVault.sol  ← the vault (source of truth)
│       └── MockPROS.sol             ← faucet test token
├── src/                             ← Foundry build sources
├── test/AgentAllowanceVault.t.sol   ← 17 tests incl. fuzzing
├── script/DeployVault.s.sol
└── scripts/demo.sh                  ← one-command reproducible local demo
```

An agent: reads `SKILL.md` → matches the user's intent in the Capability Index → opens the
referenced section → runs the exact `cast`/`forge` command → parses output → returns an
explorer link.

---

## Quickstart

### Prerequisites
```bash
# Foundry
curl -L https://foundry.paradigm.xyz | bash && foundryup
# (or: brew install foundry)
```

### Run the full demo locally (no testnet, no funds)
```bash
git clone <this-repo> && cd <this-repo>
forge install foundry-rs/forge-std
./scripts/demo.sh
```
This spins up `anvil`, deploys the token + vault, funds it, grants an agent a budget, and
walks the entire lifecycle — proving the guardrails fire on-chain.

### Run the tests
```bash
forge test -vvv
```

### Deploy to Pharos testnet
```bash
export PRIVATE_KEY=0xYOUR_KEY
export RPC=https://atlantic.dplabs-internal.com   # Atlantic (688689); 688688 may be gated
# Native-PHRS vault (recommended — custodies the real testnet asset, no token needed)
forge create src/AgentAllowanceVault.sol:AgentAllowanceVault \
  --rpc-url $RPC --private-key $PRIVATE_KEY --broadcast \
  --constructor-args 0x0000000000000000000000000000000000000000
# Fund it
cast send <VAULT> "depositNative()" --value $(cast to-wei 1 ether) \
  --rpc-url $RPC --private-key $PRIVATE_KEY
```
For an ERC20 vault instead, pass the token address as the constructor arg and fund with
`approve` + `deposit`. Full step-by-step (fund, grant, pay, approve, verify) lives in
[`references/agent-allowance-vault.md`](references/agent-allowance-vault.md). Live addresses
are in [DEPLOYMENT.md](DEPLOYMENT.md).

---

## The contract at a glance

| Function | Who | Effect |
|----------|-----|--------|
| `depositNative()` / `deposit(amount)` | anyone | fund the vault (native PHRS / ERC20) |
| `grantAllowance(agent, cap, maxPerTx, period, expiry)` | owner | set an agent's budget |
| `pay(recipient, amount)` | agent | pay within budget — reverts if over cap/per-tx |
| `requestPayment(recipient, amount)` | agent | queue an over-budget payment |
| `approvePayment(id)` | owner | settle a queued payment (explicit override) |
| `cancelPayment(id)` | owner/agent | drop a queued payment |
| `revokeAllowance(agent)` | owner | cut off an agent instantly |
| `setPaused(bool)` | owner | emergency stop |
| `withdraw(to, amount)` | owner | pull funds out |
| `transferOwnership` + `acceptOwnership` | owner / new owner | safe two-step handover |
| `remainingAllowance`, `vaultBalance`, `getAllowance`, `getPendingPayment` | anyone | reads |

---

## Security design (built for the CertiK Skill Scanner)

- **No fund custody by the agent** — agents hold allowances, never keys to the money.
- **Checks-Effects-Interactions** on every state-changing path; state written before transfer.
- **ReentrancyGuard** on `deposit`, `depositNative`, `pay`, `approvePayment`, `withdraw`
  — critical for the native-PHRS payout path (`call`).
- **SafeERC20** wrapper handles non-standard tokens and empty-code addresses; native
  payouts use a bounded `call` with an explicit success check (`NativeTransferFailed`).
- **Custom errors** for every failure → cheap gas + unambiguous agent error handling.
- **Two-step ownership transfer** prevents bricking the vault.
- **Owner-only** mutating admin functions; per-agent `active`/`expiry` gating.
- **Rolling-period accounting** that safely resets without external keepers.
- **17 unit tests + fuzz test** proving the cap is never exceeded within a period.
- **Single self-contained file** (no external imports) → minimal audit surface, trivial
  source verification on PharosScan.

Pinned to Solidity `0.8.24` (checked arithmetic). `block.timestamp` is used only for
day/hour-scale budget windows, where validator drift (seconds) is immaterial.

---

## License
MIT — see [LICENSE](LICENSE).
