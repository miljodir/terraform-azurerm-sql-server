variable "resource_group_name" {
  type        = string
  description = "Resource Group Name where resources should be placed. Defaults to auto-generated name for creating rg."
  default     = null
}

variable "dns_resource_group_name" {
  type        = string
  description = "Resource Group Name where DNS zone is located."
  default     = "p-dns-pri"
}

variable "server_name" {
  type        = string
  description = "Name of the SQL server. Defaults to auto-generated name."
  default     = null
}

variable "create_resource_group" {
  type        = bool
  description = "Create resource group? Defaults to true."
  default     = true
}

variable "subnet_id" {
  type        = string
  description = "Virtual Network subnet id where private endpoints should be created."
}

variable "create_private_endpoint" {
  type        = bool
  description = "Create private endpoint for the SQL server? Defaults to true."
  default     = true
}

variable "location" {
  type        = string
  description = "Location for all resources involved."
  default     = "norwayeast"
}

variable "publicly_available" {
  type        = bool
  description = "Should SQL server be publicly available? Defaults to false."
  default     = false
}

variable "admin_username" {
  type        = string
  description = "Admin username for SQL server. Defaults to 'sqlserveradmin'."
  default     = "sqlserveradmin"
}

variable "minimum_tls_version" {
  type        = string
  description = "Minimum TLS version the SQL server supports. Valid values 1.0, 1.1, 1.2. Defaults to 1.2 (preferred)."
  default     = "1.2"

  validation {
    condition     = (contains(["1.0", "1.1", "1.2"], var.minimum_tls_version))
    error_message = "Valid values are '1.0', '1.1', or '1.2'."
  }
}

variable "create_managed_identity" {
  type        = bool
  description = "Create system assigned managed identity for SQL server? Defaults to false."
  default     = false
}

variable "transparent_data_encryption_key_vault_key_id" {
  type        = string
  description = "The Key Vault Key ID to use for Transparent Data Encryption. Defaults to null."
  default     = null
}

variable "azuread_administrator" {
  type = list(object({
    azuread_authentication_only = optional(bool, true)
    login_username              = optional(string, "MDIR SQL Admins PIM")
    object_id                   = optional(string, "0820ef72-b3ef-4b39-aebd-1d1912ef0df9")
    tenant_id                   = optional(string, "f999e2e9-5aa8-467f-9eca-df0d6c4eaf13")
  }))
  default = [{
    azuread_authentication_only = true
    login_username              = "MDIR SQL Admins PIM"
    object_id                   = "0820ef72-b3ef-4b39-aebd-1d1912ef0df9"
    tenant_id                   = "f999e2e9-5aa8-467f-9eca-df0d6c4eaf13"
  }]
}

variable "unique" {
  type        = string
  description = "Provide a unique string if you want to use an already generated one."
  default     = null

  validation {
    condition     = length(var.unique == null ? "123456" : var.unique) == 6
    error_message = "Unique string must be exactly 6 chars long."
  }
}

variable "firewall_rules" {
  type = map(object({
    start_ip_address = optional(string)
    end_ip_address   = optional(string)
  }))
  description = "Map of objects containing information on firewall rules to be created."
  default     = {}
}

variable "databases" {
  type = map(object({
    sku_name                    = optional(string),           # Sku name for database. Many possibilities .Defaults to "GP_S_Gen5_1" which means serverless 1 vcore.
    min_capacity                = optional(number),           # Minimum capacity for serverless type capacity. Defaults to 0.5.
    auto_pause_delay_in_minutes = optional(number),           # Time in minutes after which database is automatically paused. A value of -1 means that automatic pause is disabled. Defaults to 60.
    storage_account_type        = optional(string),           # Storage account type for database backup. Possible values are Geo, GeoZone, Local and Zone. Defaults to Local.
    license_type                = optional(string),           # License type for hybrid benefit. LicenseIncluded (regular) or BasePrice(Hybrid benefit). Defaults to LicenseIncluded.
    collation                   = optional(string),           # Collation for database. Defaults to "Danish_Norwegian_CI_AS".
    max_size_gb                 = optional(number),           # Number of gigabytes database size. Defaults to 50.
    capacity_unit               = optional(string),           # The capacity unit for database. Either Serverless or Provisioned. Only applicable if using vCore server type. Defaults to Serverless.
    creation_source_database_id = optional(string),           # The resource ID of the source database if create_mode is not Default. Defaults to null.
    create_mode                 = optional(string, "Default") # The creation mode of the database. Defaults to Default.
    restore_point_in_time       = optional(string),           # The point in time to restore from if create_mode is PointInTimeRestore. Defaults to null.
    long_term_retention_policy = optional(object({
      monthly_retention = optional(string) # See own comment below
      week_of_year      = optional(number) # See own comment below
      weekly_retention  = optional(string) # See own comment below
      yearly_retention  = optional(string) # See own comment below
    }))
    short_term_retention_policy = optional(object({
      backup_interval_in_hours = optional(number) # See own comment below
      retention_days           = optional(number) # See own comment below
    }))
    })
  )
  description = "Map of objects containing information on databases to be created."
  default = {
    defaultdb = {}
  }
}

variable "password_length" {
  type        = number
  description = "Length of password for SQL server. Defaults to 16."
  default     = 16
}

##############################################################################
#                        Retention policies                                  #
##############################################################################
# If you don't provide backup info, a best practice will be enforced for you.#
##############################################################################
# A long_term_retention_policy block supports the following:
# weekly_retention - (Optional) The weekly retention policy for an LTR backup in an ISO 8601 format. Valid value is between 1 to 520 weeks. e.g. P1Y, P1M, P1W or P7D.
# monthly_retention - (Optional) The monthly retention policy for an LTR backup in an ISO 8601 format. Valid value is between 1 to 120 months. e.g. P1Y, P1M, P4W or P30D.
# yearly_retention - (Optional) The yearly retention policy for an LTR backup in an ISO 8601 format. Valid value is between 1 to 10 years. e.g. P1Y, P12M, P52W or P365D.
# week_of_year - (Required) The week of year to take the yearly backup. Value has to be between 1 and 52.

# A short_term_retention_policy block supports the following:
# retention_days - (Required) Point In Time Restore configuration. Value has to be between 7 and 35.
# backup_interval_in_hours - (Optional) The hours between each differential backup. This is only applicable to live databases but not dropped databases. Value has to be 12 or 24. Defaults to 12 hours.
