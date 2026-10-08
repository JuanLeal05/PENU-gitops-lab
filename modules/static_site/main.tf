locals {
  sa_name = "st${var.prefix}${var.environment}${random_string.suffix.result}"
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_storage_account" "site" {
  name                            = local.sa_name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  tags                            = var.tags
}

resource "azurerm_storage_account_static_website" "site" {
  storage_account_id = azurerm_storage_account.site.id
  index_document     = "index.html"
}

resource "azurerm_storage_blob" "index" {
  name                   = "index.html"
  storage_account_name   = azurerm_storage_account.site.name
  storage_container_name = "$web"
  type                   = "Block"
  content_type           = "text/html"
  source                 = var.index_file
  content_md5            = filemd5(var.index_file)

  depends_on = [azurerm_storage_account_static_website.site]
}
