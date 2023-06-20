variable "state_backend_resource_group_name" {
  type = string
}

variable "state_backend_storage_account_name" {
  type = string
}

variable "state_backend_storage_container_name" {
  type = string
}

variable "state_backend_subscription_id" {
  type = string
}

variable "state_backend_tenant_id" {
  type = string
}

terraform {
  backend "azurerm" {
    resource_group_name  = var.state_backend_resource_group_name
    storage_account_name = var.state_backend_storage_account_name
    container_name       = var.state_backend_storage_container_name
    key                  = "terraform-workspace-azure-vault.tfstate"
    use_oidc             = true
    subscription_id      = var.state_backend_subscription_id
    tenant_id            = var.state_backend_tenant_id
  }
}
