#!/bin/bash

# AWS Security Stack Deployment Script
# This script handles environment-specific deployment of the AWS security implementation

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT="production"
SKIP_TESTS=false
SKIP_VALIDATION=false
AUTO_APPROVE=false
VERBOSE=false

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    cat << EOF
AWS Security Stack Deployment Script

Usage: $0 [OPTIONS]

Options:
    -e, --environment ENV    Target environment (production, staging, development) [default: production]
    -s, --skip-tests        Skip unit tests before deployment
    -v, --skip-validation   Skip post-deployment validation
    -y, --auto-approve      Auto-approve CDK deployment (use with caution)
    --verbose               Enable verbose output
    -h, --help              Show this help message

Examples:
    $0                                    # Deploy to production with all checks
    $0 -e staging -s                      # Deploy to staging, skip tests
    $0 -e development -y --verbose        # Deploy to dev with auto-approve and verbose output

Environment Configuration:
    - production: Full security policies, all users, MFA required
    - staging: Reduced user set, relaxed policies for testing
    - development: Minimal setup for development work

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -s|--skip-tests)
            SKIP_TESTS=true
            shift
            ;;
        -v|--skip-validation)
            SKIP_VALIDATION=true
            shift
            ;;
        -y|--auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(production|staging|development)$ ]]; then
    print_error "Invalid environment: $ENVIRONMENT"
    print_error "Valid environments: production, staging, development"
    exit 1
fi

print_status "Starting deployment to $ENVIRONMENT environment"

# Check prerequisites
print_status "Checking prerequisites..."

# Check if AWS CLI is installed and configured
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS credentials not configured or invalid."
    print_error "Please run 'aws configure' or set AWS environment variables."
    exit 1
fi

# Check if CDK is installed
if ! command -v cdk &> /dev/null; then
    print_error "AWS CDK is not installed. Please install it with: npm install -g aws-cdk"
    exit 1
fi

# Check if Node.js and npm are available
if ! command -v node &> /dev/null || ! command -v npm &> /dev/null; then
    print_error "Node.js and npm are required but not installed."
    exit 1
fi

print_success "Prerequisites check passed"

# Get AWS account info
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region || echo "us-east-1")
print_status "Deploying to AWS Account: $AWS_ACCOUNT in region: $AWS_REGION"

# Install dependencies
print_status "Installing dependencies..."
npm install
if [ $? -ne 0 ]; then
    print_error "Failed to install dependencies"
    exit 1
fi

# Run tests unless skipped
if [ "$SKIP_TESTS" = false ]; then
    print_status "Running unit tests..."
    npm test
    if [ $? -ne 0 ]; then
        print_error "Unit tests failed. Use --skip-tests to bypass."
        exit 1
    fi
    print_success "Unit tests passed"
else
    print_warning "Skipping unit tests"
fi

# Build the project
print_status "Building TypeScript project..."
npm run build
if [ $? -ne 0 ]; then
    print_error "Build failed"
    exit 1
fi

# Generate environment-specific configuration
print_status "Generating environment configuration..."
cat > cdk.context.json << EOF
{
  "environment": "$ENVIRONMENT",
  "aws-account": "$AWS_ACCOUNT",
  "aws-region": "$AWS_REGION",
  "stack-name": "AwsSecurityStack-$ENVIRONMENT",
  "team-size": {
    "production": {
      "developers": 3,
      "operations": 2,
      "finance": 2,
      "analysts": 3
    },
    "staging": {
      "developers": 2,
      "operations": 1,
      "finance": 1,
      "analysts": 1
    },
    "development": {
      "developers": 1,
      "operations": 1,
      "finance": 1,
      "analysts": 1
    }
  }
}
EOF

# Bootstrap CDK if needed
print_status "Checking CDK bootstrap status..."
if ! aws cloudformation describe-stacks --stack-name CDKToolkit --region $AWS_REGION &> /dev/null; then
    print_status "Bootstrapping CDK..."
    cdk bootstrap aws://$AWS_ACCOUNT/$AWS_REGION
    if [ $? -ne 0 ]; then
        print_error "CDK bootstrap failed"
        exit 1
    fi
    print_success "CDK bootstrap completed"
else
    print_status "CDK already bootstrapped"
fi

# Synthesize the stack
print_status "Synthesizing CloudFormation template..."
if [ "$VERBOSE" = true ]; then
    cdk synth --verbose
else
    cdk synth > /dev/null
fi

if [ $? -ne 0 ]; then
    print_error "CDK synthesis failed"
    exit 1
fi

# Show diff if stack already exists
print_status "Checking for changes..."
if aws cloudformation describe-stacks --stack-name "AwsSecurityStack-$ENVIRONMENT" --region $AWS_REGION &> /dev/null; then
    print_status "Stack exists, showing differences..."
    cdk diff
else
    print_status "New stack deployment"
fi

# Deploy the stack
print_status "Deploying stack..."
DEPLOY_CMD="cdk deploy"

if [ "$AUTO_APPROVE" = true ]; then
    DEPLOY_CMD="$DEPLOY_CMD --require-approval never"
    print_warning "Auto-approval enabled - deployment will proceed without confirmation"
fi

if [ "$VERBOSE" = true ]; then
    DEPLOY_CMD="$DEPLOY_CMD --verbose"
fi

# Add environment-specific stack name
DEPLOY_CMD="$DEPLOY_CMD AwsSecurityStack-$ENVIRONMENT"

print_status "Executing: $DEPLOY_CMD"
eval $DEPLOY_CMD

if [ $? -ne 0 ]; then
    print_error "Deployment failed"
    exit 1
fi

print_success "Stack deployment completed successfully"

# Post-deployment validation
if [ "$SKIP_VALIDATION" = false ]; then
    print_status "Running post-deployment validation..."
    
    # Run validation script
    if [ -f "scripts/validate-deployment.sh" ]; then
        bash scripts/validate-deployment.sh --environment $ENVIRONMENT
        if [ $? -ne 0 ]; then
            print_warning "Post-deployment validation failed"
            print_warning "Stack deployed successfully but validation issues detected"
        else
            print_success "Post-deployment validation passed"
        fi
    else
        print_warning "Validation script not found, skipping validation"
    fi
else
    print_warning "Skipping post-deployment validation"
fi

# Generate deployment report
print_status "Generating deployment report..."
REPORT_FILE="deployment-report-$(date +%Y%m%d-%H%M%S).txt"

cat > $REPORT_FILE << EOF
AWS Security Stack Deployment Report
====================================

Deployment Details:
- Environment: $ENVIRONMENT
- AWS Account: $AWS_ACCOUNT
- AWS Region: $AWS_REGION
- Stack Name: AwsSecurityStack-$ENVIRONMENT
- Deployment Time: $(date)
- Deployed By: $(aws sts get-caller-identity --query Arn --output text)

Stack Outputs:
$(aws cloudformation describe-stacks --stack-name "AwsSecurityStack-$ENVIRONMENT" --region $AWS_REGION --query 'Stacks[0].Outputs' --output table 2>/dev/null || echo "No outputs available")

Resources Created:
$(aws cloudformation list-stack-resources --stack-name "AwsSecurityStack-$ENVIRONMENT" --region $AWS_REGION --query 'StackResourceSummaries[].{Type:ResourceType,Status:ResourceStatus}' --output table 2>/dev/null || echo "Unable to list resources")

Next Steps:
1. Configure MFA for all IAM users
2. Distribute initial passwords securely
3. Test user permissions
4. Set up monitoring and alerts
5. Schedule regular security reviews

EOF

print_success "Deployment report saved to: $REPORT_FILE"

# Final summary
print_success "🎉 Deployment completed successfully!"
echo
print_status "Summary:"
echo "  ✅ Environment: $ENVIRONMENT"
echo "  ✅ Stack: AwsSecurityStack-$ENVIRONMENT"
echo "  ✅ Account: $AWS_ACCOUNT"
echo "  ✅ Region: $AWS_REGION"
echo
print_status "Next steps:"
echo "  1. Review the deployment report: $REPORT_FILE"
echo "  2. Configure MFA for all users (see docs/root-account-security-guide.md)"
echo "  3. Test user permissions with validation scripts"
echo "  4. Set up monitoring and alerts"
echo
print_warning "Important: Secure the AWS root account immediately if not already done!"

exit 0