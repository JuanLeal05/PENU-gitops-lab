terraform {
  backend "azurerm" {
    container_name   = "tfstate"
    key              = "prod.tfstate"
    use_azuread_auth = true
    # storage_account_name se entrega con -backend-config desde el workflow
  }
}
