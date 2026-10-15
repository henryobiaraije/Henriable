#!/usr/bin/env bash
#
# Re-verify an already-deployed Henriable platform on Sepolia (Etherscan).
#
# Why this is separate from deploy-sepolia.sh:
#   Verification is flaky and re-runnable. Etherscan often has not indexed a
#   brand-new contract yet, so the --verify step inside a deploy can fail even
#   though the deployment itself succeeded. Retrying verification here needs no
#   redeploy, and a failed verify can never be mistaken for a failed deploy.
#
# Where the deployment details come from (nothing is typed by hand):
#   forge writes them to broadcast/Deploy.s.sol/<chainId>/run-latest.json on the
#   last deploy -- the deployed contract addresses and, for Henriable, the
#   constructor args (the tail of the recorded transaction input). This script
#   reads that file and verifies both deployed contracts.
#
# Usage:
#   ./script/verify-sepolia.sh
#
# Env (from .env):
#   ETHERSCAN_API_KEY    required; the key used for verification.
#   SEPOLIA_PRIVATE_KEY  required; used only to derive the owner for constructor args.
#   USDC_ADDRESS         optional; defaults to Circle's Sepolia USDC (must match deploy).
#   VERIFY_ATTEMPTS      optional; how many times to retry each contract (default 3).

# Fail fast on errors, unset variables and failed pipes.
set -euo pipefail

# Resolve the project root (this script lives in script/) and work from there.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# Verify against the same via-IR profile used to deploy, or the bytecode will differ.
export FOUNDRY_PROFILE="${FOUNDRY_PROFILE:-production}"

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

if [ ! -f "$BROADCAST" ]; then
    echo "error: $BROADCAST not found (deploy first)" >&2
    exit 1
fi

# Read both CREATE addresses recorded by the last deploy.
mapfile -t ADDRESSES < <(python3 - "$BROADCAST" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
wanted = ("HenriableVehicleNFT", "Henriable")
found = {}
for tx in data.get("transactions", []):
    name = tx.get("contractName")
    if tx.get("transactionType") == "CREATE" and name in wanted:
        found.setdefault(name, tx["contractAddress"])
for name in wanted:
    if name not in found:
        sys.exit(name + " CREATE not found in " + sys.argv[1])
    print(found[name])
PY
)

NFT_ADDRESS="${ADDRESSES[0]}"
HENRIABLE_ADDRESS="${ADDRESSES[1]}"

# Constructor args must match Deploy.s.sol.
#   NFT:        (initialOwner)
#   Henriable:  (initialOwner, usdc, vehicleNft)
OWNER_ADDRESS="$(cast wallet address --private-key "${SEPOLIA_PRIVATE_KEY:?SEPOLIA_PRIVATE_KEY is not set}")"
USDC_ADDRESS="${USDC_ADDRESS:-0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238}"
NFT_ARGS="$(cast abi-encode "constructor(address)" "$OWNER_ADDRESS")"
HENRIABLE_ARGS="$(cast abi-encode "constructor(address,address,address)" "$OWNER_ADDRESS" "$USDC_ADDRESS" "$NFT_ADDRESS")"

ATTEMPTS="${VERIFY_ATTEMPTS:-3}"

# verify_contract <address> <contract-path> <constructor-args>
verify_contract() {
    local address="$1" source="$2" args="$3"

    echo "Verifying ${source} at ${address}"
    for attempt in $(seq 1 "$ATTEMPTS"); do
        if forge verify-contract "$address" "$source" \
            --chain sepolia \
            --constructor-args "$args" \
            --etherscan-api-key "$ETHERSCAN_API_KEY"; then
            echo "Verified: ${address}"
            return 0
        fi

        if [ "$attempt" -lt "$ATTEMPTS" ]; then
            echo "attempt ${attempt}/${ATTEMPTS} failed; retrying in 15s (explorer may still be indexing)..." >&2
            sleep 15
        fi
    done

    echo "error: verification of ${source} at ${address} failed after ${ATTEMPTS} attempts" >&2
    return 1
}

echo "Chain ${CHAIN_ID}; owner ${OWNER_ADDRESS}; usdc ${USDC_ADDRESS}"
verify_contract "$NFT_ADDRESS" "src/HenriableVehicleNFT.sol:HenriableVehicleNFT" "$NFT_ARGS"
verify_contract "$HENRIABLE_ADDRESS" "src/Henriable.sol:Henriable" "$HENRIABLE_ARGS"
