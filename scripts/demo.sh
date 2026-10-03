#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$TASK_ROOT/scripts/build.sh"
python3 "$TASK_ROOT/scripts/create-demo.py"
MISSENV_DEMO_ROOT="$TASK_ROOT/work/demo" \
MISSENV_REGISTRY="$TASK_ROOT/work/demo-registry.json" \
"$TASK_ROOT/build/MissEnv.app/Contents/MacOS/MissEnv" --demo
