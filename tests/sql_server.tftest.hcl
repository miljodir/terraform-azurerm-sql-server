mock_provider "azurerm" {
  mock_data "azurerm_subscription" {
    defaults = {
      display_name = "p-test"
    }
  }

  # Generated mock IDs are random strings; resources that parse IDs need a real-looking one.
  mock_resource "azurerm_mssql_server" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/p-test-sql/providers/Microsoft.Sql/servers/p-test-sqlabc123-sqlsvr"
    }
  }
}

mock_provider "random" {}

# The internal public IP module is replaced with documentation-range addresses.
override_module {
  target = module.network_vars
  outputs = {
    known_public_ips = {
      office = "192.0.2.10"
      vpn    = "198.51.100.20"
    }
  }
}

# The external elastic pool module is not under test here.
override_module {
  target = module.elastic_pool
  outputs = {
    resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/p-test-sql/providers/Microsoft.Sql/servers/p-test-sqlabc123-sqlsvr/elasticPools/pool"
    resource    = {}
  }
}

variables {
  unique    = "abc123"
  subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-pe"
  azuread_administrator = [{
    login_username = "sql-admins-test"
    object_id      = "00000000-0000-0000-0000-000000000001"
    tenant_id      = "00000000-0000-0000-0000-000000000000"
  }]
}

run "defaults" {
  command = plan

  assert {
    condition     = azurerm_resource_group.sql[0].name == "p-test-sql"
    error_message = "Resource group should be named '<subscription>-sql'."
  }

  assert {
    condition     = azurerm_mssql_server.sqlsrv.name == "p-test-sqlabc123-sqlsvr"
    error_message = "Server name should be '<subscription>-sql<unique>-sqlsvr'."
  }

  assert {
    condition     = azurerm_mssql_server.sqlsrv.minimum_tls_version == "1.2"
    error_message = "Minimum TLS should default to 1.2."
  }

  assert {
    condition     = azurerm_mssql_server.sqlsrv.public_network_access_enabled == false
    error_message = "Public network access should be disabled by default outside development."
  }

  assert {
    condition     = azurerm_mssql_server.sqlsrv.azuread_administrator[0].azuread_authentication_only == true
    error_message = "Entra ID only authentication should be enabled by default."
  }

  assert {
    condition     = length(random_password.password) == 0
    error_message = "No local administrator should be created with Entra ID only authentication."
  }

  assert {
    condition     = azurerm_mssql_server.sqlsrv.express_vulnerability_assessment_enabled == true
    error_message = "Express vulnerability assessment should always be enabled in production subscriptions."
  }

  assert {
    condition     = length(azurerm_mssql_server.sqlsrv.identity) == 0
    error_message = "No managed identity should be created by default."
  }

  assert {
    condition     = length(module.network_vars) == 0 && length(azurerm_mssql_firewall_rule.known_pips) == 0
    error_message = "Known public IPs should only be allowed in development."
  }

  assert {
    condition     = length(module.elastic_pool) == 0
    error_message = "No elastic pool should be created by default."
  }

  assert {
    condition     = length(azurerm_private_endpoint.sqlsrv_pe) == 1
    error_message = "A private endpoint should be created by default."
  }
}

run "default_database" {
  command = plan

  assert {
    condition     = keys(azurerm_mssql_database.db) == ["defaultdb"]
    error_message = "A single 'defaultdb' database should be created by default."
  }

  assert {
    condition     = azurerm_mssql_database.db["defaultdb"].sku_name == "GP_S_Gen5_1"
    error_message = "Databases should default to serverless GP_S_Gen5_1."
  }


  assert {
    condition     = azurerm_mssql_database.db["defaultdb"].collation == "Danish_Norwegian_CI_AS"
    error_message = "Collation should default to Danish_Norwegian_CI_AS."
  }

  assert {
    condition     = azurerm_mssql_database.db["defaultdb"].storage_account_type == "Geo"
    error_message = "Production subscriptions should use geo-redundant backup storage."
  }

  assert {
    condition     = length(azurerm_mssql_database.db["defaultdb"].long_term_retention_policy) == 0
    error_message = "Long term retention is not supported for auto-pausing serverless databases."
  }

  assert {
    condition     = azurerm_mssql_database.db["defaultdb"].short_term_retention_policy[0].retention_days == 7
    error_message = "Short term retention should default to 7 days."
  }
}

run "non_production_defaults" {
  command = plan

  override_data {
    target = data.azurerm_subscription.current
    values = {
      display_name = "t-test"
    }
  }

  assert {
    condition     = azurerm_mssql_database.db["defaultdb"].storage_account_type == "Local"
    error_message = "Non-production subscriptions should use locally redundant backup storage."
  }

  assert {
    condition     = azurerm_mssql_server.sqlsrv.express_vulnerability_assessment_enabled == false
    error_message = "Express vulnerability assessment should be opt-in outside production."
  }

  assert {
    condition     = azurerm_mssql_server.sqlsrv.public_network_access_enabled == false
    error_message = "Public network access should stay disabled outside development."
  }
}

run "development_allows_known_public_ips" {
  command = apply

  override_data {
    target = data.azurerm_subscription.current
    values = {
      display_name = "d-test"
    }
  }

  assert {
    condition     = azurerm_mssql_server.sqlsrv.public_network_access_enabled == true
    error_message = "Development subscriptions should enable public access for known IPs."
  }

  assert {
    condition     = toset(keys(azurerm_mssql_firewall_rule.known_pips)) == toset(["office", "vpn"])
    error_message = "A firewall rule should be created per known public IP."
  }

  assert {
    condition     = azurerm_mssql_firewall_rule.known_pips["office"].start_ip_address == "192.0.2.10" && azurerm_mssql_firewall_rule.known_pips["office"].end_ip_address == "192.0.2.10"
    error_message = "Known public IP firewall rules should cover a single address."
  }
}

run "local_authentication" {
  command = apply

  variables {
    azuread_administrator = [{
      azuread_authentication_only = false
      login_username              = "sql-admins-test"
      object_id                   = "00000000-0000-0000-0000-000000000001"
      tenant_id                   = "00000000-0000-0000-0000-000000000000"
    }]
  }

  assert {
    condition     = azurerm_mssql_server.sqlsrv.administrator_login == "sqlserveradmin"
    error_message = "Local administrator should be created when Entra ID only authentication is disabled."
  }

  assert {
    condition     = length(random_password.password) == 1 && random_password.password[0].length == 16
    error_message = "A 16 character administrator password should be generated."
  }
}

run "existing_resource_group_and_names" {
  command = plan

  variables {
    create_resource_group = false
    resource_group_name   = "rg-existing"
    server_name           = "sql-custom-name"
  }

  assert {
    condition     = length(azurerm_resource_group.sql) == 0
    error_message = "No resource group should be created when create_resource_group = false."
  }

  assert {
    condition     = azurerm_mssql_server.sqlsrv.resource_group_name == "rg-existing"
    error_message = "The existing resource group should be used."
  }

  assert {
    condition     = azurerm_mssql_server.sqlsrv.name == "sql-custom-name"
    error_message = "server_name should override the generated name."
  }
}

run "provisioned_database" {
  command = plan

  variables {
    databases = {
      appdb = {
        sku_name      = "GP_Gen5_2"
        capacity_unit = "Provisioned"
        license_type  = "BasePrice"
      }
    }
  }


  assert {
    condition     = azurerm_mssql_database.db["appdb"].license_type == "BasePrice"
    error_message = "License type should be passed through for provisioned databases."
  }


  assert {
    condition     = azurerm_mssql_database.db["appdb"].long_term_retention_policy[0].weekly_retention == "P1M" && azurerm_mssql_database.db["appdb"].long_term_retention_policy[0].yearly_retention == "P5Y"
    error_message = "Provisioned databases should get the default long term retention policy."
  }
}

run "elastic_pool" {
  command = apply

  variables {
    elastic_pool = {}
    databases = {
      pooled     = {}
      standalone = { use_elastic_pool = false }
    }
  }

  assert {
    condition     = length(module.elastic_pool) == 1
    error_message = "An elastic pool should be created when elastic_pool is set."
  }

  assert {
    condition     = azurerm_mssql_database.db["pooled"].elastic_pool_id == output.elastic_pool_id
    error_message = "Databases should be placed in the elastic pool by default."
  }

  assert {
    condition     = azurerm_mssql_database.db["pooled"].sku_name == "ElasticPool"
    error_message = "Pooled databases should use the ElasticPool SKU."
  }

  assert {
    condition     = azurerm_mssql_database.db["standalone"].elastic_pool_id == null && azurerm_mssql_database.db["standalone"].sku_name == "GP_S_Gen5_1"
    error_message = "Databases that opt out should stay standalone serverless."
  }
}

run "pooled_database_rejects_custom_sku" {
  command = plan

  variables {
    elastic_pool = {}
    databases = {
      pooled = { sku_name = "GP_Gen5_2" }
    }
  }

  expect_failures = [azurerm_mssql_database.db]
}

run "network_rules" {
  command = plan

  variables {
    create_private_endpoint = false
    firewall_rules = {
      partner = {
        start_ip_address = "203.0.113.1"
        end_ip_address   = "203.0.113.10"
      }
    }
    virtual_network_rules = {
      app = {
        subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-app"
      }
    }
  }

  assert {
    condition     = azurerm_mssql_firewall_rule.sql["partner"].start_ip_address == "203.0.113.1"
    error_message = "Firewall rules should be passed through."
  }

  assert {
    condition     = length(azurerm_mssql_virtual_network_rule.sql) == 1
    error_message = "Virtual network rules should be created."
  }

  assert {
    condition     = length(azurerm_private_endpoint.sqlsrv_pe) == 0 && output.private_ip == ""
    error_message = "No private endpoint should be created when disabled."
  }
}

run "invalid_tls_version_is_rejected" {
  command = plan

  variables {
    minimum_tls_version = "1.3"
  }

  expect_failures = [var.minimum_tls_version]
}

run "invalid_unique_is_rejected" {
  command = plan

  variables {
    unique = "abc"
  }

  expect_failures = [var.unique]
}

run "omitted_and_null_database_defaults" {
  command = apply

  variables {
    databases = {
      serverless = {}
      serverless_null = {
        sku_name                    = "GP_S_Gen5_1"
        min_capacity                = null
        auto_pause_delay_in_minutes = null
        max_size_gb                 = null
      }
      provisioned = { sku_name = "GP_Gen5_2" }
      provisioned_null = {
        sku_name                    = "GP_Gen5_2"
        min_capacity                = null
        auto_pause_delay_in_minutes = null
        max_size_gb                 = null
      }
      dtu = { sku_name = "S0" }
      dtu_null = {
        sku_name                    = "S0"
        min_capacity                = null
        auto_pause_delay_in_minutes = null
        max_size_gb                 = null
      }
    }
  }

  assert {
    condition = alltrue([
      for name in ["serverless", "serverless_null"] :
      azurerm_mssql_database.db[name].min_capacity == 0.5 &&
      azurerm_mssql_database.db[name].auto_pause_delay_in_minutes == 60 &&
      azurerm_mssql_database.db[name].max_size_gb == 50
    ])
    error_message = "Omitted/null standalone serverless settings must default to 0.5 vCore, 60 minutes and 50 GB."
  }

  assert {
    condition = alltrue([
      for name in ["provisioned", "provisioned_null", "dtu", "dtu_null"] :
      azurerm_mssql_database.db[name].min_capacity == 0 &&
      azurerm_mssql_database.db[name].auto_pause_delay_in_minutes == 0 &&
      azurerm_mssql_database.db[name].max_size_gb == 32
    ])
    error_message = "Non-serverless SKUs must retain provider-normalized zero compute settings and default to 32 GB."
  }
}

run "explicit_database_values" {
  command = plan

  variables {
    databases = {
      zero_capacity = {
        min_capacity                = 0
        auto_pause_delay_in_minutes = -1
        max_size_gb                 = 64
      }
      serverless = {
        sku_name                    = "GP_S_Gen5_2"
        min_capacity                = 1
        auto_pause_delay_in_minutes = 120
        max_size_gb                 = 75
      }
      provisioned = {
        sku_name                    = "GP_Gen5_2"
        capacity_unit               = "Provisioned"
        min_capacity                = 1
        auto_pause_delay_in_minutes = 120
        max_size_gb                 = 128
      }
      dtu = {
        sku_name    = "S0"
        max_size_gb = 10
      }
    }
  }

  assert {
    condition = (
      azurerm_mssql_database.db["zero_capacity"].min_capacity == 0 &&
      azurerm_mssql_database.db["zero_capacity"].auto_pause_delay_in_minutes == -1 &&
      azurerm_mssql_database.db["zero_capacity"].max_size_gb == 64 &&
      length(azurerm_mssql_database.db["zero_capacity"].long_term_retention_policy) == 1
    )
    error_message = "Explicit zero capacity and disabled auto-pause must be preserved, including LTR eligibility."
  }

  assert {
    condition = (
      azurerm_mssql_database.db["serverless"].min_capacity == 1 &&
      azurerm_mssql_database.db["serverless"].auto_pause_delay_in_minutes == 120 &&
      azurerm_mssql_database.db["serverless"].max_size_gb == 75 &&
      length(azurerm_mssql_database.db["serverless"].long_term_retention_policy) == 0
    )
    error_message = "Explicit serverless settings must be preserved."
  }

  assert {
    condition = (
      azurerm_mssql_database.db["provisioned"].min_capacity == 0 &&
      azurerm_mssql_database.db["provisioned"].auto_pause_delay_in_minutes == 0 &&
      azurerm_mssql_database.db["provisioned"].max_size_gb == 128 &&
      azurerm_mssql_database.db["dtu"].max_size_gb == 10
    )
    error_message = "Explicit sizes must be preserved for non-serverless SKUs without enabling serverless compute."
  }
}

run "pooled_and_opt_out_database_defaults" {
  command = apply

  variables {
    elastic_pool = {}
    databases = {
      pooled = {}
      pooled_null = {
        sku_name                    = "ElasticPool"
        min_capacity                = null
        auto_pause_delay_in_minutes = null
        max_size_gb                 = null
      }
      pooled_explicit = { max_size_gb = 64 }
      standalone      = { use_elastic_pool = false }
      standalone_null = {
        use_elastic_pool            = false
        min_capacity                = null
        auto_pause_delay_in_minutes = null
        max_size_gb                 = null
      }
    }
  }

  assert {
    condition = alltrue([
      for name in ["pooled", "pooled_null", "pooled_explicit"] :
      azurerm_mssql_database.db[name].elastic_pool_id == output.elastic_pool_id &&
      azurerm_mssql_database.db[name].min_capacity == 0 &&
      azurerm_mssql_database.db[name].auto_pause_delay_in_minutes == 0 &&
      azurerm_mssql_database.db[name].max_size_gb == (name == "pooled_explicit" ? 64 : 32)
    ])
    error_message = "Pooled databases must omit serverless compute and use 32 GB unless a size is explicitly supplied."
  }

  assert {
    condition = alltrue([
      for name in ["standalone", "standalone_null"] :
      azurerm_mssql_database.db[name].elastic_pool_id == null &&
      azurerm_mssql_database.db[name].min_capacity == 0.5 &&
      azurerm_mssql_database.db[name].auto_pause_delay_in_minutes == 60 &&
      azurerm_mssql_database.db[name].max_size_gb == 50
    ])
    error_message = "Pool opt-outs must retain standalone serverless defaults for omitted/null settings."
  }
}

run "short_term_retention_defaults_and_explicit_values" {
  command = plan

  variables {
    databases = {
      omitted = {}
      null    = { short_term_retention_policy = null }
      empty   = { short_term_retention_policy = {} }
      null_fields = {
        short_term_retention_policy = {
          retention_days           = null
          backup_interval_in_hours = null
        }
      }
      retention_only = { short_term_retention_policy = { retention_days = 14 } }
      interval_only  = { short_term_retention_policy = { backup_interval_in_hours = 24 } }
      explicit = {
        short_term_retention_policy = {
          retention_days           = 21
          backup_interval_in_hours = 24
        }
      }
    }
  }

  assert {
    condition = alltrue([
      for name in ["omitted", "null", "empty", "null_fields", "retention_only", "interval_only", "explicit"] :
      azurerm_mssql_database.db[name].short_term_retention_policy[0].retention_days == (name == "explicit" ? 21 : name == "retention_only" ? 14 : 7) &&
      azurerm_mssql_database.db[name].short_term_retention_policy[0].backup_interval_in_hours == (contains(["explicit", "interval_only"], name) ? 24 : 12)
    ])
    error_message = "Short-term retention must default missing/null fields to 7 days and 12 hours while preserving explicit fields."
  }
}
