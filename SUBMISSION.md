# DoraHacks Submission — Agent Allowance Vault

> Copy/paste-ready submission content for the Pharos Phase 1 Hackathon.
> Fill the `<...>` placeholders (repo URL, deployed addresses, demo video) before submitting.

---

## Project name
**Agent Allowance Vault** — the on-chain spending-limit primitive for AI agents.

## One-liner
A Pharos Skill that lets a human delegate **bounded, revocable** spending power to
autonomous AI agents — hard budget caps enforced on-chain, not by the prompt.

## Tagline for the "Skills first, agents second" theme
Before an agent can safely *make payments*, someone has to make it *safe to pay*. This is
that foundational Skill: the wallet guardrail every payment agent needs underneath it.

---

## Problem
Giving an autonomous AI agent a wallet today means giving it a private key — and one
hallucination, prompt injection, or bug can drain everything. "Be careful" in a system
prompt is not a security control. There is no native way to say *"this agent may spend up
to 100 PROS/day, max 40 per payment, and nothing else."*

## Solution
A custody vault that issues each agent a **spending allowance** instead of the keys:

- **Rolling spending cap** per period (e.g. 100 PROS/day)
- **Per-transaction maximum** (e.g. 40 PROS/payment)
- **Expiry** (e.g. valid for 30 days)
- **Over-budget approval queue** — the agent escalates exceptional spend to the human
  instead of being able to bypass its own limits
- **Owner controls** — revoke an agent instantly, pause everything, withdraw, two-step
  ownership transfer

Every limit is enforced in Solidity. The agent literally *cannot* exceed its budget; the
contract reverts. The funds never leave the owner's control.

## What makes it a Pharos *Skill* (not just a contract)
It ships as a complete Skill Engine package following the official 3-layer structure:

- `SKILL.md` — a Capability Index mapping ~17 natural-language intents ("give the agent a
  budget", "pay a merchant", "approve a payment", "cut off the agent") to exact instructions.
- `references/*.md` — machine-readable `cast`/`forge` command templates with parameter
  tables, output parsing, and a full error→fix map for every custom revert.
- `assets/` — the contract, a faucet test token, and `networks.json` for both Pharos
  testnets.

An AI agent reads this package and operates the vault end-to-end with no custom SDK.

---

## How it maps to the judging criteria

**Functionality / completeness**
Full lifecycle works end-to-end and is reproducible in one command (`./scripts/demo.sh`):
deploy → fund → grant → pay → block-over-limit → request → approve → revoke. 17 passing
tests including a fuzz test.

**Security (CertiK Skill Scanner)**
Designed to scan clean: single self-contained file, checks-effects-interactions,
ReentrancyGuard, SafeERC20, custom errors, owner-only admin, two-step ownership, Solidity
0.8.24. The agent never holds funds — it holds a capped allowance. See the Security section
in the README.

**Innovation**
Most hackathon skills wrap a single contract action. This introduces the *guardrail layer*
— the missing safety primitive that makes every other "agent pays X" skill deployable in
production. The request/approve escalation pattern is a novel human-in-the-loop design for
agent payments.

**Usability for agents**
Natural-language Capability Index, exact copy-run commands, deterministic error handling,
and explorer links on every action.

---

## Tech stack
Solidity 0.8.24 · Foundry (`forge`/`cast`/`anvil`) · Pharos Skill Engine 3-layer format ·
Pharos Testnet (chainId 688688) / Atlantic (688689).

## Links

### Live on Pharos Atlantic Testnet (chainId 688689)
- **Deployed vault (native PHRS):** `0xf98dAFAEaD0eEdb3490F0514CC9B6d299964E515`
  → https://atlantic.pharosscan.xyz/address/0xf98dAFAEaD0eEdb3490F0514CC9B6d299964E515
- Custodies the **real native testnet asset (PHRS)** — no mock token. `isNative() == true`.
- Full on-chain lifecycle with real PHRS (fund → grant → pay → request → approve) executed
  — see [DEPLOYMENT.md](DEPLOYMENT.md). (An ERC20-mode vault was also deployed to prove the
  same contract handles ERC20 assets.)

### To fill in before submitting
- **GitHub repo:** `<repo-url>`
- **Demo video (2–3 min):** `<youtube-or-loom-link>`
- **Verified source on PharosScan:** verify via web UI (steps in [DEPLOYMENT.md](DEPLOYMENT.md))

## Suggested 2–3 minute demo video script
1. (20s) The problem: "you can't give an AI agent your private key." 
2. (30s) Deploy the vault, fund it, grant an agent `100/day, 40 max` — show it on PharosScan.
3. (40s) Ask the agent (in plain English) to pay a merchant 25 → it works. Ask it to pay
   1000 → **the chain rejects it** (`BudgetExceeded`). This is the money shot.
4. (30s) Agent escalates via `requestPayment`; owner approves with one call.
5. (20s) Owner hits `pause` / `revoke` → agent is cut off instantly.
6. (10s) "Guardrails enforced on-chain, not by the prompt. Skills first, agents second."
