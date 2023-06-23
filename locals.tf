locals {
  resource_name_prefix         = "delpierref"
  vnet_cidr                    = "10.19.20.0/23"
  vault_ip_allowlist           = ["68.84.62.0/24", "199.212.219.8/32", "199.212.218.22/32"]
  vault_admin_username         = "fd1"
  dns_zone_name                = "us-terraform-prod.azure.lnrsg.io"
  dns_zone_resource_group_name = "app-dns-prod-eastus2"
  certbot_contact_email        = "fabien.delpierre@lexisnexisrisk.com"
  vm_timezone                  = "UTC"
  vm_arch                      = "arm64"
  vault_version                = "1.14.0"
}
