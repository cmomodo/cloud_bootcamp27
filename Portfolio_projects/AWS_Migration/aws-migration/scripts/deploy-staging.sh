#!/bin/bash

# Deploy TechHealth Infrastructure to Staging Environment
# This script deploys the infrastructure stack to the staging environment

set -e  # Exit on any error

echo "🚀 Deploying TechHealth Infrastructure to Staging Environment"
echo "============================================================="

# Set environment variables
export ENVIRONMENT=staging
export CDK_DEFAULT_REGION=us-east-1

# Validate configuration
echo "📋 Validating staging configuration..."
if [ ! -f "config/staging.json" ]; then
    echo "❌ Error: Staging configuration file not found at config/staging.json"
    exit 1
fi

# Build the project
echo "🔨 Building TypeScript project..."
npm run build

# Run tests
echo "🧪 Running tests..."
npm test

# Synthesize CloudFormation template
echo "📄 Synthesizing CloudFormation template..."
npx cdk synth TechHealth-Staging-Infrastructure

# Deploy the stack with approval required for staging
echo "🚀 Deploying to AWS (approval required)..."
npx cdk deploy TechHealth-Staging-Infrastructure \
    --require-approval broadening \
    --context environment=staging \
    --outputs-file outputs-staging.json

echo "✅ Staging deployment completed successfully!"
echo ""
echo "📊 Stack Outputs:"
if [ -f "outputs-staging.json" ]; then
    cat outputs-staging.json | jq '.'
fi

echo ""
echo "💡 Next Steps:"
echo "   1. Run integration tests against staging environment"
echo "   2. Verify Multi-AZ database deployment"
echo "   3. Test application functionality"
echo "   4. Review monitoring dashboards"
echo "   5. Validate security group configurations"
echo ""
echo "🧹 To clean up resources later, run:"
echo "   ./scripts/destroy-staging.sh"