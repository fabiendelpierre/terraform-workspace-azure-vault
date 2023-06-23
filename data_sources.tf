data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "dns_zone" {
  name = local.dns_zone_resource_group_name
}

data "azurerm_dns_zone" "main" {
  name                = local.dns_zone_name
  resource_group_name = local.dns_zone_resource_group_name
}
