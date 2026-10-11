#!/usr/bin/env bash
#
# Local Anvil deployment of the Henriable platform (see script/Deploy.s.sol).
# Deploys a MockUSDC and points Henriable at it.
#
# Usage:
#   ./script/deploy.sh [extra forge script flags...]

# Fail fast on errors, unset variables and failed pipes.
set -euo pipefail

# Resolve the project root (this script lives in script/) and work from there.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# Load .env so ANVIL_RPC_URL / ANVIL_PRIVATE_KEY are exported to forge.
if [ -f .env ]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
else
    echo "error: .env not found in $PROJECT_ROOT (copy .env.example to .env)" >&2
    exit 1
fi

# Make sure the two required variables are present.
: "${ANVIL_RPC_URL:?ANVIL_RPC_URL is not set (see .env.example)}"
: "${ANVIL_PRIVATE_KEY:?ANVIL_PRIVATE_KEY is not set (see .env.example)}"

# The Solidity script reads the deployer key from DEPLOYER_PRIVATE_KEY.
export DEPLOYER_PRIVATE_KEY="$ANVIL_PRIVATE_KEY"

# Local deploy always uses the mock USDC, so ignore any configured token address.
unset USDC_ADDRESS

# Deploy. Extra arguments passed to this script are forwarded to forge.
forge script script/Deploy.s.sol \
    --rpc-url "$ANVIL_RPC_URL" \
    --broadcast \
    "$@"
