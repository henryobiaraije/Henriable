#!/usr/bin/env bash
#
# Sepolia testnet deployment of the Henriable platform (see script/Deploy.s.sol).
# Uses the real Circle USDC on Sepolia and verifies the contract on Etherscan
# when an ETHERSCAN_API_KEY is configured.
#
# Usage:
#   ./script/deploy-sepolia.sh [extra forge script flags...]
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

# Gas-limit headroom: default 200% of forge's gas estimate (see the header for
# why). Override with GAS_ESTIMATE_MULTIPLIER=<n>, or by passing your own -g <n>.
GAS_ESTIMATE_MULTIPLIER="${GAS_ESTIMATE_MULTIPLIER:-200}"

# forge rejects a duplicate --gas-estimate-multiplier, so only add our flag when
# the caller did not already pass -g / --gas-estimate-multiplier themselves.
gas_args=(--gas-estimate-multiplier "$GAS_ESTIMATE_MULTIPLIER")
for arg in "$@"; do
    case "$arg" in
        -g | --gas-estimate-multiplier | -g=* | --gas-estimate-multiplier=* | -g[0-9]*)
            gas_args=()
            break
            ;;
    esac
done

# Verify on Etherscan when an API key is available.
verify_args=()
if [ -n "${ETHERSCAN_API_KEY:-}" ]; then
    verify_args=(--verify --etherscan-api-key "$ETHERSCAN_API_KEY")
fi

# Deploy. Extra arguments passed to this script are forwarded to forge.
forge script script/Deploy.s.sol \
    --rpc-url "$SEPOLIA_RPC_URL" \
    --broadcast \
    "${gas_args[@]}" \
    "${verify_args[@]}" \
    "$@"
