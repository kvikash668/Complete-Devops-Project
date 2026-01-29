provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = "dotnet-rg"
  location = "East US"
}

resource "azurerm_app_service_plan" "app_plan" {
  name                = "dotnet-app-service-plan"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku {
    tier = "Standard"
    size = "S1"
  }
}

resource "azurerm_app_service" "app_service" {
  name                = "dotnet-web-app-${random_id.suffix.hex}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  app_service_plan_id = azurerm_app_service_plan.app_plan.id

  site_config {
    dotnet_framework_version = "v6.0"
  }

  app_settings = {
    "WEBSITE_RUN_FROM_PACKAGE" = "1"
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}
