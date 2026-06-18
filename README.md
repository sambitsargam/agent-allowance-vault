# Agent Allowance Vault

A Pharos Skill Engine skill that lets you give an AI agent a spending allowance instead of your
private key: the agent pays from a vault within on-chain limits (cap, per-tx max, expiry), and
anything over the limit waits for your approval.

## How to use it

Setup (install, build, key, network) and the capability index are in [`SKILL.md`](SKILL.md).
Point your agent at it — it maps your request to
[`references/agent-allowance-vault.md`](references/agent-allowance-vault.md) and runs the
`cast`/`forge` command. You can also run any command directly from the reference file.
