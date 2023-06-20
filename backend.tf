terraform {
  backend "azurerm" {
    resource_group_name  = "delpierref-terraform-state-storage"
    storage_account_name = "fdtfstatestorage"
    container_name       = "fdtfstatestorage"
    key                  = "terraform-workspace-azure-vault.tfstate"
    use_oidc             = true
  }
}
