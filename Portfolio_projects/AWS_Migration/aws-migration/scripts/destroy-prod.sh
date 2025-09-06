#!/bin/bash

# Destroy TechHealth Infrastructure in Production Environment
# This script safely destroys the production environment with extensive safety checks

set -e  # Exit on any error

echo "🚨 PRODUCTION ENVIRONMENT DESTRUCTION"
echo "====================================="
echo ""
echo "⚠️  WARNING: This will destroy ALL resources in the PRODUCTION environment!"
echo "⚠️  This action is IRREVERSIBLE and will result in DATA LOSS!"
echo ""

# Set environment variables
export ENVIRONMENT=prod
export CDK_DEFAULT_REGION=us-east-1

# Verify AWS credentials are for production account
echo "🔍 Verifying AWS account..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Current AWS Account: $ACCOUNT_ID"

read -p "Is this the correct production account? (y/N): " account_confirm
if [ "$account_confirm" != "y" ] && [ "$account_confirm" != "Y" ]; then
    echo "❌ Production destruction cancelled - wrong AWS account."
    exit 1
fi

# List resources that will be destroyed
echo ""
echo "📋 Resources to be destroyed:"
npx cdk list --context environment=prod

# Multiple confirmation steps
echo ""
echo "🚨 CRITICAL CONFIRMATION REQUIRED"
echo "================================="
echo ""
echo "This will permanently destroy:"
echo "- All EC2 instances and their data"
echo "- RDS database and ALL patient data"
echo "- VPC and networking configuration"
echo "- Security groups and IAM roles"
echo "- CloudWatch logs and metrics"
echo ""

read -p "Type 'I UNDERSTAND THE RISKS' to continue: " risk_confirm
if [ "$risk_confirm" != "I UNDERSTAND THE RISKS" ]; then
    echo "❌ Production destruction cancelled."
    exit 1
fi

read -p "Type the production account ID ($ACCOUNT_ID) to confirm: " account_id_confirm
if [ "$account_id_confirm" != "$ACCOUNT_ID" ]; then
    echo "❌ Production destruction cancelled - account ID mismatch."
    exit 1
fi

read -p "Type 'DESTROY PRODUCTION' to proceed: " final_confirm
if [ "$final_confirm" != "DESTROY PRODUCTION" ]; then
    echo "❌ Production destruction cancelled."
    exit 1
fi

# Final countdown
echo ""
echo "🚨 FINAL WARNING: Destroying production in 10 seconds..."
echo "Press Ctrl+C to cancel!"
for i in {10..1}; do
    echo "Destroying in $i seconds..."
    sleep 1
done

# Destroy the stack
echo ""
echo "🗑️  Destroying production stack..."
npx cdk destroy TechHealth-Prod-Infrastructure \
    --force \
    --context environment=prod

echo ""
echo "💥 PRODUCTION ENVIRONMENT DESTROYED"
echo "==================================="
echo ""
echo "⚠️  All production resources have been permanently deleted."
echo "⚠️  Patient data and application state have been lost."
echo ""
echo "📞 Next Steps:"
echo "   1. Notify all stakeholders immediately"
echo "   2. Begin disaster recovery procedures if applicable"
echo "   3. Review incident response protocols"
echo ""
echo "🔄 To redeploy production, run:"
echo "   ./scripts/deploy-prod.sh"