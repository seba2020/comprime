#!/bin/zsh
set -eu
project_root="${0:A:h:h}"
"$project_root/scripts/build-local.sh"
"$project_root/.build-cache/build/debug/SmokeChecks" "$project_root/fixtures/generated"
