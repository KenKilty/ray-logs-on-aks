output "resource_group_name" {
  description = "The name of the resource group"
  value       = azurerm_resource_group.rg.name
}

output "aks_name" {
  description = "The name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.name
}

output "aks_id" {
  description = "The ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.id
}

output "kubeconfig" {
  description = "The kubeconfig for the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive   = true
}

output "vnet_id" {
  description = "The ID of the VNet"
  value       = azurerm_virtual_network.this.id
}

output "subnet_id" {
  description = "The ID of the subnet"
  value       = azurerm_subnet.aks.id
}

output "aks_managed_identity_id" {
  description = "The ID of the managed identity used by the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.identity[0].principal_id
}

output "log_analytics_workspace_name" {
  description = "The name of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.law.name
} 