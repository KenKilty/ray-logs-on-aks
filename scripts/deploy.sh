#!/bin/bash
set -e

# Get the directory of the script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Deploy Terraform infrastructure
echo "Deploying Terraform infrastructure..."
cd "$PROJECT_ROOT/terraform"
terraform init -upgrade
terraform apply -auto-approve

# Get outputs from Terraform
RESOURCE_GROUP=$(terraform output -raw resource_group_name)
AKS_NAME=$(terraform output -raw aks_name)
LAW_NAME=$(terraform output -raw log_analytics_workspace_name)

# Get AKS credentials
echo "Getting AKS credentials..."
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$AKS_NAME" --overwrite-existing

# Create namespace
NAMESPACE="ray-logs"
echo "Creating namespace $NAMESPACE..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Apply Kubernetes manifests
echo "Applying Kubernetes manifests..."
cd "$PROJECT_ROOT/manifests"
echo "Deploying log simulator and collector..."
kubectl apply -f ray-logs-namespace.yaml
kubectl apply -f ray-logs-simulator-deployment.yaml
kubectl apply -f ray-logs-collector-deployment.yaml

echo "Deployment completed!"

# Validate log collection
echo "Validating log collection..."
LAW_CUSTOMER_ID=$(az monitor log-analytics workspace show \
    --resource-group "$RESOURCE_GROUP" \
    --workspace-name "$LAW_NAME" \
    --query customerId \
    --output tsv)

# Function to check for logs
check_logs() {
    local query="ContainerLogV2
    | where TimeGenerated > ago(5m)
    | where PodNamespace == 'ray-logs'
    | where ContainerName == 'log-generator'
    | project TimeGenerated, ContainerName, LogMessage
    | order by TimeGenerated desc
    | limit 5"

    local result=$(az monitor log-analytics query \
        --workspace "$LAW_CUSTOMER_ID" \
        --analytics-query "$query" \
        --timespan 5m)

    if [ "$(echo "$result" | jq 'length')" -gt 0 ]; then
        echo "✅ Logs found in ContainerLogV2 table:"
        echo "$result" | jq -r '.[] | "\(.TimeGenerated) - \(.ContainerName): \(.LogMessage)"'
        return 0
    else
        echo "⏳ Waiting for logs..."
        return 1
    fi
}

# Try for 5 minutes (30 attempts, 10 seconds apart)
attempt=1
max_attempts=30

while [ $attempt -le $max_attempts ]; do
    echo "Attempt $attempt of $max_attempts..."
    
    if check_logs; then
        echo "✅ Validation successful! Logs are being collected."
        exit 0
    fi
    
    attempt=$((attempt + 1))
    sleep 10
done

echo "❌ Validation failed! No logs found after 5 minutes."
echo "Please check:"
echo "1. The log simulator pod is running: kubectl get pods -n ray-logs -l app=ray-logs-simulator"
echo "2. The Fluentd collector pod is running: kubectl get pods -n ray-logs -l app=ray-logs-collector"
echo "3. The Container Insights extension is properly configured"
exit 1 