# Activated by scripts/prepare-tests.sh before initialization in the test copy.
module "network_vars" {
  source = "./tests/fixtures/network_vars"
}
