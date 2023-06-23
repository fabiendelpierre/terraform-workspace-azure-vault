# locals {
#   gha_ip_ranges_without_small_prefixes = [for j in [for i in data.github_ip_ranges.main.actions_ipv4 : replace(i, "/31", "")] : replace(j, "/32", "")]
#   storage_account_ip_allowlist         = flatten([[for i in var.vault_ip_allowlist : replace(i, "/32", "")], local.gha_ip_ranges_without_small_prefixes])
#   key_vault_ip_allowlist               = flatten([var.vault_ip_allowlist, data.github_ip_ranges.main.actions_ipv4])
# }
