# 1. Data Sources
data "azurerm_subscription" "current" {}

# 2. Core Infrastructure
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "this" {
  name                = var.virtual_network_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  address_space       = [var.virtual_network_address_space]
  tags                = var.tags
}

resource "azurerm_subnet" "aks" {
  name                 = var.subnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.node_cidr]
  service_endpoints    = []
  private_endpoint_network_policies_enabled = true
  private_link_service_network_policies_enabled = true
}

# 3. Identity and Access
resource "azurerm_user_assigned_identity" "aks_identity" {
  name                = var.managed_identity_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  tags                = var.tags
}

# 4. Monitoring Infrastructure
resource "azurerm_log_analytics_workspace" "law" {
  name                = var.log_analytics_workspace_name
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = var.law_sku
  retention_in_days   = var.law_retention_in_days
  tags                = var.tags
}

resource "azurerm_log_analytics_solution" "container_insights" {
  solution_name         = "ContainerInsights"
  location              = var.location
  resource_group_name   = azurerm_resource_group.rg.name
  workspace_resource_id = azurerm_log_analytics_workspace.law.id
  workspace_name        = azurerm_log_analytics_workspace.law.name

  plan {
    publisher = var.container_insights_publisher
    product   = var.container_insights_product
  }

  tags = var.tags
}

# 5. AKS Cluster and Extensions
resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.aks_cluster_name
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = var.aks_cluster_name
  kubernetes_version  = var.kubernetes_version
  tags                = var.tags

  identity {
    type         = var.aks_identity_type
    identity_ids = [azurerm_user_assigned_identity.aks_identity.id]
  }

  default_node_pool {
    name                = var.default_node_pool_name
    node_count          = var.default_node_pool_node_count
    vm_size             = var.default_node_pool_vm_size
    vnet_subnet_id      = azurerm_subnet.aks.id
    enable_auto_scaling = var.default_node_pool_enable_auto_scaling
    max_pods            = var.default_node_pool_max_pods
    os_disk_size_gb     = var.default_node_pool_os_disk_size_gb
    tags                = var.tags
  }

  network_profile {
    network_plugin     = "azure"
    network_policy     = "azure"
    service_cidr       = var.service_cidr
    dns_service_ip     = var.dns_service_ip
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
    msi_auth_for_monitoring_enabled = true
  }

  oidc_issuer_enabled = true
  workload_identity_enabled = true

  depends_on = [
    azurerm_log_analytics_workspace.law,
    azurerm_log_analytics_solution.container_insights
  ]
}

# 6. Monitoring Configuration (Logs Only)
resource "azurerm_monitor_data_collection_rule" "aks" {
  name                = azurerm_kubernetes_cluster.aks.name
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  tags                = var.tags

  destinations {
    log_analytics {
      name                  = var.dcr_destination_name
      workspace_resource_id = azurerm_log_analytics_workspace.law.id
    }
  }

  data_flow {
    streams      = ["Microsoft-ContainerInsights-Group-Default"]
    destinations = [var.dcr_destination_name]
  }

  data_sources {
    extension {
      name           = "ContainerInsightsExtension"
      streams        = ["Microsoft-ContainerInsights-Group-Default"]
      extension_name = "ContainerInsights"
      extension_json = jsonencode({
        dataCollectionSettings = {
          # Interval for collecting metrics and logs (e.g., "1m", "5m", "15m", "30m", "1h")
          # See: https://learn.microsoft.com/en-us/azure/azure-monitor/containers/container-insights-log-query#containerlog-table
          interval = var.container_insights_interval

          # Namespace filtering mode options:
          # - "Off": No filtering, collect logs from all namespaces
          # - "Include": Only collect logs from specified namespaces
          # - "Exclude": Collect logs from all namespaces except specified ones
          # See: https://learn.microsoft.com/en-us/azure/azure-monitor/containers/container-insights-agent-config#namespace-filtering
          namespaceFilteringMode = var.container_insights_namespace_filtering_mode

          # List of namespaces to include or exclude based on namespaceFilteringMode
          # Example: ["ray-logs", "default", "kube-system"]
          # See: https://learn.microsoft.com/en-us/azure/azure-monitor/containers/container-insights-agent-config#namespace-filtering
          namespaces = var.container_insights_namespaces

          # Enable ContainerLogV2 schema for more detailed container logs
          # - true: Use newer schema with more fields and better structure
          # - false: Use legacy schema
          # See: https://learn.microsoft.com/en-us/azure/azure-monitor/containers/container-insights-log-query#containerlog-table
          enableContainerLogV2 = var.container_insights_enable_container_log_v2

          # Additional configuration options from official Microsoft Container Insights agent config:
          # See: https://github.com/microsoft/Docker-Provider/blob/ci_prod/kubernetes/container-azm-ms-agentconfig.yaml
          #
          # Log collection settings:
          # - log_collection_settings.stdout.enabled: Enable/disable stdout log collection (default: true)
          # - log_collection_settings.stdout.exclude_namespaces: Namespaces to exclude from stdout collection
          # - log_collection_settings.stderr.enabled: Enable/disable stderr log collection (default: true)
          # - log_collection_settings.stderr.exclude_namespaces: Namespaces to exclude from stderr collection
          # - log_collection_settings.collect_system_pod_logs: List of system pods to collect logs from (format: "namespace:podName")
          #
          # Multi-tenancy settings:
          # - log_collection_settings.multi_tenancy.enabled: Enable/disable multi-tenancy mode (default: false)
          # - log_collection_settings.multi_tenancy.disable_fallback_ingestion: Disable fallback ingestion (default: false)
          #
          # Alertable metrics configuration:
          # - alertable_metrics_configuration_settings.container_resource_utilization_thresholds.container_cpu_threshold_percentage: CPU threshold percentage (default: 95.0)
          # - alertable_metrics_configuration_settings.container_resource_utilization_thresholds.container_memory_rss_threshold_percentage: Memory RSS threshold percentage (default: 95.0)
          # - alertable_metrics_configuration_settings.container_resource_utilization_thresholds.container_memory_working_set_threshold_percentage: Memory working set threshold percentage (default: 95.0)
          # - alertable_metrics_configuration_settings.pv_utilization_thresholds.pv_usage_threshold_percentage: PV usage threshold percentage (default: 60.0)
          # - alertable_metrics_configuration_settings.job_completion_threshold.job_completion_threshold_time_minutes: Job completion threshold time in minutes (default: 360)
          #
          # Agent settings:
          # - agent_settings.high_log_scale.enabled: Enable/disable high log scale mode (default: false)
          # - agent_settings.prometheus_fbit_settings.tcp_listener_chunk_size: TCP listener chunk size in MB (default: 10)
          # - agent_settings.prometheus_fbit_settings.tcp_listener_buffer_size: TCP listener buffer size in MB (default: 10)
          # - agent_settings.prometheus_fbit_settings.tcp_listener_mem_buf_limit: TCP listener memory buffer limit in MB (default: 200)
          # - agent_settings.fbit_config.log_flush_interval_secs: Log flush interval in seconds (default: 15)
          # - agent_settings.fbit_config.tail_mem_buf_limit_megabytes: Tail memory buffer limit in MB (default: 10)
          # - agent_settings.fbit_config.tail_buf_chunksize_megabytes: Tail buffer chunk size in MB (default: 0.032)
          # - agent_settings.fbit_config.tail_buf_maxsize_megabytes: Tail buffer max size in MB (default: 0.032)
          # - agent_settings.fbit_config.enable_internal_metrics: Enable internal metrics (default: false)
          # - agent_settings.fbit_config.tail_ignore_older: Ignore logs older than specified time (default: 0m)
          # - agent_settings.proxy_config.ignore_proxy_settings: Ignore proxy settings (default: false)
          # - agent_settings.windows_fluent_bit.disabled: Disable fluent-bit for Windows (default: false)
          # - agent_settings.network_listener_waittime.tcp_port_25226: Wait time for port 25226 in seconds (default: 45)
          # - agent_settings.network_listener_waittime.tcp_port_25228: Wait time for port 25228 in seconds (default: 60)
          # - agent_settings.network_listener_waittime.tcp_port_25229: Wait time for port 25229 in seconds (default: 45)
          # - agent_settings.mdsd_config.monitoring_max_event_rate: Maximum event rate (default: 20000)
          # - agent_settings.mdsd_config.backpressure_memory_threshold_in_mb: Backpressure memory threshold in MB (default: 3500)
          # - agent_settings.mdsd_config.upload_max_size_in_mb: Upload max size in MB (default: 2)
          # - agent_settings.mdsd_config.upload_frequency_seconds: Upload frequency in seconds (default: 60)
          # - agent_settings.mdsd_config.compression_level: Compression level (0-9, 0 means no compression)
          # - agent_settings.resource_optimization.enabled: Enable resource optimization (default: false)
          # - agent_settings.telemetry_config.disable_telemetry: Disable telemetry (default: false)
          # - agent_settings.k8s_metadata_config.kube_meta_cache_ttl_secs: Kubernetes metadata cache TTL in seconds (default: 60)
          # - agent_settings.chunk_config.PODS_CHUNK_SIZE: Pods chunk size (default: 1000)
          #
          # For more details, see: https://github.com/microsoft/Docker-Provider/blob/ci_prod/Documentation/AgentSettings/ReadMe.md
        }
      })
    }
  }
}

resource "azurerm_monitor_data_collection_rule_association" "aks" {
  name                    = azurerm_kubernetes_cluster.aks.name
  target_resource_id      = azurerm_kubernetes_cluster.aks.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.aks.id
} 