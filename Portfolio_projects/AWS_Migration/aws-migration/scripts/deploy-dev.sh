#!/bin/bash

# Deploy TechHealth Infrastructure to Development Environment
# This script deploys the infrastructure stack to the dev environment

set -e  # Exit on any error

echo "🚀 Deploying TechHealth Infrastructure to Development Environment"
echo "================================================================"

# Set environment variables
export ENVIRONMENT=dev
export CDK_DEFAULT_REGION=us-east-1

# Validate configuration
echo "📋 Validating development configuration..."
if [ ! -f "config/dev.json" ]; then
    echo "❌ Error: Development configuration file not found at config/dev.json"
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
npx cdk synth TechHealth-Dev-Infrastructure

# Deploy the stack
echo "🚀 Deploying to AWS..."
npx cdk deploy TechHealth-Dev-Infrastructure \
    --require-approval never \
    --context environment=dev \
    --outputs-file outputs-dev.json

echo "✅ Development deployment completed successfully!"
echo ""
echo "📊 Stack Outputs:"
if [ -f "outputs-dev.json" ]; then
    cat outputs-dev.json | jq '.'
fi

echo ""
echo "💡 Next Steps:"
echo "   1. Verify EC2 instances are running"
echo "   2. Test database connectivity"
echo "   3. Check CloudWatch logs"
echo "   4. Review cost estimates in AWS Cost Explorer"
echo ""
echo "🧹 To clean up resources later, run:"
echo "   ./scripts/destroy-dev.sh"