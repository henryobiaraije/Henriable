#!/usr/bin/env bash
#
# Sepolia testnet deployment of the Henriable platform (see script/Deploy.s.sol).
# Uses the real Circle USDC on Sepolia and verifies the contract on Etherscan
# when an ETHERSCAN_API_KEY is configured.
#
# Usage:
#   ./script/deploy-sepolia.sh [extra forge script flags...]

# Fail fast on errors, unset variables and failed pipes.
set -euo pipefail

# Resolve the project root (this script lives in script/) and work from there.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

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

# Verify on Etherscan when an API key is available.
verify_args=()
if [ -n "${ETHERSCAN_API_KEY:-}" ]; then
    verify_args=(--verify --etherscan-api-key "$ETHERSCAN_API_KEY")
fi

# Deploy. Extra arguments passed to this script are forwarded to forge.
forge script script/Deploy.s.sol \
    --rpc-url "$SEPOLIA_RPC_URL" \
    --broadcast \
    "${verify_args[@]}" \
    "$@"
