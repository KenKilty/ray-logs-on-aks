variable "location" {
  description = "Azure region to deploy resources"
  type        = string
}

# Resource Names
variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "virtual_network_name" {
  description = "Name of the virtual network"
  type        = string
}

variable "subnet_name" {
  description = "Name of the subnet"
  type        = string
}

variable "aks_cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
}

variable "log_analytics_workspace_name" {
  description = "Name of the Log Analytics Workspace"
  type        = string
}

variable "managed_identity_name" {
  description = "Name of the managed identity"
  type        = string
}

# Configuration Variables
variable "kubernetes_version" {
  description = "Kubernetes version for the AKS cluster"
  type        = string
}

variable "law_retention_in_days" {
  description = "Log Analytics Workspace retention in days"
  type        = number
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
}

variable "law_sku" {
  description = "SKU for Log Analytics Workspace"
  type        = string
}

variable "container_insights_publisher" {
  description = "Publisher for Container Insights solution"
  type        = string
}

variable "container_insights_product" {
  description = "Product for Container Insights solution"
  type        = string
}

# Default Node Pool Variables
variable "default_node_pool_name" {
  type        = string
  description = "The name of the default node pool"
}

variable "default_node_pool_node_count" {
  type        = number
  description = "The initial number of nodes in the default node pool"
}

variable "default_node_pool_vm_size" {
  type        = string
  description = "The size of VMs in the default node pool"
}

variable "default_node_pool_enable_auto_scaling" {
  type        = bool
  description = "Enable auto-scaling for the default node pool"
}

variable "default_node_pool_max_pods" {
  type        = number
  description = "The maximum number of pods per node"
}

variable "default_node_pool_os_disk_size_gb" {
  type        = number
  description = "The OS disk size in GB for each node"
}

# Virtual Network Configuration
variable "virtual_network_address_space" {
  type        = string
  description = "The address space for the virtual network"
}

variable "node_cidr" {
  type        = string
  description = "The CIDR for the AKS subnet"
}

variable "service_cidr" {
  type        = string
  description = "The CIDR for Kubernetes services"
}

variable "dns_service_ip" {
  type        = string
  description = "IP address within the Kubernetes service address range that will be used by cluster service discovery (kube-dns)"
}

# Container Insights Settings
variable "container_insights_interval" {
  type        = string
  description = "Interval for collecting metrics and logs from the cluster"
}

variable "container_insights_namespace_filtering_mode" {
  type        = string
  description = "Mode for filtering namespaces (Off, Include, Exclude)"
}

variable "container_insights_namespaces" {
  type        = list(string)
  description = "List of namespaces to include or exclude based on namespaceFilteringMode"
}

variable "container_insights_enable_container_log_v2" {
  type        = bool
  description = "Enable the newer ContainerLogV2 schema which provides more detailed container logs"
}

# AKS Identity Settings
variable "aks_identity_type" {
  description = "The type of identity used for the AKS cluster. Possible values are SystemAssigned, UserAssigned, SystemAssigned, UserAssigned"
  type        = string
  default     = "UserAssigned"
}

# DCR Settings
variable "dcr_destination_name" {
  description = "Name of the Data Collection Rule destination for Log Analytics"
  type        = string
} 