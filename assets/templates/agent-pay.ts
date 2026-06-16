/**
 * Example: an AI agent making an autonomous payment through the Agent Allowance Vault.
 *
 * This is the "agents second" half of the story — a minimal viem snippet an agent
 * runtime can call after deciding to pay. It pre-flights the on-chain budget, and if the
 * payment is over budget it escalates to the owner via requestPayment() instead of failing.
 *
 *   npm i viem
 *   AGENT_PRIVATE_KEY=0x... VAULT=0x... RPC=https://testnet.dplabs-internal.com \
 *     npx tsx assets/templates/agent-pay.ts 0xRecipient 25
 */
import {
  createPublicClient,
  createWalletClient,
  http,
  parseEther,
  formatEther,
  getAddress,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";

const RPC = process.env.RPC ?? "https://testnet.dplabs-internal.com";
const VAULT = getAddress(process.env.VAULT!);
const account = privateKeyToAccount(process.env.AGENT_PRIVATE_KEY as `0x${string}`);

const [recipientArg, amountArg] = process.argv.slice(2);
const recipient = getAddress(recipientArg);
const amount = parseEther(amountArg); // 18 decimals — works for native PHRS and 18-decimal ERC20s

const abi = [
  { type: "function", name: "remainingAllowance", stateMutability: "view",
    inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "vaultBalance", stateMutability: "view",
    inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "pay", stateMutability: "nonpayable",
    inputs: [{ type: "address" }, { type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "requestPayment", stateMutability: "nonpayable",
    inputs: [{ type: "address" }, { type: "uint256" }], outputs: [{ type: "uint256" }] },
] as const;

const pub = createPublicClient({ transport: http(RPC) });
const wallet = createWalletClient({ account, transport: http(RPC) });

async function main() {
  // Pre-flight: read the on-chain budget the agent is allowed to spend.
  const [remaining, balance] = await Promise.all([
    pub.readContract({ address: VAULT, abi, functionName: "remainingAllowance", args: [account.address] }),
    pub.readContract({ address: VAULT, abi, functionName: "vaultBalance" }),
  ]);
  console.log(`agent budget left: ${formatEther(remaining)} | vault balance: ${formatEther(balance)}`);

  if (amount > balance) throw new Error("vault underfunded — ask the owner to deposit");

  if (amount <= remaining) {
    // Within budget → pay directly. The contract still enforces the cap on-chain.
    const hash = await wallet.writeContract({ address: VAULT, abi, functionName: "pay", args: [recipient, amount] });
    console.log(`paid within budget → https://testnet.pharosscan.xyz/tx/${hash}`);
  } else {
    // Over budget → escalate to the owner instead of bypassing the limit.
    const hash = await wallet.writeContract({ address: VAULT, abi, functionName: "requestPayment", args: [recipient, amount] });
    console.log(`over budget → queued for owner approval: https://testnet.pharosscan.xyz/tx/${hash}`);
  }
}

main().catch((e) => { console.error(e); process.exit(1); });
