# Agent Allowance Vault

A Pharos Skill Engine skill that lets you give an AI agent a spending allowance instead of your
private key: the agent pays from a vault within on-chain limits (cap, per-tx max, expiry), and
anything over the limit waits for your approval.

## How to use it

1. Install & build

```bash
curl -L https://foundry.paradigm.xyz | bash && foundryup
forge install foundry-rs/forge-std
forge build
```

2. Set your key & network

```bash
export PRIVATE_KEY=0xYOUR_KEY
export RPC=https://atlantic.dplabs-internal.com   # Atlantic testnet (688689); mainnet: https://rpc.pharos.xyz
```

3. Run it

Point your agent at [`SKILL.md`](SKILL.md) — it maps your request to
[`references/agent-allowance-vault.md`](references/agent-allowance-vault.md) and runs the
`cast`/`forge` command. Or run any command directly from the reference file.
