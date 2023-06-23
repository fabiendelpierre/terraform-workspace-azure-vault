resource "azurerm_resource_group" "network" {
  name     = "${var.resource_name_prefix}-network"
  location = "East US"
}

resource "azurerm_virtual_network" "main" {
  name                = "${var.resource_name_prefix}-vnet"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name
  address_space       = [var.vnet_cidr]
}

resource "azurerm_subnet" "vms" {
  name                 = "${var.resource_name_prefix}-snet-vms"
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [cidrsubnet(var.vnet_cidr, 3, 0)]
  service_endpoints    = ["Microsoft.KeyVault", "Microsoft.Storage"]
}

resource "azurerm_route_table" "main" {
  name                = "${var.resource_name_prefix}-default-rt"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name
}

resource "azurerm_subnet_route_table_association" "vms" {
  subnet_id      = azurerm_subnet.vms.id
  route_table_id = azurerm_route_table.main.id
}

resource "azurerm_route" "main_vnetlocal" {
  name                = "vnetlocal"
  resource_group_name = azurerm_resource_group.network.name
  route_table_name    = azurerm_route_table.main.name
  address_prefix      = var.vnet_cidr
  next_hop_type       = "VnetLocal"
}

resource "azurerm_route" "main_internet" {
  name                = "internet"
  resource_group_name = azurerm_resource_group.network.name
  route_table_name    = azurerm_route_table.main.name
  address_prefix      = "0.0.0.0/0"
  next_hop_type       = "Internet"
}

resource "azurerm_network_security_group" "main" {
  name                = "${var.resource_name_prefix}-default-nsg"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name
}

resource "azurerm_subnet_network_security_group_association" "vms" {
  subnet_id                 = azurerm_subnet.vms.id
  network_security_group_id = azurerm_network_security_group.main.id
}

resource "azurerm_network_security_rule" "main_ob_internet" {
  name                        = "internet"
  priority                    = "100"
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "0.0.0.0/0"
  resource_group_name         = azurerm_resource_group.network.name
  network_security_group_name = azurerm_network_security_group.main.name
}
