#!/bin/bash

# Stack Update Script for TechHealth Infrastructure
# This script safely updates existing infrastructure with change validation

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Function to display usage
usage() {
    echo "Usage: $0 <environment> [options]"
    echo ""
    echo "Environments:"
    echo "  dev       - Development environment"
    echo "  staging   - Staging environment"
    echo "  prod      - Production environment"
    echo ""
    echo "Options:"
    echo "  --dry-run     Show changes without applying them"
    echo "  --auto-approve Skip change approval for dev environment"
    echo "  --help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 dev --auto-approve"
    echo "  $0 staging --dry-run"
    echo "  $0 prod"
    exit 1
}

# Parse command line arguments
ENVIRONMENT=""
DRY_RUN=false
AUTO_APPROVE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        dev|staging|prod)
            ENVIRONMENT="$1"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

if [ -z "$ENVIRONMENT" ]; then
    echo "Error: Environment is required"
    usage
fi

# Set environment variables
export ENVIRONMENT
export CDK_DEFAULT_REGION=us-east-1

echo "🔄 TechHealth Infrastructure Stack Update"
echo "========================================="
echo "Environment: $ENVIRONMENT"
echo "Dry Run: $DRY_RUN"
echo "Auto Approve: $AUTO_APPROVE"
echo ""

# Validate configuration file exists
CONFIG_FILE="config/${ENVIRONMENT}.json"
if [ ! -f "$CONFIG_FILE" ]; then
    print_error "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

print_success "Configuration file found: $CONFIG_FILE"

# Build the project
print_status "Building TypeScript project..."
npm run build

# Run tests
print_status "Running tests..."
npm test

# Show current stack status
print_status "Checking current stack status..."
STACK_NAME="TechHealth-$(echo $ENVIRONMENT | sed 's/.*/\u&/')-Infrastructure"

if cdk list --context environment=$ENVIRONMENT | grep -q "$STACK_NAME"; then
    print_success "Stack $STACK_NAME exists and can be updated"
else
    print_error "Stack $STACK_NAME does not exist. Use deploy script instead."
    exit 1
fi

# Generate diff to show changes
print_status "Generating change diff..."
echo ""
echo "📋 Proposed Changes:"
echo "==================="

cdk diff $STACK_NAME --context environment=$ENVIRONMENT

DIFF_EXIT_CODE=$?

if [ $DIFF_EXIT_CODE -eq 0 ]; then
    print_warning "No changes detected in the stack"
    echo "The current deployed stack matches the local configuration."
    exit 0
elif [ $DIFF_EXIT_CODE -eq 1 ]; then
    print_status "Changes detected and displayed above"
else
    print_error "Error generating diff"
    exit 1
fi

# If dry run, exit here
if [ "$DRY_RUN" = true ]; then
    print_status "Dry run completed. No changes were applied."
    exit 0
fi

# Approval logic based on environment
if [ "$ENVIRONMENT" = "prod" ]; then
    echo ""
    print_warning "PRODUCTION UPDATE CONFIRMATION REQUIRED"
    echo "======================================="
    echo ""
    read -p "⚠️  Are you sure you want to update PRODUCTION? (type 'UPDATE PRODUCTION' to confirm): " confirm
    if [ "$confirm" != "UPDATE PRODUCTION" ]; then
        print_error "Production update cancelled."
        exit 1
    fi
    
    # Additional production safety check
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    echo "Current AWS Account: $ACCOUNT_ID"
    read -p "Is this the correct production account? (y/N): " account_confirm
    if [ "$account_confirm" != "y" ] && [ "$account_confirm" != "Y" ]; then
        print_error "Production update cancelled - wrong AWS account."
        exit 1
    fi
    
    APPROVAL_FLAG="--require-approval broadening"
elif [ "$ENVIRONMENT" = "staging" ]; then
    if [ "$AUTO_APPROVE" != true ]; then
        echo ""
        read -p "Apply these changes to staging? (y/N): " confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            print_error "Staging update cancelled."
            exit 1
        fi
    fi
    APPROVAL_FLAG="--require-approval broadening"
else
    # Development environment
    if [ "$AUTO_APPROVE" != true ]; then
        echo ""
        read -p "Apply these changes to development? (y/N): " confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            print_error "Development update cancelled."
            exit 1
        fi
    fi
    APPROVAL_FLAG="--require-approval never"
fi

# Apply the update
print_status "Applying stack update..."
echo ""

cdk deploy $STACK_NAME \
    $APPROVAL_FLAG \
    --context environment=$ENVIRONMENT \
    --outputs-file "outputs-${ENVIRONMENT}-update.json" \
    --progress events

UPDATE_EXIT_CODE=$?

if [ $UPDATE_EXIT_CODE -eq 0 ]; then
    print_success "Stack update completed successfully!"
    
    # Display outputs if available
    OUTPUT_FILE="outputs-${ENVIRONMENT}-update.json"
    if [ -f "$OUTPUT_FILE" ]; then
        echo ""
        echo "📊 Updated Stack Outputs:"
        cat "$OUTPUT_FILE" | jq '.'
    fi
    
    echo ""
    print_success "✅ $ENVIRONMENT environment updated successfully!"
    
    # Environment-specific post-update recommendations
    case $ENVIRONMENT in
        dev)
            echo ""
            echo "💡 Next Steps for Development:"
            echo "   1. Run connectivity tests"
            echo "   2. Verify application functionality"
            echo "   3. Check CloudWatch logs"
            ;;
        staging)
            echo ""
            echo "💡 Next Steps for Staging:"
            echo "   1. Run full integration test suite"
            echo "   2. Verify Multi-AZ database functionality"
            echo "   3. Test application end-to-end"
            echo "   4. Validate monitoring dashboards"
            ;;
        prod)
            echo ""
            echo "💡 Next Steps for Production:"
            echo "   1. Monitor application health closely"
            echo "   2. Verify all services are operational"
            echo "   3. Check patient portal functionality"
            echo "   4. Review monitoring alerts"
            echo "   5. Validate backup systems"
            echo "   6. Notify stakeholders of successful update"
            ;;
    esac
    
else
    print_error "Stack update failed!"
    echo ""
    echo "🔧 Troubleshooting Steps:"
    echo "   1. Check CloudFormation console for detailed error messages"
    echo "   2. Review CloudWatch logs for application errors"
    echo "   3. Verify IAM permissions are sufficient"
    echo "   4. Check for resource limits or quotas"
    echo ""
    echo "🔄 To rollback if needed, run:"
    echo "   ./scripts/rollback-stack.sh $ENVIRONMENT"
    
    exit 1
fi