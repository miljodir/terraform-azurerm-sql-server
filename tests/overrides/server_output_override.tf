# Test-only: the server output contains the administrator password. Terraform
# requires root module outputs with sensitive values to be marked sensitive,
# which only matters when the module itself is the root module (terraform test).
output "server" {
  sensitive = true
}
