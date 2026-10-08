terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}

  # La identidad solo tiene permisos sobre grupos de recursos, no sobre la
  # suscripción, así que no puede registrar proveedores de recursos.
  resource_provider_registrations = "none"
}

variable "location" {
  type = string
}

variable "owner" {
  type = string
}

variable "prefix" {
  type    = string
  default = "lab5"
}

module "sitio" {
  source              = "../../modules/static_site"
  resource_group_name = "rg-gitops-dev"
  location            = var.location
  prefix              = var.prefix
  environment         = "dev"
  index_file          = "${path.root}/../../site/index.html"

  tags = {
    environment = "dev"
    owner       = var.owner
    course      = "pemu-2026"
  }
}

output "site_url" {
  value = module.sitio.site_url
}
