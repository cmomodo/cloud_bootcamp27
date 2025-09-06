#!/bin/bash

# Destroy TechHealth Infrastructure in Staging Environment
# This script safely destroys the staging environment

set -e  # Exit on any error

echo "🧹 Destroying TechHealth Infrastructure in Staging Environment"
echo "=============================================================="

# Set environment variables
export ENVIRONMENT=staging
export CDK_DEFAULT_REGION=us-east-1

# Enhanced confirmation for staging
echo "⚠️  This will destroy ALL resources in the STAGING environment!"
echo "This action cannot be undone and will affect staging testing."
echo ""
echo "Resources to be destroyed:"
npx cdk list --context environment=staging

echo ""
read -p "Are you sure you want to destroy the staging environment? (type 'destroy-staging' to confirm): " confirm
if [ "$confirm" != "destroy-staging" ]; then
    echo "❌ Destruction cancelled."
    exit 1
fi

# Additional safety check
read -p "This will impact staging testing. Continue? (y/N): " final_confirm
if [ "$final_confirm" != "y" ] && [ "$final_confirm" != "Y" ]; then
    echo "❌ Destruction cancelled."
    exit 1
fi

# Destroy the stack
echo "🗑️  Destroying staging stack..."
npx cdk destroy TechHealth-Staging-Infrastructure \
    --force \
    --context environment=staging

echo "✅ Staging environment destroyed successfully!"
echo ""
echo "💰 Cost Savings: All AWS resources have been terminated to avoid ongoing charges."
echo ""
echo "🔄 To redeploy later, run:"
echo "   ./scripts/deploy-staging.sh"