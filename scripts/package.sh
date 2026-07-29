#!/usr/bin/env bash
# Build the single current LeoMacMonitor release artifact.
# Auto-update metadata and appcasts are intentionally not produced: releases are installed
# manually so this branded build can never be replaced by another project's update channel.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-2.2.1}"
exec scripts/build-dmg.sh "$VERSION"
