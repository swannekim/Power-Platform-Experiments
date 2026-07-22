#!/usr/bin/env bash
# deploy.sh — export / pack / import helper for the Near-Miss Safety solution (bash).
# Requires the Power Platform CLI: dotnet tool install --global Microsoft.PowerApps.CLI.Tool
# Usage:
#   ./deploy.sh auth        https://<dev>.crm.dynamics.com
#   ./deploy.sh export      https://<dev>.crm.dynamics.com
#   ./deploy.sh pack-import https://<dev>.crm.dynamics.com
#   ./deploy.sh promote
set -euo pipefail

ACTION="${1:-pack-import}"
ENVURL="${2:-https://your-dev.crm.dynamics.com}"
SOLUTION="NearMissSafety"
SRC="src/solution/src"
OUT="out"
mkdir -p "$OUT"

case "$ACTION" in
  auth)
    pac auth create --environment "$ENVURL" ;;

  export)   # capture Studio changes back into source
    pac solution export --name "$SOLUTION" --path "$OUT/$SOLUTION.zip" --managed false --overwrite
    pac solution unpack --zipfile "$OUT/$SOLUTION.zip" --folder "$SRC" --packagetype Unmanaged --allowDelete ;;

  pack-import)   # build from source + import to Dev/Test
    pac solution pack --zipfile "$OUT/$SOLUTION.zip" --folder "$SRC" --packagetype Unmanaged
    pac solution import --path "$OUT/$SOLUTION.zip" --activate-plugins --force-overwrite
    pac solution publish ;;

  promote)   # managed build for Test/Prod (or use Pipelines)
    pac solution pack --zipfile "$OUT/${SOLUTION}_managed.zip" --folder "$SRC" --packagetype Managed
    echo "Managed solution at $OUT/${SOLUTION}_managed.zip — import via Pipelines or the target env." ;;

  *)
    echo "Unknown action: $ACTION" >&2; exit 1 ;;
esac
