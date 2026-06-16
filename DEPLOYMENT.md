# Live Deployment — Pharos Atlantic Testnet

> Network: **Pharos Atlantic Testnet** · chainId **688689** · RPC
> `https://atlantic.dplabs-internal.com` · Explorer `https://atlantic.pharosscan.xyz`
>
> (The default `testnet.dplabs-internal.com` / 688688 endpoint was unreachable at deploy
> time, so the live demo runs on Atlantic. Both networks are in `assets/networks.json`.)

## Primary deployment — Native PHRS vault ✅

The vault custodies the **real native testnet asset (PHRS)** — no mock token. `asset` is
`address(0)`, so `isNative()` returns `true`.

| Contract | Address | Explorer |
|----------|---------|----------|
| **AgentAllowanceVault (native PHRS)** | `0xf98dAFAEaD0eEdb3490F0514CC9B6d299964E515` | https://atlantic.pharosscan.xyz/address/0xf98dAFAEaD0eEdb3490F0514CC9B6d299964E515 |

### Native lifecycle executed on-chain (real PHRS)
1. Deployed vault with `asset = address(0)` → native PHRS.
2. `depositNative()` funded the vault with **1 PHRS**.
3. Owner granted agent allowance: **cap 0.5 / maxPerTx 0.2 / period 1 day / no expiry**.
4. Agent autonomously **paid 0.1 PHRS** within budget → remaining 0.4, vault 0.9.
5. Agent **requested 0.3 PHRS** (exceeds the 0.2 per-tx limit, so it needs approval) →
   owner **approved** → vault 0.6 PHRS.

## Secondary deployment — ERC20 vault (optional reference)

Also deployed an ERC20-custody instance against a faucet test token, proving the same
contract handles ERC20 assets.

| Contract | Address |
|----------|---------|
| AgentAllowanceVault (ERC20) | `0x14c3c6B5FC5B46c79B4b9cd5d0B2f5a096120ce2` |
| MockPROS (faucet test token) | `0xB1BDE02a3604FE54262f1d69Bb45fcbf98d28B0B` |

## Roles

| Role | Address |
|------|---------|
| Owner | `0x218996B33147B62FC86e59200455708FBf25225d` |
| Agent (demo) | `0xE15f0846C6641F3b768638A673e491CB463cbF74` |
| Recipient (demo) | `0x000000000000000000000000000000000000dEaD` |

## Source verification

The verification API on PharosScan sits behind a Vercel bot-protection checkpoint, so the
automated `forge verify-contract` call can't pass it. Verify manually via the web UI:

1. Open the vault address on the explorer → **Contract** tab → **Verify & Publish**.
2. Method: **Standard JSON Input** (Blockscout). Upload
   [`verification/standard-json-input.json`](verification/standard-json-input.json).
3. Settings to match:
   - Compiler: **v0.8.24**
   - Optimization: **Enabled, 200 runs**
   - EVM version: **paris**
   - Contract name: `AgentAllowanceVault`
   - Constructor args (ABI-encoded) for the **native** vault:
     `0x0000000000000000000000000000000000000000000000000000000000000000`
   - License: MIT

The contract is a single self-contained file (no imports), so "Single file" verification
with `src/AgentAllowanceVault.sol` also works.
