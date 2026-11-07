# Testing

This module uses native Terraform and OpenTofu tests. The shared workflow runs
on every pull request to `main`, including forks and documentation-only changes,
on pushes to `main`, and manually. There are no path filters or repository secrets.

## What runs in CI

| Job      | Command                              | Purpose                                         |
| -------- | ------------------------------------ | ----------------------------------------------- |
| Format   | `terraform/tofu fmt -check -recursive` | Consistent formatting                          |
| Validate | `terraform/tofu init -backend=false` + `validate` | Prepared configuration syntax/types    |
| Test     | `terraform/tofu test -no-color`        | Module behaviour (defaults, wiring, validation) |

The caller pins Terraform 1.16.6 and OpenTofu 1.13.9 and runs both independently
in fresh disposable copies. Tests run only in GitHub Actions for CI verification.
The shared runner fails on absent tests, empty or entirely skipped suites, and
native test failures (including failures through its output pipeline).

The shared workflow is temporarily pinned to integration commit
`70a3d807d7a6d1969f8216c8c9e3a5108e892ddb` in `miljodir/workflow-templates`.
**Before landing, replace this with a durable merged commit or release ref.**

## How the tests work

- Test files live in `tests/` and end in `.tftest.hcl`.
- Every test file declares `mock_provider` blocks. Mocked providers never call
  Azure: no credentials are needed and **no real resources are created**.
  Resource attributes that Azure would compute (for example `id`) get generated
  fake values.
- Each `run` block plans (`command = plan`) or "applies" against the mocks
  (`command = apply`) with a set of input variables, then checks the result with
  `assert` blocks.
- Input validation is tested with `expect_failures`, which passes only when the
  listed variable validation or precondition fails.
- Data sources and nested modules that would need real lookups can be replaced
  with `override_data` / `override_module`.

- When tests run, the module is the *root* module. The engines then reject
  outputs that contain sensitive attributes unless they are marked
  `sensitive = true` (consumers calling the module are not affected). Put
  test-only override files in `tests/overrides/` named `*_override.tf`, e.g.

  ```hcl
  output "storage_account" {
    sensitive = true
  }
  ```

  Terraform installs sensitive-output overrides after validation and before tests.
  OpenTofu requires them before root-module validation as well. Always install
  them in the isolated copy, never in the production module root.

### Private dependency fixture

Mocking `module.network_vars` does not prevent its source from being downloaded
during initialization. `tests/source-overrides/network_vars_source_override.tf` redirects
that source to `tests/fixtures/network_vars`, a local interface-only module with
an empty `known_public_ips` map. The existing test override still supplies
documentation-range IP addresses; the development firewall assertions are retained.
No private module code or real network data is included.
Preparation fails if the expected module target or source/ref changes, so a future
dependency change requires an explicit fixture review rather than being hidden.
Only an exact, uncommented source assignment satisfies the source guard.
`bash scripts/test-prepare-tests.sh` runs in CI and locally to check the accepted
assignment and reject a changed live source even when the old source is commented.

**Validation with this override checks the fixture's interface, not the real
private dependency or compatibility with its implementation.** The public Azure
elastic-pool module is still downloaded and validated, although its outputs are
mocked during tests. Provider and public module downloads need internet access.

Both the source override and sensitive server-output override are test-only.
Normal consumers do not activate them, and production module behavior is unchanged.
Never plan or apply the isolated test configuration with real providers.

The shared workflow's `prepare-script: scripts/prepare-tests.sh` installs the
source override before initialization. Its
`test-override-directory: tests/overrides` installs the sensitive-output override
after Terraform validation but before OpenTofu validation. OpenTofu validation
therefore checks overridden output metadata, not the original root output metadata.
Both hooks run in the workflow's disposable copy.

These are unit-style tests: they verify how the module turns inputs into
resource configuration. They do not prove that Azure accepts the configuration;
that still happens when a consuming workload runs `terraform plan`/`apply`.

## Writing a test

```hcl
mock_provider "azurerm" {}

variables {
  resource_group_name = "rg-test"
}

run "defaults" {
  command = plan

  assert {
    condition     = azurerm_example.this.name == "expected"
    error_message = "Name should default to 'expected'."
  }
}

run "rejects_invalid_input" {
  command = plan

  variables {
    some_setting = "not-allowed"
  }

  expect_failures = [var.some_setting]
}
```

Guidelines:

- Add or update a test whenever you change behaviour, defaults or validation.
- Use obviously fake values (`rg-test`, `00000000-0000-0000-0000-000000000000`,
  documentation IP ranges such as `192.0.2.0/24`). Never use real subscription
  IDs, tenant IDs, names or addresses — this repository is public.
- Prefer one behaviour per `run` block with a descriptive name.

## Running locally

Requires Bash (for example Git Bash on Windows), internet access for public
downloads, and Terraform >= 1.9 and < 2.0. OpenTofu's test command supports the
same `.tftest.hcl` files, mocks and module overrides.
CI targets Terraform 1.16.6 and OpenTofu 1.13.9;
support for other versions is not established by these checks.

Mock/override values must target computed fields, not configured inputs.
For example, the existing resource group's `name` comes from
`resource_group_name`; it must not be redundantly overridden. OpenTofu rejects
that override, while the input and assertion already test the intended wiring.

Start from a clean checkout with no root-level overrides. In Bash, from the
repository root, run:

```bash
terraform fmt -check -recursive -diff
(
  set -euo pipefail
  # mkdir refuses to overwrite a previous test directory.
  mkdir .terraform-test
  trap 'rm -rf -- .terraform-test' EXIT
  # Copy configuration and synthetic tests, not tfvars, state or provider caches.
  cp ./*.tf .terraform-test/
  cp -R tests .terraform-test/tests
  cp -R scripts .terraform-test/scripts
  (
    cd .terraform-test
    bash scripts/prepare-tests.sh
    terraform init -backend=false
    terraform validate
    cp tests/overrides/*_override.tf .
    terraform test -no-color
  )
)
```

For OpenTofu 1.13.9, replace each `terraform` command with `tofu` and move
`cp tests/overrides/*_override.tf .` before `tofu validate`.
This suite has **12 run blocks** and should report `12 passed, 0 failed`.
Every provider is mocked, including apply-mode runs; no Azure credentials or SSH
key are required. Use only synthetic values in the isolated workspace.

The exit trap removes the installed source and sensitive-output overrides along
with downloaded dependencies and any mock state, including after test failures.
If a session is terminated before the trap runs, remove only `.terraform-test/`
before repeating the setup. If you followed the previous instructions and copied
`server_output_override.tf` into the production root, remove that specific copied
file first; preserve unrelated user overrides.

Use `terraform test -verbose` (or `tofu test -verbose`) only when deliberately
debugging synthetic test data; routine public CI should not print plans or state.
For a single file, use `-filter=tests/sql_server.tftest.hcl`; CI must run the full
suite and fail on absent tests, zero executed runs, or any failure.

### Applying the fixture mechanism to other modules

Use repository-specific `tests/source-overrides/*_override.tf` files to redirect private
module sources to minimal public-safe `tests/fixtures/` input/output interfaces.
Activate source overrides through `prepare-script` before `init` in an isolated
checkout, and install sensitive-output overrides via `test-override-directory`
(after Terraform validation, before OpenTofu validation).
Keep behavioral `override_module` assertions and document
which real dependency interfaces validation cannot verify. Do not change production
sources, copy private code, or introduce secrets into a public pull-request workflow.
