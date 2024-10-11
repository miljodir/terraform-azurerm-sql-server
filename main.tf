locals {
  name_prefix         = data.azurerm_subscription.current.display_name
  resource_group_name = var.create_resource_group == true ? azurerm_resource_group.sql[0].name : data.azurerm_resource_group.rg[0].name
  unique              = var.unique == null ? random_string.unique[0].result : var.unique
  enable_local_auth   = var.azuread_administrator[0].azuread_authentication_only == true ? false : true
  server_name         = var.server_name != null ? var.server_name : "${local.name_prefix}-sql${local.unique}-sqlsvr"
}

data "azurerm_subscription" "current" {}


resource "random_password" "password" {
  count            = local.enable_local_auth == true ? 1 : 0
  length           = var.password_length
  special          = true
  override_special = "_%@"
}

data "azurerm_resource_group" "rg" {
  count = var.create_resource_group == false ? 1 : 0
  name  = var.resource_group_name
}

resource "random_string" "unique" {
  count   = var.unique == null ? 1 : 0
  length  = 6
  special = false
  upper   = false
  numeric = true
}

resource "azurerm_resource_group" "sql" {
  count    = var.create_resource_group == true ? 1 : 0
  name     = "${local.name_prefix}-sql"
  location = var.location
  lifecycle {
    ignore_changes = [tags]
  }
}

resource "azurerm_mssql_server" "sqlsrv" {
  administrator_login                          = local.enable_local_auth ? var.admin_username : null
  administrator_login_password                 = local.enable_local_auth ? random_password.password[0].result : null
  location                                     = var.location
  name                                         = local.server_name
  resource_group_name                          = local.resource_group_name
  minimum_tls_version                          = var.minimum_tls_version
  version                                      = "12.0"
  transparent_data_encryption_key_vault_key_id = var.transparent_data_encryption_key_vault_key_id != null ? var.transparent_data_encryption_key_vault_key_id : null

  public_network_access_enabled = var.publicly_available

  dynamic "azuread_administrator" {
    for_each = var.azuread_administrator[0].login_username != "" ? [1] : []
    # Only 1 or 0 of this block is supported. Always use index 0 of azuread_administrator block if supplied
    content {
      azuread_authentication_only = var.azuread_administrator[0].azuread_authentication_only
      login_username              = var.azuread_administrator[0].login_username
      object_id                   = var.azuread_administrator[0].object_id
      tenant_id                   = var.azuread_administrator[0].tenant_id
    }
  }

  dynamic "identity" {
    for_each = var.create_managed_identity == true ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }
}

resource "azurerm_mssql_database" "db" {
  for_each = var.databases

  # Since sku_names now determine server type, we need to compute the type here.
  # Serverless will always have GP_S_xx, and we can therefore deduce this from splitting by underscore.
  # License type not allowed for serverless databases
  name                        = each.key
  server_id                   = azurerm_mssql_server.sqlsrv.id
  sku_name                    = each.value.sku_name != null ? each.value.sku_name : "GP_S_Gen5_1"
  min_capacity                = !startswith(each.value.sku_name, "GP_S") ? 0 : try(each.value.min_capacity, 0.5)
  auto_pause_delay_in_minutes = !startswith(each.value.sku_name, "GP_S") ? 0 : try(each.value.auto_pause_delay_in_minutes, 30)
  storage_account_type        = each.value.storage_account_type != null ? each.value.storage_account_type : "Local"
  license_type                = each.value.capacity_unit == "Provisioned" && each.value.license_type != null ? each.value.license_type : null
  collation                   = each.value.collation != null ? each.value.collation : "Danish_Norwegian_CI_AS"
  max_size_gb                 = !startswith(each.value.sku_name, "GP_S") ? try(each.value.max_size_gb, 32) : try(each.value.max_size_gb, 50)
  create_mode                 = each.value.create_mode
  creation_source_database_id = each.value.create_mode != "Default" && each.value.creation_source_database_id != null ? each.value.creation_source_database_id : null
  enclave_type                = each.value.create_mode == "Copy" ? "Default" : null

  restore_point_in_time = each.value.create_mode == "PointInTimeRestore" && each.value.restore_point_in_time != null ? each.value.restore_point_in_time : null
  dynamic "long_term_retention_policy" {
    # Long term retention policy not allowed for serverless databases with auto-pause enabled.
    # Therefore the "hacky" determination of enabling LTR or not.
    # This logic will enable LTR by default if supported.
    for_each = each.value.capacity_unit == "Provisioned" || each.value.auto_pause_delay_in_minutes == -1 ? ["true"] : []
    content {
      monthly_retention = lookup(long_term_retention_policy, "monthly_retention", "P6M")
      week_of_year      = lookup(long_term_retention_policy, "week_of_year", 1)
      weekly_retention  = lookup(long_term_retention_policy, "weekly_retention", "P1M")
      yearly_retention  = lookup(long_term_retention_policy, "yearly_retention", "P5Y")
    }
  }

  short_term_retention_policy {
    retention_days           = each.value.short_term_retention_policy == null ? 7 : each.value.short_term_retention_policy.retention_days
    backup_interval_in_hours = each.value.short_term_retention_policy == null ? 12 : each.value.short_term_retention_policy.backup_interval_in_hours
  }
}

resource "azurerm_mssql_firewall_rule" "sql" {
  for_each         = var.firewall_rules
  name             = each.key
  server_id        = azurerm_mssql_server.sqlsrv.id
  start_ip_address = each.value.start_ip_address
  end_ip_address   = each.value.end_ip_address
}

resource "azurerm_private_endpoint" "sqlsrv_pe" {
  count               = var.create_private_endpoint == true ? 1 : 0
  location            = azurerm_mssql_server.sqlsrv.location
  name                = "${azurerm_mssql_server.sqlsrv.name}-pe"
  resource_group_name = local.resource_group_name
  subnet_id           = var.subnet_id
  private_service_connection {
    is_manual_connection           = false
    name                           = "${azurerm_mssql_server.sqlsrv.name}-pe"
    private_connection_resource_id = azurerm_mssql_server.sqlsrv.id
    subresource_names              = ["sqlServer"]
  }
}

resource "azurerm_private_dns_a_record" "sqlsrv_pe_dns" {
  count = var.create_private_endpoint == true ? 1 : 0
  name  = azurerm_mssql_server.sqlsrv.name
  records = [
    azurerm_private_endpoint.sqlsrv_pe[0].private_service_connection[0].private_ip_address
  ]
  resource_group_name = var.dns_resource_group_name
  ttl                 = 600
  zone_name           = "privatelink.database.windows.net"

  provider = azurerm.p-dns
}
