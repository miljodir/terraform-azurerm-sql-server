# SQL Server

[![Changelog](https://img.shields.io/badge/changelog-release-green.svg)](https://github.com/miljodir/terraform-azurerm-sql-server/wiki/main#changelog)
[![TF Registry](https://img.shields.io/badge/terraform-registry-blue.svg)](https://registry.terraform.io/modules/miljodir/sql-server/azurerm/)

Creates an Azure SQL Server with databases.
Optionally provisions an Azure SQL elastic pool for all module-managed databases by using the remote Azure AVM elasticpool submodule.
By default, local authentication and public network access is disabled.

## Elastic pool

Set `elastic_pool` to provision an elastic pool and place all databases from `databases` in that pool. Leave `elastic_pool = null` to preserve the existing single database compute behavior.
