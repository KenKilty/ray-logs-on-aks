# Ray Logs on AKS

A solution for collecting Ray framework logs in AKS using Fluentd and Container Insights. Redirects Ray's filesystem logs to Container Insights for better observability of Ray workloads in Azure.

## Problem Statement

Ray, a distributed computing framework, writes logs to the filesystem in a specific directory structure (`/tmp/ray/session_*/logs/*.log`). These logs are not automatically collected by Azure Container Insights, which primarily collects logs from stdout and stderr. This creates a challenge for monitoring and troubleshooting Ray applications running on Azure Kubernetes Service (AKS).

Currently, there is no Data Collection Rule (DCR) support in Container Insights that can directly collect custom text files from the filesystem in AKS. This project demonstrates a solution using a Fluentd sidecar container that continuously reads the filesystem logs and redirects them to stdout and stderr, making them available to Container Insights.

## Solution Architecture

This project implements a solution with the following components:

1. **Ray Log Simulator**: A Python application that simulates Ray logs by writing them to the filesystem in the same structure and format as Ray.
2. **Fluentd Sidecar**: A container that reads the logs from the filesystem and redirects them to stdout/stderr based on log level.
3. **Azure Container Insights**: Collects the redirected logs from stdout/stderr and makes them available in Log Analytics.

When deployed, you'll see two main monitoring resources in your resource group:
- "ContainerInsights(law-ray-logs-demo)": The Container Insights solution connected to our Log Analytics workspace (law) that collects and processes the container logs
- "aks-ray-logs-demo": The Data Collection Rule that defines what logs to collect and how to process them

### How It Works

1. The Ray Log Simulator generates logs with different levels (INFO, WARNING, ERROR) and writes them to files in `/tmp/ray/session_*/logs/*.log`.
2. The Fluentd sidecar container:
   - Monitors these log files using the `tail` input plugin
   - Parses the JSON logs
   - Uses the `exec` output plugin to redirect logs to stdout/stderr based on their level
   - ERROR logs go to stderr, while INFO and WARNING logs go to stdout
3. Container Insights automatically collects logs from stdout/stderr and sends them to Log Analytics
4. The logs can then be queried and analyzed in the Azure Portal

## Prerequisites

- Azure CLI
- Terraform
- kubectl
- Azure subscription with Contributor permissions

## Project Structure

```
raylogsim/
├── terraform/           # Infrastructure as Code
│   ├── main.tf         # Main Terraform configuration
│   ├── variables.tf    # Variable definitions
│   ├── outputs.tf      # Output values
│   └── terraform.tfvars # Variable values (create this file)
├── manifests/          # Kubernetes manifests
│   ├── ray-logs-simulator-deployment.yaml
│   └── ray-logs-collector-deployment.yaml
└── scripts/
    └── deploy.sh       # Deployment script
```

## Components

### 1. Ray Log Simulator

The Ray Log Simulator is a Python application that generates logs similar to those produced by Ray. It:

- Creates a unique session directory (`/tmp/ray/session_*/logs/`)
- Generates logs for different Ray components (driver, worker, actor, system)
- Assigns different log levels (INFO, WARNING, ERROR) with varying frequencies
- Writes logs to component-specific files (e.g., `ray_driver.log`, `ray_worker.log`)

The simulator is deployed as a Kubernetes pod with an emptyDir volume to store the logs.

### 2. Fluentd Collector

The Fluentd collector is deployed as a sidecar container in the same pod as the Ray Log Simulator. It:

- Uses the `tail` input plugin to monitor log files in `/tmp/ray/session_*/logs/*.log`
- Parses the JSON logs using the `json` parser
- Uses the `exec` output plugin to redirect logs to stdout/stderr based on their level
- ERROR logs are sent to stderr, while INFO and WARNING logs are sent to stdout

### 3. Azure Container Insights

Azure Container Insights is configured to:

- Collect logs from stdout and stderr
- Filter logs by namespace (in this case, the `ray-logs` namespace)
- Use the ContainerLogV2 schema for more detailed container logs
- Send logs to a Log Analytics workspace for analysis

### Understanding Container Insights in Our Solution

While our Terraform configuration references `omsagent` (in the AKS addon profile configuration shown below), our solution actually uses the Azure Monitor Agent (AMA) for log collection:

```hcl
resource "azurerm_kubernetes_cluster" "aks" {
  # ... other configuration ...

  monitor_metrics {
    annotations_allowed = []
    labels_allowed     = []
  }

  # This references 'omsagent' but actually deploys AMA
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  }
}
```

Here's how the components work together:

#### Data Collection Rule (DCR)
A DCR is essentially a configuration file in Azure that defines your monitoring recipe - it specifies what data you want to collect, how to collect it, and where to send it. Think of it as a monitoring playbook that tells Azure "watch these things, in this way, and send the data here." In our solution, it's declared in Terraform:
```hcl
resource "azurerm_monitor_data_collection_rule" "aks" {
  name                = "aks-ray-logs-demo"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  data_sources {
    extension {
      name           = "ContainerInsightsExtension"
      extension_name = "ContainerInsights"
      streams        = ["Microsoft-ContainerInsights-Group-Default"]
      ...
    }
  }
  ...
}
```
This DCR specifies:
- Collection of container logs from our `ray-logs` namespace
- Use of ContainerLogV2 schema
- Sending data to our Log Analytics workspace

> **Note:** When viewing the DCR in the Azure Portal, you'll notice a few things about Container Insights configuration:
> - In the "Data sources" tab, you'll see "No standard data sources or destinations found". This is expected because Container Insights uses the ContainerInsightsExtension, which is a specialized extension rather than a standard data source.
> - In the "Resources" tab, you'll see your AKS cluster listed with "No endpoint configured" status. This is normal for Container Insights DCRs, as they use a built-in endpoint configuration through the Azure Monitor Agent (AMA).
> - In the "Identity" tab, authentication is handled through the AKS cluster's managed identity for Container Insights operations. The DCR can use either system-assigned or user-assigned managed identities for other data collection scenarios.
> The data collection is working through the ContainerInsights extension and Azure Monitor Agent (AMA).

> **Important Cost Management Note:** In this demo, we've configured the DCR to only include logs from the `ray-logs` namespace to focus on our simulation. In production environments, you would typically do the opposite - exclude specific namespaces (like `kube-system`, monitoring tools, etc.) while collecting logs from your application namespaces. This namespace filtering capability is crucial for controlling costs in AKS Container Insights, as log ingestion can become expensive at scale without proper filtering.

#### Data Collection Rule Association (DCRA)
The DCRA is the binding mechanism that tells Azure which monitoring settings (defined in the DCR) should apply to which resources. Think of it as the "glue" that connects your data collection rules to the actual resources you want to monitor. In our solution, it's declared in Terraform:
```hcl
resource "azurerm_monitor_data_collection_rule_association" "aks" {
  name                    = "aks-ray-logs-demo"
  target_resource_id      = azurerm_kubernetes_cluster.aks.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.aks.id
}
```

#### Azure Monitor Agent (AMA)
Despite the Terraform configuration referencing `omsagent`, the actual collection is done by AMA pods. You can see these in your cluster:
```bash
$ kubectl get pods -n kube-system | grep ama
ama-logs-l9c8f                    3/3     Running   1          10m
ama-logs-rs-f46df69f7-szkqv       2/2     Running   0          10m
```

#### Data Flow
1. Ray Log Simulator writes logs to `/tmp/ray/session_*/logs/*.log`
2. Fluentd sidecar reads these logs and writes to stdout/stderr
3. AMA pods collect container logs through containerd
4. The DCR configuration filters logs from the `ray-logs` namespace
5. Logs are sent to Log Analytics using ContainerLogV2 schema
6. Data becomes queryable in Log Analytics

## Deployment

1. Create a `terraform.tfvars` file in the terraform directory with your desired values (see `variables.tf` for available options)

2. Run the deployment script:
   ```bash
   ./scripts/deploy.sh
   ```

The script will:
- Deploy the infrastructure using Terraform
- Configure kubectl to use the new AKS cluster
- Deploy the Kubernetes manifests
- Wait for pods to be ready
- Display instructions for checking logs

### What's Running After Deployment

After a successful deployment, you'll have several components running in your cluster. Here's what you should see:

#### Ray Logs Components (namespace: ray-logs)
```bash
$ kubectl get pods -n ray-logs
NAME                                  READY   STATUS    RESTARTS   AGE
ray-logs-simulator-5d4f8b9c6-2qxvp   2/2     Running   0          10m
```

This pod contains two containers:
1. `ray-logs-simulator`: Generates Ray-like logs
2. `fluentd`: Collects and redirects logs to stdout/stderr

#### Monitoring Components (namespace: kube-system)
```bash
$ kubectl get pods -n kube-system | grep -E 'ama|oms'
ama-logs-l9c8f                    3/3     Running   1          10m
ama-logs-rs-f46df69f7-szkqv       2/2     Running   0          10m
```

These pods handle log collection and forwarding to Azure Monitor.

## Verifying Log Collection

1. Check the Ray Log Simulator logs:
   ```bash
   kubectl logs -n ray-logs deployment/ray-logs-simulator -c ray-logs-simulator
   ```

2. Check the Fluentd collector logs:
   ```bash
   kubectl logs -n ray-logs deployment/ray-logs-simulator -c fluentd
   ```

3. Query logs in Azure Portal:
   - Navigate to your Log Analytics workspace
   - Use the following Kusto query to see the collected logs:
   ```kusto
   ContainerLogV2
   | where Namespace == "ray-logs"
   | where ContainerName == "ray-logs-simulator"
   | project TimeGenerated, LogEntry, LogLevel
   | order by TimeGenerated desc
   ```

## Cleanup

To remove all resources created by this project:

1. Delete the Kubernetes resources:
   ```bash
   kubectl delete namespace ray-logs
   ```

2. Run Terraform destroy:
   ```bash
   cd terraform
   terraform destroy
   ```

## Additional Resources

- [Ray Documentation](https://docs.ray.io/)
- [Azure Container Insights Documentation](https://learn.microsoft.com/en-us/azure/azure-monitor/containers/container-insights-overview)
- [Fluentd Documentation](https://docs.fluentd.org/)
- [Azure Monitor Agent Documentation](https://learn.microsoft.com/en-us/azure/azure-monitor/agents/azure-monitor-agent-overview)
- [Container Insights Agent Configuration](https://github.com/microsoft/Docker-Provider/blob/ci_prod/kubernetes/container-azm-ms-agentconfig.yaml) - Reference configuration for customizing log collection settings, including namespace filtering and log collection thresholds
- [Container Insights Agent Settings Documentation](https://github.com/microsoft/Docker-Provider/blob/ci_prod/Documentation/AgentSettings/ReadMe.md) - Detailed documentation of all available agent settings
- [Container Insights Log Query Documentation](https://learn.microsoft.com/en-us/azure/azure-monitor/containers/container-insights-log-query) - Guide for querying container logs in Log Analytics
- [Container Insights High Scale Mode](https://aka.ms/cihsmode) - Documentation for high log volume scenarios

## License

This project is licensed under the MIT License - see the LICENSE file for details.