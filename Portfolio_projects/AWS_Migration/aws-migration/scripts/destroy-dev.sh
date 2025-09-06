#!/bin/bash

# Destroy TechHealth Infrastructure in Development Environment
# This script safely destroys the dev environment to avoid ongoing costs

set -e  # Exit on any error

echo "🧹 Destroying TechHealth Infrastructure in Development Environment"
echo "=================================================================="

# Set environment variables
export ENVIRONMENT=dev
export CDK_DEFAULT_REGION=us-east-1

# Confirmation
echo "⚠️  This will destroy ALL resources in the development environment!"
echo "This action cannot be undone."
echo ""
read -p "Are you sure you want to destroy the dev environment? (type 'destroy' to confirm): " confirm
if [ "$confirm" != "destroy" ]; then
    echo "❌ Destruction cancelled."
    exit 1
fi

# List resources that will be destroyed
echo "📋 Resources to be destroyed:"
npx cdk list --context environment=dev

# Destroy the stack
echo "🗑️  Destroying stack..."
npx cdk destroy TechHealth-Dev-Infrastructure \
    --force \
    --context environment=dev

echo "✅ Development environment destroyed successfully!"
echo ""
echo "💰 Cost Savings: All AWS resources have been terminated to avoid ongoing charges."
echo ""
echo "🔄 To redeploy later, run:"
echo "   ./scripts/deploy-dev.sh"