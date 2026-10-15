#!/usr/bin/env bash
#
# Sepolia testnet deployment of the whole Henriable platform (see script/Deploy.s.sol).
# One run deploys the vehicle-title NFT collection and Henriable (plus a mock USDC only
# when USDC_ADDRESS is unset), wires Henriable as the NFT minter, writes
# deployments/<chainId>.json, and verifies every contract on Etherscan when an
# ETHERSCAN_API_KEY is configured. Uses the real Circle USDC on Sepolia by default.
#
# Usage:
#   ./script/deploy-sepolia.sh [extra forge script flags...]
#
# Post-deploy check (why this script re-checks the chain at the end):
#   The Solidity script writes deployments/<chainId>.json during forge's *simulation*,
#   so a run whose broadcast fails still leaves a manifest full of addresses that were
#   never mined -- that is exactly how a phantom Henriable address leaked into the
#   frontend env. The manifest is therefore never treated as proof: after forge exits,
#   this script reads it, calls eth_getCode for each contract, prints DEPLOYED / MISSING
#   with bytecode size, reports the RPC chain id, and exits non-zero if a required
#   contract is missing. A CREATE address is only a prediction (keccak256 of deployer +
#   nonce); bytecode on-chain is the truth.
#
# Transaction ordering + self-finishing (why --slow is forced):
#   forge normally broadcasts a script's transactions in a burst. On a delegated
#   (EIP-7702) deployer the RPC caps in-flight transactions, so the last tx -- the
#   vehicleNft.setMinter() wiring -- can be silently dropped, leaving the contracts
#   DEPLOYED but the NFT un-mintable. This script therefore always passes --slow (each
#   tx confirmed before the next) and, as a safety net, re-reads nft.getMinter() and
#   sends the setMinter() tx itself when it is missing. One run yields a complete, wired
#   deployment or a loud failure -- there is nothing to fix up by hand afterwards.
#
# Gas headroom (why this script sets --gas-estimate-multiplier):
#   forge sets each transaction's gas limit to (estimated gas * multiplier). The
#   built-in default is tight enough that a deploy can run out of gas on a live
#   network -- the transaction fails with `gasUsed == gasLimit` -- when the real
#   cost is a few gas above forge's estimate. That is what happened on Sepolia:
#   the deploy needed ~5,430,766 gas but the limit was 5,430,751, so it reverted.
#   This script therefore defaults the multiplier to 200% (~2x the estimate) to
#   leave margin. You are only charged for gas actually used, never for the
#   limit, so a larger multiplier costs nothing extra; it only guards against
#   running out. Keep it well under the block gas limit (~30M on Ethereum) so
#   the transaction is still accepted.
#   Override the default two ways:
#     GAS_ESTIMATE_MULTIPLIER=300 ./script/deploy-sepolia.sh   # env var
#     ./script/deploy-sepolia.sh -g 300                        # your own forge flag
#   When you pass your own -g / --gas-estimate-multiplier, the script detects it
#   and omits its own flag, because forge refuses a duplicate
#   --gas-estimate-multiplier rather than letting the last one win.

# Fail fast on errors, unset variables and failed pipes.
set -euo pipefail

# Resolve the project root (this script lives in script/) and work from there.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# Deploy with via-IR so the contract fits under the EIP-170 size limit.
export FOUNDRY_PROFILE="${FOUNDRY_PROFILE:-production}"

# Load .env so SEPOLIA_RPC_URL / SEPOLIA_PRIVATE_KEY are exported to forge.
if [ -f .env ]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
else
    echo "error: .env not found in $PROJECT_ROOT (copy .env.example to .env)" >&2
    exit 1
fi

# Make sure the required variables are present.
: "${SEPOLIA_RPC_URL:?SEPOLIA_RPC_URL is not set (see .env.example)}"
: "${SEPOLIA_PRIVATE_KEY:?SEPOLIA_PRIVATE_KEY is not set (see .env.example)}"

# The Solidity script reads the deployer key from DEPLOYER_PRIVATE_KEY.
export DEPLOYER_PRIVATE_KEY="$SEPOLIA_PRIVATE_KEY"

# Circle's USDC on Sepolia. Override by exporting USDC_ADDRESS before running.
export USDC_ADDRESS="${USDC_ADDRESS:-0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238}"

# Directory the Solidity script writes the deployment manifest into.
mkdir -p deployments

# Gas-limit headroom: default 200% of forge's gas estimate (see the header for
# why). Override with GAS_ESTIMATE_MULTIPLIER=<n>, or by passing your own -g <n>.
GAS_ESTIMATE_MULTIPLIER="${GAS_ESTIMATE_MULTIPLIER:-200}"

# forge rejects a duplicate --gas-estimate-multiplier, so only add our flag when
# the caller did not already pass -g / --gas-estimate-multiplier themselves.
gas_args=(--gas-estimate-multiplier "$GAS_ESTIMATE_MULTIPLIER")

# --slow is forced: it makes forge confirm each transaction before sending the next,
# which is what prevents the RPC from dropping the final setMinter() tx (see the header).
# Passing --slow yourself just suppresses the duplicate; --resume still composes with it.
slow_args=(--slow)

for arg in "$@"; do
    case "$arg" in
        -g | --gas-estimate-multiplier | -g=* | --gas-estimate-multiplier=* | -g[0-9]*)
            gas_args=()
            ;;
        --slow)
            slow_args=()
            ;;
    esac
done

# Verify on Etherscan when an API key is available.
verify_args=()
if [ -n "${ETHERSCAN_API_KEY:-}" ]; then
    verify_args=(--verify --etherscan-api-key "$ETHERSCAN_API_KEY")
fi

# The chain this script targets. Kept explicit so the on-chain check below can flag
# an RPC that is not actually Sepolia (e.g. a custom "Sepolia"-named fork network).
CHAIN_ID=11155111
DEPLOYMENT_FILE="deployments/${CHAIN_ID}.json"

# Read one key from the manifest, preferring jq but falling back to python3.
json_get() {
    if command -v jq >/dev/null 2>&1; then
        jq -r --arg key "$2" '.[$key] // empty' "$1"
    else
        python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2], ""))' "$1" "$2"
    fi
}

# Deploy. Extra arguments passed to this script are forwarded to forge. A broadcast
# can fail partway (e.g. Infura's "gapped-nonce ... delegated accounts"), so capture the
# status instead of letting `set -e` abort before we can report what really landed.
set +e
forge script script/Deploy.s.sol \
    --rpc-url "$SEPOLIA_RPC_URL" \
    --broadcast \
    "${slow_args[@]}" \
    "${gas_args[@]}" \
    "${verify_args[@]}" \
    "$@"
forge_status=$?
set -e

# ---- Reality check: confirm bytecode actually exists on-chain -------------------
echo
echo "================== on-chain deployment check =================="
rpc_chain_id="$(cast chain-id --rpc-url "$SEPOLIA_RPC_URL" 2>/dev/null || echo unknown)"
printf 'rpc           %s\n' "$SEPOLIA_RPC_URL"
printf 'rpc chain id  %s (expected %s)\n' "$rpc_chain_id" "$CHAIN_ID"
if [ "$rpc_chain_id" != "$CHAIN_ID" ]; then
    echo "WARNING: the RPC chain id does not match $CHAIN_ID -- wrong network?"
fi

# Addresses can come back 32-byte padded (and checksummed) from cast; compare on the
# low 20 bytes, case-insensitively.
normalize_addr() {
    local addr="${1,,}"
    addr="${addr#0x}"
    printf '0x%s' "${addr: -40}"
}

missing=0
nft_address=""
henriable_address=""
if [ -f "$DEPLOYMENT_FILE" ]; then
    printf 'manifest      %s\n\n' "$DEPLOYMENT_FILE"
    for name in usdc vehicleNft henriable; do
        address="$(json_get "$DEPLOYMENT_FILE" "$name")"
        [ -z "$address" ] && continue
        code="$(cast code "$address" --rpc-url "$SEPOLIA_RPC_URL" 2>/dev/null || echo 0x)"
        size=$(( (${#code} - 2) / 2 ))
        if [ "$size" -gt 0 ]; then
            printf '  %-11s %s  DEPLOYED (%s bytes)\n' "$name" "$address" "$size"
            case "$name" in
                vehicleNft) nft_address="$address" ;;
                henriable) henriable_address="$address" ;;
            esac
            if [ "$name" = "henriable" ]; then
                count_hex="$(cast call "$address" "getAssetsCount()(uint256)" --rpc-url "$SEPOLIA_RPC_URL" 2>/dev/null || echo '')"
                if [ -n "$count_hex" ]; then
                    count="$(cast to-dec "$count_hex" 2>/dev/null || echo "$count_hex")"
                else
                    count="(call failed)"
                fi
                printf '  %-11s getAssetsCount() = %s\n' "" "$count"
            fi
        else
            printf '  %-11s %s  *** NOT DEPLOYED (no bytecode) ***\n' "$name" "$address"
            case "$name" in
                henriable | vehicleNft) missing=1 ;;
            esac
        fi
    done
else
    printf 'manifest      %s NOT FOUND (the Solidity script never reached writeFile)\n' "$DEPLOYMENT_FILE"
    missing=1
fi

# ---- Ensure Henriable is wired as the NFT minter --------------------------------
# If the broadcast dropped setMinter(), the contracts are DEPLOYED but the NFT cannot
# be minted. Finish the wiring here in one sequential tx (a single tx can't trip the
# in-flight cap), so one run is genuinely complete.
if [ "$missing" -eq 0 ] && [ -n "$nft_address" ] && [ -n "$henriable_address" ]; then
    minter="$(cast call "$nft_address" "getMinter()(address)" --rpc-url "$SEPOLIA_RPC_URL" 2>/dev/null || echo '')"
    if [ "$(normalize_addr "$minter")" != "$(normalize_addr "$henriable_address")" ]; then
        echo
        echo "minter not wired (getMinter=$minter); sending setMinter($henriable_address)..."
        cast send "$nft_address" "setMinter(address)" "$henriable_address" \
            --rpc-url "$SEPOLIA_RPC_URL" --private-key "$SEPOLIA_PRIVATE_KEY" || true
        minter="$(cast call "$nft_address" "getMinter()(address)" --rpc-url "$SEPOLIA_RPC_URL" 2>/dev/null || echo '')"
    fi
    printf '\n  %-11s nft.getMinter() = %s\n' "wiring" "$minter"
    if [ "$(normalize_addr "$minter")" != "$(normalize_addr "$henriable_address")" ]; then
        printf '  %-11s *** NOT WIRED -- NFT minting would revert ***\n' ""
        missing=1
    fi
fi

# ---- Verdict --------------------------------------------------------------------
echo
if [ "$missing" -ne 0 ]; then
    echo "RESULT: NOT DONE -- see the *** lines above."
    echo "        The manifest is written during simulation, so it can list addresses"
    echo "        that were never mined. Do NOT copy them into the frontend env."
    echo "        Re-run: ./script/deploy-sepolia.sh   (--slow is applied automatically)."
    exit 1
fi

if [ "$forge_status" -ne 0 ]; then
    echo "NOTE: forge exited with status $forge_status (usually the dropped wiring tx)."
    echo "      The contracts are deployed and the minter is wired, so the deployment is"
    echo "      complete. If Etherscan verification did not run, finish it with:"
    echo "      ./script/verify-sepolia.sh"
    echo
fi

echo "RESULT: DONE -- contracts deployed, wired, and ready on chain $CHAIN_ID."
echo "        NEXT_PUBLIC_HENRIABLE_ADDRESS=\"$henriable_address\""
