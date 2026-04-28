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
