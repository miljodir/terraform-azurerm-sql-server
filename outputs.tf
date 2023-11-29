output "server" {
  description = "The SQL Server resource"
  value       = azurerm_mssql_server.sqlsrv
}

output "private_ip" {
  description = "The database private IP if created."
  value       = var.create_private_endpoint == true ? azurerm_private_endpoint.sqlsrv_pe[0].private_service_connection[0].private_ip_address : ""
}
