#!/bin/bash

# Deploy TechHealth Infrastructure to Production Environment
# This script deploys the infrastructure stack to the production environment

set -e  # Exit on any error

echo "🚀 Deploying TechHealth Infrastructure to Production Environment"
echo "================================================================"

# Set environment variables
export ENVIRONMENT=prod
export CDK_DEFAULT_REGION=us-east-1

# Validate configuration
echo "📋 Validating production configuration..."
if [ ! -f "config/prod.json" ]; then
    echo "❌ Error: Production configuration file not found at config/prod.json"
    exit 1
fi

# Additional production safety checks
echo "🔒 Running production safety checks..."

# Check if this is really production
read -p "⚠️  Are you sure you want to deploy to PRODUCTION? (type 'PRODUCTION' to confirm): " confirm
if [ "$confirm" != "PRODUCTION" ]; then
    echo "❌ Production deployment cancelled."
    exit 1
fi

# Verify AWS credentials are for production account
echo "🔍 Verifying AWS account..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Current AWS Account: $ACCOUNT_ID"

read -p "Is this the correct production account? (y/N): " account_confirm
if [ "$account_confirm" != "y" ] && [ "$account_confirm" != "Y" ]; then
    echo "❌ Production deployment cancelled - wrong AWS account."
    exit 1
fi

# Build the project
echo "🔨 Building TypeScript project..."
npm run build

# Run comprehensive tests
echo "🧪 Running comprehensive test suite..."
npm test

# Run security checks (if available)
if command -v checkov &> /dev/null; then
    echo "🔐 Running security checks with Checkov..."
    npx cdk synth TechHealth-Prod-Infrastructure --quiet
    checkov -d cdk.out --framework cloudformation
fi

# Synthesize CloudFormation template
echo "📄 Synthesizing CloudFormation template..."
npx cdk synth TechHealth-Prod-Infrastructure

# Final confirmation
echo ""
echo "🚨 FINAL PRODUCTION DEPLOYMENT CONFIRMATION"
echo "==========================================="
echo "Environment: PRODUCTION"
echo "Region: $CDK_DEFAULT_REGION"
echo "Account: $ACCOUNT_ID"
echo ""
read -p "Proceed with production deployment? (type 'DEPLOY' to confirm): " final_confirm
if [ "$final_confirm" != "DEPLOY" ]; then
    echo "❌ Production deployment cancelled."
    exit 1
fi

# Deploy the stack with strict approval requirements
echo "🚀 Deploying to AWS (strict approval required)..."
npx cdk deploy TechHealth-Prod-Infrastructure \
    --require-approval broadening \
    --context environment=prod \
    --outputs-file outputs-prod.json \
    --rollback false

echo "✅ Production deployment completed successfully!"
echo ""
echo "📊 Stack Outputs:"
if [ -f "outputs-prod.json" ]; then
    cat outputs-prod.json | jq '.'
fi

echo ""
echo "🎉 PRODUCTION DEPLOYMENT COMPLETE!"
echo "================================="
echo ""
echo "💡 Post-Deployment Checklist:"
echo "   ✓ Verify all resources are healthy"
echo "   ✓ Test application functionality"
echo "   ✓ Confirm database connectivity"
echo "   ✓ Validate security configurations"
echo "   ✓ Check monitoring and alerting"
echo "   ✓ Review backup configurations"
echo "   ✓ Validate HIPAA compliance settings"
echo ""
echo "📞 Support: Contact DevOps team if any issues arise"