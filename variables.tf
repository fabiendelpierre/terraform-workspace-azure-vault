variable "resource_name_prefix" {
  type = string
}

variable "vnet_cidr" {
  type = string
}

variable "vault_ip_allowlist" {
  type = list(string)
}

variable "vault_admin_username" {
  type = string
}

variable "dns_zone_name" {
  type = string
}

variable "dns_zone_resource_group_name" {
  type = string
}

variable "certbot_contact_email" {
  type = string
}

variable "acme_staging" {
  type    = string
  default = "true"
}

variable "vm_timezone" {
  type = string
}

variable "vm_size" {
  type    = string
  default = "Standard_D2pls_v5"
}

variable "vm_arch" {
  type    = string
  default = "arm64"
}

variable "vault_version" {
  type = string
}

variable "key_vault_name_prefix" {
  type = string
}

variable "storage_account_name_prefix" {
  type = string
}

variable "vault_unseal_recovery_keys" {
  type    = number
  default = 1
}

variable "vault_unseal_recovery_threshold" {
  type    = number
  default = 1
}

variable "ssh_public_key_resource_group_name" {
  type = string
}

variable "ssh_public_key_name" {
  type = string
}

variable "my_aad_object_id" {
  type = string
}

variable "terraform_pipeline_object_id" {
  type = string
}

# variable "gh_pat" {
#   type = string
# }
