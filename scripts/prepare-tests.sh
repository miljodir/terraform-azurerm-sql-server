#!/usr/bin/env bash
set -euo pipefail

# Run from the disposable module root before init, not in a production checkout.
expected_source='git@github.com:miljodir/cp-shared.git//modules/public_nw_ips?ref=public_nw_ips/v1'
target_count=$(awk '/^[[:space:]]*module[[:space:]]+"network_vars"[[:space:]]*\{/ { total++ } END { print total + 0 }' ./*.tf)
source_block=$(sed -n '/^module "network_vars" {$/,/^}$/p' main.tf)
source_count=$(printf '%s\n' "$source_block" | awk -v expected="source = \"$expected_source\"" '
  {
    sub(/^[[:space:]]+/, "")
    sub(/[[:space:]]+$/, "")
    if ($0 == expected) total++
  }
  END { print total + 0 }
')
if [[ "$target_count" != 1 || "$source_count" != 1 ]]; then
  echo "The network_vars target or source/ref changed; review the test fixture before substituting it." >&2
  exit 1
fi

if [[ -e network_vars_source_override.tf || -L network_vars_source_override.tf ]]; then
  echo "Refusing to overwrite an existing network_vars source override." >&2
  exit 1
fi

cp tests/source-overrides/network_vars_source_override.tf .
