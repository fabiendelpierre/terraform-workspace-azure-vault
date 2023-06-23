data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "dns_zone" {
  name = var.dns_zone_resource_group_name
}

data "azurerm_dns_zone" "main" {
  name                = var.dns_zone_name
  resource_group_name = data.azurerm_resource_group.dns_zone.name
}

data "azurerm_ssh_public_key" "main" {
  name                = var.ssh_public_key_name
  resource_group_name = var.ssh_public_key_resource_group_name
}

data "github_ip_ranges" "main" {}
