#==========================================
#                   Links
#==========================================

# Peer Azure VNet https://developer.hashicorp.com/hcp/tutorials/networking/azure-peering-hcp
# HCP Docs: https://developer.hashicorp.com/hcp/docs/vault/get-started/create-hvn
# HCP tutorials: https://developer.hashicorp.com/vault/tutorials/cloud
# HCP Vault Tf: https://developer.hashicorp.com/vault/tutorials/terraform-hcp-vault
# HCP config w/ tf: https://developer.hashicorp.com/vault/tutorials/operations/apply-codified-vault-hcp-terraform
# HCP metrics: https://developer.hashicorp.com/hcp/docs/vault/logs-metrics#metrics-streaming-configuration


#==========================================
#               provider.tf
#==========================================
// Pin the version
terraform {
  required_providers {
    hcp = {
      source = "hashicorp/hcp"
      version = "0.89.0"
    }
    azurerm = {
      source = "hashicorp/azurerm"
      version = "3.104.2"
    }
    tfe = {
      source = "hashicorp/tfe"
      version = "0.55.0"
    }
    azuread = {
      source = "hashicorp/azuread"
      version = "2.50.0"
    }
     }
}

// Configure the HCP provider: https://registry.terraform.io/providers/hashicorp/hcp/latest/docs/guides/auth
provider "hcp" {
  client_id     = ""
  client_secret = ""
  project_id    = ""
}

// Configure the azure provider
provider "azurerm" {
  features {
    
  }
  client_id = ""
  tenant_id = ""
 }

// Configure the azuread provider
provider "azuread" {
  tenant_id = ""
}   

// Configure the TFC provider (hashi-demo token) 
provider "tfe" {
  token = ""
}



#==========================================
#               HVN & HCP Cluster
#==========================================

resource "hcp_hvn" "example" {
  hvn_id         = "hvn"
  cloud_provider = "azure"
  region         = "canadacentral"
  cidr_block     = "172.25.16.0/20"
}

resource "hcp_vault_cluster" "example" {
  cluster_id = "vault-cluster"
  hvn_id     = hcp_hvn.example.hvn_id
  tier       = "standard_large"
  metrics_config {
    datadog_api_key = "test_datadog"
    datadog_region  = "us1"
  }
  audit_log_config {
    datadog_api_key = "test_datadog"
    datadog_region  = "us1"
  }
  lifecycle {
    prevent_destroy = true
  }
}

#==========================================
#               Azure Peering Connection 
#==========================================
# https://registry.terraform.io/providers/hashicorp/hcp/latest/docs/resources/azure_peering_connection
# https://developer.hashicorp.com/hcp/docs/vault/get-started/configure-private-access
  // This resource initially returns in a Pending state, because its application_id is required to complete acceptance of the connection.

resource "hcp_azure_peering_connection" "peer" {
  hvn_link                 = hcp_hvn.hvn.self_link
  peering_id               = "dev"
  peer_vnet_name           = azurerm_virtual_network.vnet.name
  peer_subscription_id     = azurerm_subscription.sub.subscription_id
  peer_tenant_id           = "<tenant UUID>"
  peer_resource_group_name = azurerm_resource_group.rg.name
  peer_vnet_region         = azurerm_virtual_network.vnet.location
}

data "hcp_azure_peering_connection" "peer" {
  hvn_link              = hcp_hvn.hvn.self_link
  peering_id            = hcp_azure_peering_connection.peer.peering_id
  wait_for_active_state = true
}

resource "hcp_hvn_route" "route" {
  hvn_link         = hcp_hvn.hvn.self_link
  hvn_route_id     = "azure-route"
  destination_cidr = "172.31.0.0/16"
  target_link      = data.hcp_azure_peering_connection.peer.self_link
}

#==========================================
#               Create Azure Resources
#==========================================

data "azurerm_subscription" "sub" {
  subscription_id = "<subscription UUID>"
}

resource "azurerm_resource_group" "rg" {
  name     = "resource-group-test"
  location = "Canada Central"
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-test"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  address_space = [
    "10.0.0.0/16"
  ]
}

resource "azuread_service_principal" "principal" {
  application_id = hcp_azure_peering_connection.peer.application_id
}

resource "azurerm_role_definition" "definition" {
  name  = "hcp-hvn-peering-access"
  scope = azurerm_virtual_network.vnet.id

  assignable_scopes = [
    azurerm_virtual_network.vnet.id
  ]

  permissions {
    actions = [
      "Microsoft.Network/virtualNetworks/peer/action",
      "Microsoft.Network/virtualNetworks/virtualNetworkPeerings/read",
      "Microsoft.Network/virtualNetworks/virtualNetworkPeerings/write"
    ]
  }
}

resource "azurerm_role_assignment" "assignment" {
  principal_id       = azuread_service_principal.principal.id
  scope              = azurerm_virtual_network.vnet.id
  role_definition_id = azurerm_role_definition.definition.role_definition_resource_id
}
