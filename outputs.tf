output "server" {
  description = "The SQL Server resource"
  value       = azurerm_mssql_server.sqlsrv
}

output "elastic_pool" {
  description = "The SQL elastic pool resource when created."
  value       = local.elastic_pool_enabled == true ? module.elastic_pool[0].resource : null
}

output "elastic_pool_id" {
  description = "The SQL elastic pool resource ID when created."
  value       = local.elastic_pool_enabled == true ? module.elastic_pool[0].resource_id : null
}

output "private_ip" {
  description = "The database private IP if created."
  value       = var.create_private_endpoint == true ? azurerm_private_endpoint.sqlsrv_pe[0].private_service_connection[0].private_ip_address : ""
}

locals {
  possible_group_name = "aks rbac ns ${split("-", local.name_prefix)[0]}-aks-${split("-", local.name_prefix)[1]} workload identities"
}

output "access_script" {
  description = "The script to grant your application access the database. This is currently done manually by a member of the ${azurerm_mssql_server.sqlsrv.azuread_administrator[1].login_username} Entra group. The group name not necessarily correct for your situation"
  value       = <<-EOT
    CREATE USER [${local.possible_group_name}] FROM EXTERNAL PROVIDER; ALTER ROLE db_owner ADD MEMBER [${local.possible_group_name}];
  EOT
}