#!/usr/bin/env bash
#
# Re-verify an already-deployed Henriable on Sepolia (Etherscan).
#
# Why this is separate from deploy-sepolia.sh:
#   Verification is flaky and re-runnable. Etherscan often has not indexed a
#   brand-new contract yet, so the --verify step inside a deploy can fail even
#   though the deployment itself succeeded. Retrying verification here needs no
#   redeploy, and a failed verify can never be mistaken for a failed deploy.
#
# Where the deployment details come from (nothing is typed by hand):
#   forge writes them to broadcast/Deploy.s.sol/<chainId>/run-latest.json on the
#   last deploy -- the deployed contract address and the exact constructor args
#   (the tail of the recorded transaction input). This script reads that file.
#   Pass an address as the first argument to verify a specific deployment instead.
#
# Usage:
#   ./script/verify-sepolia.sh [contractAddress]
#
# Env (from .env):
#   ETHERSCAN_API_KEY    required; the key used for verification.
#   SEPOLIA_PRIVATE_KEY  required unless an address is passed as arg 1; used only
#                        to derive the owner address for the constructor args.
#   USDC_ADDRESS         optional; defaults to Circle's Sepolia USDC (must match
#                        the value used at deploy time).
#   VERIFY_ATTEMPTS      optional; how many times to retry (default 3).

# Fail fast on errors, unset variables and failed pipes.
set -euo pipefail

# Resolve the project root (this script lives in script/) and work from there.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# Load .env for ETHERSCAN_API_KEY / SEPOLIA_PRIVATE_KEY / USDC_ADDRESS.
if [ -f .env ]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
fi

: "${ETHERSCAN_API_KEY:?ETHERSCAN_API_KEY is not set (see .env.example)}"

CHAIN_ID=11155111
BROADCAST="broadcast/Deploy.s.sol/${CHAIN_ID}/run-latest.json"

# Address: first argument, else the Henriable CREATE recorded by the last deploy.
if [ "$#" -ge 1 ] && [ -n "$1" ]; then
    CONTRACT_ADDRESS="$1"
else
    if [ ! -f "$BROADCAST" ]; then
        echo "error: no address given and $BROADCAST not found (deploy first)" >&2
        exit 1
    fi
    CONTRACT_ADDRESS="$(python3 - "$BROADCAST" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for tx in data.get("transactions", []):
    if tx.get("transactionType") == "CREATE" and tx.get("contractName") == "Henriable":
        print(tx["contractAddress"])
        break
else:
    sys.exit("Henriable CREATE not found in " + sys.argv[1])
PY
)"
fi

# Constructor args must match Deploy.s.sol: (initialOwner, usdc).
OWNER_ADDRESS="$(cast wallet address --private-key "${SEPOLIA_PRIVATE_KEY:?SEPOLIA_PRIVATE_KEY is not set}")"
USDC_ADDRESS="${USDC_ADDRESS:-0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238}"
CONSTRUCTOR_ARGS="$(cast abi-encode "constructor(address,address)" "$OWNER_ADDRESS" "$USDC_ADDRESS")"

echo "Verifying ${CONTRACT_ADDRESS} on chain ${CHAIN_ID}"
echo "  owner: ${OWNER_ADDRESS}"
echo "  usdc:  ${USDC_ADDRESS}"

# Etherscan can lag behind the chain; retry a few times before giving up.
ATTEMPTS="${VERIFY_ATTEMPTS:-3}"
verified=0
for attempt in $(seq 1 "$ATTEMPTS"); do
    if forge verify-contract "$CONTRACT_ADDRESS" src/Henriable.sol:Henriable \
        --chain sepolia \
        --constructor-args "$CONSTRUCTOR_ARGS" \
        --etherscan-api-key "$ETHERSCAN_API_KEY"; then
        verified=1
        break
    fi

    if [ "$attempt" -lt "$ATTEMPTS" ]; then
        echo "attempt ${attempt}/${ATTEMPTS} failed; retrying in 15s (explorer may still be indexing)..." >&2
        sleep 15
    fi
done

if [ "$verified" -ne 1 ]; then
    echo "error: verification failed after ${ATTEMPTS} attempts" >&2
    exit 1
fi

echo "Verified: ${CONTRACT_ADDRESS}"
