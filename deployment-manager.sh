#!/usr/bin/env bash

set -e

declare -A SCRIPTS=(
    ["deploy"]="script/Deploy.s.sol:Deploy"
    ["deploy-production-environment"]="script/DeployProductionEnvironment.s.sol:DeployProductionEnvironment"
    ["deploy-home-omnichain-environment"]="script/DeployHomeOmnichainEnvironment.s.sol:DeployHomeOmnichainEnvironment"
    ["deploy-away-omnichain-environment"]="script/DeployAwayOmnichainEnvironment.s.sol:DeployAwayOmnichainEnvironment"
    ["upgrade-chip"]="script/UpgradeChip.s.sol:UpgradeChip"
    ["upgrade-staked-chip"]="script/UpgradeStakedChip.s.sol:UpgradeStakedChip"
    ["oadapter-set-rate-limits"]="script/OAdapterSetRateLimits.s.sol:OAdapterSetRateLimits"
    ["show"]="script/Show.s.sol:Show"
)

usage() {
    echo "Usage: $0 <command> [arguments...]"
    echo ""
    echo "Commands:"
    echo "  deploy <usdai> <treasury>"
    echo "  deploy-production-environment <deployer> <treasury> <admin>"
    echo "  deploy-home-omnichain-environment <deployer> <lz endpoint> <admin>"
    echo "  deploy-away-omnichain-environment <deployer> <lz endpoint> <admin>"
    echo ""
    echo "  upgrade-chip <usdai>"
    echo "  upgrade-staked-chip <usdai>"
    echo ""
    echo "  oadapter-set-rate-limits <oadapter> <dst eids> <limit> <window>"
    echo ""
    echo "  show"
}

# Check argument count
if [ "$#" -lt 1 ]; then
    usage
    exit 0
fi

# Check for NETWORK env var
if [[ -z "$NETWORK" ]]; then
    echo -e "Error: NETWORK env var missing.\n"
    usage
    exit 1
fi

# Check for <NETWORK>_RPC_URL env var
RPC_URL_VAR=${NETWORK^^}_RPC_URL
RPC_URL=${!RPC_URL_VAR}
if [[ -z "$RPC_URL" ]]; then
    echo -e "Error: $RPC_URL env var missing.\n"
    usage
    exit 1
fi

# Look up script
SCRIPT=${SCRIPTS[$1]}
if [[ -z "$SCRIPT" ]]; then
    echo -e "Error: unknown command \"$1\"\n"
    usage
    exit 1
fi

# Look up script signature
SIGNATURE=$(forge inspect --no-cache --contracts script "$SCRIPT" mi --json | grep -o "run(.*)")

echo -e "Running on $NETWORK\n"

if [[ ! -z "$LEDGER_DERIVATION_PATH" ]]; then
    forge script --rpc-url "$RPC_URL" --ledger --hd-paths "$LEDGER_DERIVATION_PATH" --sender "$LEDGER_ADDRESS" --broadcast -vvvv "$SCRIPT" --sig "$SIGNATURE" "${@:2}"
elif [[ ! -z "$PRIVATE_KEY" ]]; then
    forge script --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --sender "$(cast wallet address "$PRIVATE_KEY")" --broadcast -vvvv "$SCRIPT" --sig "$SIGNATURE" "${@:2}"
else
    forge script --rpc-url "$RPC_URL" -vvvv "$SCRIPT" --sig "$SIGNATURE" "${@:2}"
fi
