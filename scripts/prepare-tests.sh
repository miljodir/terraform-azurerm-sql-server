#!/usr/bin/env bash
set -euo pipefail

# Run from the disposable module root before init, not in a production checkout.
if [[ -e network_vars_source_override.tf || -L network_vars_source_override.tf ]]; then
  echo "Refusing to overwrite an existing network_vars source override." >&2
  exit 1
fi

cp tests/source-overrides/network_vars_source_override.tf .
