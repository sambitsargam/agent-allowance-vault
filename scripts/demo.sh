#!/usr/bin/env bash
# Reproducible local demo of the Agent Allowance Vault skill (NATIVE PHRS mode).
# Spins up a local anvil chain, deploys a native-asset vault, and walks the full
# agent-payment lifecycle with on-chain guardrails. No tokens, no real funds.
#
# Usage:  ./scripts/demo.sh
# Requires: foundry (anvil, forge, cast) on PATH.
set -euo pipefail

command -v anvil >/dev/null || { echo "Install Foundry first: https://book.getfoundry.sh"; exit 1; }

echo "▶ starting local anvil…"
anvil > /tmp/aav-anvil.log 2>&1 &
ANVIL_PID=$!
trap 'kill $ANVIL_PID 2>/dev/null || true' EXIT
sleep 4

export RPC=http://127.0.0.1:8545
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80          # anvil #0 (owner)
export AGENT_PRIVATE_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d    # anvil #1 (agent)
OWNER=$(cast wallet address --private-key $PRIVATE_KEY)
AGENT=$(cast wallet address --private-key $AGENT_PRIVATE_KEY)
RECIPIENT=0x000000000000000000000000000000000000dEaD
hb(){ cast from-wei "$(cast call "$1" "$2" "$3" --rpc-url $RPC | cut -d' ' -f1)"; }
vb(){ cast from-wei "$(cast call "$1" 'vaultBalance()(uint256)' --rpc-url $RPC | cut -d' ' -f1)"; }

echo "▶ deploying a NATIVE-PHRS vault (asset = address(0))…"
VAULT=$(forge create src/AgentAllowanceVault.sol:AgentAllowanceVault --rpc-url $RPC --private-key $PRIVATE_KEY --broadcast --constructor-args 0x0000000000000000000000000000000000000000 2>/dev/null | awk '/Deployed to:/{print $3}')
echo "   vault=$VAULT  isNative=$(cast call $VAULT 'isNative()(bool)' --rpc-url $RPC)  owner=$OWNER  agent=$AGENT"

echo "▶ funding vault with 10 PHRS via depositNative()…"
cast send $VAULT "depositNative()" --value "$(cast to-wei 10 ether)" --rpc-url $RPC --private-key $PRIVATE_KEY >/dev/null
echo "   vault balance: $(vb $VAULT) PHRS"

echo "▶ owner grants agent: 1 PHRS/day cap, 0.4 max/tx, 1-day period, no expiry…"
cast send $VAULT "grantAllowance(address,uint256,uint256,uint256,uint64)" $AGENT "$(cast to-wei 1 ether)" "$(cast to-wei 0.4 ether)" 86400 0 --rpc-url $RPC --private-key $PRIVATE_KEY >/dev/null
echo "   remaining budget: $(hb $VAULT 'remainingAllowance(address)(uint256)' $AGENT) PHRS"

echo "▶ AGENT autonomously pays 0.3 PHRS (within budget)…"
cast send $VAULT "pay(address,uint256)" $RECIPIENT "$(cast to-wei 0.3 ether)" --rpc-url $RPC --private-key $AGENT_PRIVATE_KEY >/dev/null
echo "   remaining: $(hb $VAULT 'remainingAllowance(address)(uint256)' $AGENT) | recipient: $(cast balance $RECIPIENT --rpc-url $RPC --ether) PHRS"

echo "▶ AGENT tries to pay 0.5 (> 0.4 max/tx) — should be BLOCKED on-chain…"
OUT=$(cast send $VAULT "pay(address,uint256)" $RECIPIENT "$(cast to-wei 0.5 ether)" --rpc-url $RPC --private-key $AGENT_PRIVATE_KEY 2>&1 || true)
echo "$OUT" | grep -qi PerTxLimitExceeded && echo "   ✓ blocked: PerTxLimitExceeded"

echo "▶ AGENT requests an over-budget 5 PHRS payment → owner approves…"
cast send $VAULT "requestPayment(address,uint256)" $RECIPIENT "$(cast to-wei 5 ether)" --rpc-url $RPC --private-key $AGENT_PRIVATE_KEY >/dev/null
cast send $VAULT "approvePayment(uint256)" 0 --rpc-url $RPC --private-key $PRIVATE_KEY >/dev/null
echo "   recipient total: $(cast balance $RECIPIENT --rpc-url $RPC --ether) PHRS | vault: $(vb $VAULT) PHRS"

echo "▶ AGENT tries to withdraw (owner-only) — should be BLOCKED…"
OUT=$(cast send $VAULT "withdraw(address,uint256)" $AGENT 1 --rpc-url $RPC --private-key $AGENT_PRIVATE_KEY 2>&1 || true)
echo "$OUT" | grep -qi NotOwner && echo "   ✓ blocked: NotOwner"

echo ""
echo "✅ Demo complete — real native-asset payments, guardrails enforced on-chain (not by the prompt)."
