# SQL Server

[![Changelog](https://img.shields.io/badge/changelog-release-green.svg)](https://github.com/miljodir/terraform-azurerm-sql-server/wiki/main#changelog)
[![TF Registry](https://img.shields.io/badge/terraform-registry-blue.svg)](https://registry.terraform.io/modules/miljodir/sql-server/azurerm/)

Creates an Azure SQL Server with databases.
Optionally provisions an Azure SQL elastic pool for all module-managed databases by using the remote Azure AVM elasticpool submodule.
By default, local authentication and public network access is disabled.

## Elastic pool

Set `elastic_pool` to provision an elastic pool and place all databases from `databases` in that pool. Leave `elastic_pool = null` to preserve the existing single database compute behavior.

## Database defaults

Omitted and explicitly `null` database settings use the same defaults:

| Configuration | `min_capacity` | `auto_pause_delay_in_minutes` | `max_size_gb` |
| --- | --- | --- | --- |
| Standalone serverless (`GP_S` SKU, including the default `GP_S_Gen5_1`) | 0.5 | 60 | 50 |
| Provisioned or DTU SKU | Not sent | Not sent | 32 |
| Elastic-pool database (`ElasticPool` SKU) | Not sent | Not sent | 32 |

A database with `use_elastic_pool = false` uses standalone defaults even when the
module creates a pool. Pool-level `elastic_pool.max_size_gb` separately defaults
to 50; it is not the per-database limit.

Explicit applicable values are preserved, including `min_capacity = 0` and
`auto_pause_delay_in_minutes = -1` (disabled auto-pause). Pooled databases must
still omit database-specific compute settings.

Short-term retention defaults to 7 days with a 12-hour backup interval. These
defaults also apply to omitted/null fields within an empty or partially specified
`short_term_retention_policy` object; explicit fields are preserved.

These module defaults are now applied instead of passing null through to the
provider. Existing configurations that relied on provider-selected values may
therefore see database size, capacity or auto-pause changes in their next plan.
