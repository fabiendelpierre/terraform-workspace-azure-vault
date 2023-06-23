resource "azurerm_resource_group" "vault" {
  name     = "${var.resource_name_prefix}-vault"
  location = "East US"
}

resource "random_string" "vault" {
  length  = 5
  special = false
  lower   = true
  upper   = false
  numeric = true
}

resource "azurerm_user_assigned_identity" "vault" {
  name                = "${var.resource_name_prefix}-msi-vault"
  location            = azurerm_resource_group.vault.location
  resource_group_name = azurerm_resource_group.vault.name
}

resource "azurerm_role_assignment" "msi_keyvault" {
  scope                = azurerm_resource_group.vault.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azurerm_user_assigned_identity.vault.principal_id
}

resource "azurerm_role_assignment" "msi_dns" {
  scope                = data.azurerm_resource_group.dns_zone.id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.vault.principal_id
}

resource "azurerm_storage_account" "vault" {
  name                     = "${var.storage_account_name_prefix}${random_string.vault.result}"
  location                 = azurerm_resource_group.vault.location
  resource_group_name      = azurerm_resource_group.vault.name
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  network_rules {
    bypass                     = ["AzureServices"]
    default_action             = "Deny"
    virtual_network_subnet_ids = [azurerm_subnet.vms.id]
    ip_rules                   = local.storage_account_ip_allowlist
  }
}

resource "azurerm_storage_container" "vault" {
  name                  = "vault-snapshots"
  storage_account_name  = azurerm_storage_account.vault.name
  container_access_type = "private"
}

resource "azurerm_key_vault" "vault" {
  depends_on = [azurerm_user_assigned_identity.vault]

  name                        = "${var.key_vault_name_prefix}${random_string.vault.result}"
  location                    = azurerm_resource_group.vault.location
  resource_group_name         = azurerm_resource_group.vault.name
  sku_name                    = "standard"
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  network_acls {
    bypass                     = "AzureServices"
    default_action             = "Deny"
    virtual_network_subnet_ids = [azurerm_subnet.vms.id]
    ip_rules                   = local.key_vault_ip_allowlist
  }
}

resource "azurerm_key_vault_access_policy" "msi" {
  depends_on = [azurerm_role_assignment.msi_keyvault]

  key_vault_id       = azurerm_key_vault.vault.id
  tenant_id          = data.azurerm_client_config.current.tenant_id
  object_id          = azurerm_user_assigned_identity.vault.principal_id
  key_permissions    = ["Get", "WrapKey", "UnwrapKey"]
  secret_permissions = ["List", "Get", "Set"]
}

resource "azurerm_key_vault_access_policy" "terraform" {
  key_vault_id       = azurerm_key_vault.vault.id
  tenant_id          = data.azurerm_client_config.current.tenant_id
  object_id          = var.terraform_pipeline_object_id
  key_permissions    = ["Create", "List", "Get", "Delete", "Purge", "GetRotationPolicy"]
  secret_permissions = ["Get", "Delete", "Purge"]
}

resource "azurerm_key_vault_access_policy" "myself" {
  key_vault_id       = azurerm_key_vault.vault.id
  tenant_id          = data.azurerm_client_config.current.tenant_id
  object_id          = var.my_aad_object_id
  key_permissions    = ["Create", "List", "Get", "Delete", "Backup", "Purge", "Recover", "Restore", "GetRotationPolicy", "SetRotationPolicy"]
  secret_permissions = ["Get", "Set", "Delete", "List", "Purge", "Recover", "Restore", "Backup"]
}

resource "azurerm_key_vault_key" "vault" {
  depends_on = [azurerm_key_vault_access_policy.myself]

  name         = "vault"
  key_vault_id = azurerm_key_vault.vault.id
  key_type     = "RSA"
  key_size     = 2048
  key_opts     = ["wrapKey", "unwrapKey"]
}

resource "azurerm_application_security_group" "vault" {
  name                = "${var.resource_name_prefix}-asg-vault"
  location            = azurerm_resource_group.vault.location
  resource_group_name = azurerm_resource_group.vault.name
}

resource "azurerm_network_security_rule" "main_ib_vault_ssh" {
  name                                       = "ssh"
  priority                                   = "100"
  direction                                  = "Inbound"
  access                                     = "Allow"
  protocol                                   = "Tcp"
  source_port_range                          = "*"
  destination_port_range                     = "22"
  source_address_prefixes                    = var.vault_ip_allowlist
  destination_application_security_group_ids = [azurerm_application_security_group.vault.id]
  resource_group_name                        = azurerm_resource_group.network.name
  network_security_group_name                = azurerm_network_security_group.main.name
}

resource "azurerm_network_security_rule" "main_ib_vault_https" {
  name                                       = "https"
  priority                                   = "110"
  direction                                  = "Inbound"
  access                                     = "Allow"
  protocol                                   = "Tcp"
  source_port_range                          = "*"
  destination_port_range                     = "8200"
  source_address_prefixes                    = var.vault_ip_allowlist
  destination_application_security_group_ids = [azurerm_application_security_group.vault.id]
  resource_group_name                        = azurerm_resource_group.network.name
  network_security_group_name                = azurerm_network_security_group.main.name
}

resource "azurerm_public_ip" "vault" {
  name                = "${var.resource_name_prefix}-pip-vault"
  resource_group_name = azurerm_resource_group.vault.name
  location            = azurerm_resource_group.vault.location
  allocation_method   = "Static"
}

resource "azurerm_dns_a_record" "vault_public" {
  name                = "vault"
  zone_name           = var.dns_zone_name
  resource_group_name = var.dns_zone_resource_group_name
  ttl                 = 300
  records             = [azurerm_public_ip.vault.ip_address]
}

resource "azurerm_network_interface" "vault" {
  name                = "${var.resource_name_prefix}-nic-vault"
  location            = azurerm_resource_group.vault.location
  resource_group_name = azurerm_resource_group.vault.name

  ip_configuration {
    name                          = "${var.resource_name_prefix}-nic-vault"
    subnet_id                     = azurerm_subnet.vms.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vault.id
  }
}

resource "azurerm_network_interface_application_security_group_association" "vault" {
  network_interface_id          = azurerm_network_interface.vault.id
  application_security_group_id = azurerm_application_security_group.vault.id
}

resource "azurerm_linux_virtual_machine" "vault" {
  depends_on = [
    azurerm_key_vault_key.vault,
    azurerm_role_assignment.msi_keyvault,
    azurerm_role_assignment.msi_dns,
  ]

  name                  = "${var.resource_name_prefix}-vm-vault"
  location              = azurerm_resource_group.vault.location
  resource_group_name   = azurerm_resource_group.vault.name
  size                  = var.vm_size
  admin_username        = var.vault_admin_username
  network_interface_ids = [azurerm_network_interface.vault.id]
  user_data = base64encode(templatefile("${path.module}/vault_vm_user_data.tpl", {
    timezone                   = var.vm_timezone,
    arch                       = var.vm_arch,
    vault_version              = var.vault_version,
    dns_zone_resource_group_id = data.azurerm_resource_group.dns_zone.id,
    dns_zone_name              = var.dns_zone_name,
    certbot_contact_email      = var.certbot_contact_email,
    acme_staging               = var.acme_staging,
    azure_tenant_id            = data.azurerm_client_config.current.tenant_id,
    msi_id                     = azurerm_user_assigned_identity.vault.id,
    msi_client_id              = azurerm_user_assigned_identity.vault.client_id,
    key_vault_name             = azurerm_key_vault.vault.name,
    key_vault_key_name         = azurerm_key_vault_key.vault.name,
    recovery_keys              = var.vault_unseal_recovery_keys,
    recovery_threshold         = var.vault_unseal_recovery_threshold,
  }))

  admin_ssh_key {
    username   = var.vault_admin_username
    public_key = data.azurerm_ssh_public_key.main.public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-arm64"
    version   = "latest"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.vault.id]
  }
}
