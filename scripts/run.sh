#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$TASK_ROOT/scripts/build.sh"
open "$TASK_ROOT/build/MissEnv.app"
