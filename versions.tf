terraform {
  required_version = "~> 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.61"
    }
    # github = {
    #   source  = "integrations/github"
    #   version = "~> 5.28"
    # }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}
