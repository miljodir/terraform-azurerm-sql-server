#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
workspace=$(mktemp -d)
trap 'rm -rf -- "$workspace"' EXIT
cd "$workspace"
mkdir -p tests/source-overrides
cp "$root/tests/source-overrides/network_vars_source_override.tf" tests/source-overrides/

expected_source='git@github.com:miljodir/cp-shared.git//modules/public_nw_ips?ref=public_nw_ips/v1'
printf 'module "network_vars" {\n  source = "%s"\n}\n' "$expected_source" > main.tf
bash "$root/scripts/prepare-tests.sh"
test -f network_vars_source_override.tf
rm network_vars_source_override.tf

printf 'module "network_vars" {\n  source = "%s"\n  # source = "%s"\n}\n' \
  "${expected_source%/v1}/v2" "$expected_source" > main.tf
if bash "$root/scripts/prepare-tests.sh"; then
  echo "Changed live source with a commented old source was incorrectly accepted." >&2
  exit 1
fi
test ! -e network_vars_source_override.tf
echo "Preparation accepts the exact live source and rejects a changed source with a commented old assignment."
