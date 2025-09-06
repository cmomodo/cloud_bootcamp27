#!/bin/bash

# Stack Rollback Script for TechHealth Infrastructure
# This script safely rolls back infrastructure changes to the previous stable state

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
    echo "  --list-events    Show recent CloudFormation events"
    echo "  --force          Skip confirmation prompts (dev only)"
    echo "  --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 dev --force"
    echo "  $0 staging --list-events"
    echo "  $0 prod"
    exit 1
}

# Parse command line arguments
ENVIRONMENT=""
LIST_EVENTS=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        dev|staging|prod)
            ENVIRONMENT="$1"
            shift
            ;;
        --list-events)
            LIST_EVENTS=true
            shift
            ;;
        --force)
            FORCE=true
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

echo "🔄 TechHealth Infrastructure Stack Rollback"
echo "==========================================="
echo "Environment: $ENVIRONMENT"
echo ""

STACK_NAME="TechHealth-$(echo $ENVIRONMENT | sed 's/.*/\u&/')-Infrastructure"

# Check if stack exists
print_status "Checking stack status..."
if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" &>/dev/null; then
    print_error "Stack $STACK_NAME does not exist"
    exit 1
fi

# Get current stack status
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].StackStatus' --output text)
print_status "Current stack status: $STACK_STATUS"

# Check if rollback is possible
case $STACK_STATUS in
    "UPDATE_FAILED"|"UPDATE_ROLLBACK_FAILED"|"CREATE_FAILED")
        print_warning "Stack is in a failed state: $STACK_STATUS"
        print_status "Rollback operation will attempt to restore to previous stable state"
        ;;
    "UPDATE_COMPLETE"|"CREATE_COMPLETE")
        print_warning "Stack is in a stable state: $STACK_STATUS"
        print_status "This will rollback to the previous version"
        ;;
    "UPDATE_IN_PROGRESS"|"UPDATE_ROLLBACK_IN_PROGRESS"|"DELETE_IN_PROGRESS")
        print_error "Stack is currently being modified: $STACK_STATUS"
        print_error "Wait for the current operation to complete before attempting rollback"
        exit 1
        ;;
    *)
        print_warning "Unexpected stack status: $STACK_STATUS"
        print_status "Proceeding with caution..."
        ;;
esac

# List recent events if requested
if [ "$LIST_EVENTS" = true ]; then
    echo ""
    print_status "Recent CloudFormation events:"
    echo "=============================="
    aws cloudformation describe-stack-events \
        --stack-name "$STACK_NAME" \
        --max-items 20 \
        --query 'StackEvents[*].[Timestamp,ResourceStatus,ResourceType,LogicalResourceId,ResourceStatusReason]' \
        --output table
    echo ""
fi

# Get stack creation time and last update time
CREATION_TIME=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].CreationTime' --output text)
LAST_UPDATE=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].LastUpdatedTime' --output text 2>/dev/null || echo "Never")

echo ""
print_status "Stack Information:"
echo "  Created: $CREATION_TIME"
echo "  Last Updated: $LAST_UPDATE"
echo ""

# Environment-specific confirmation
if [ "$ENVIRONMENT" = "prod" ]; then
    print_warning "🚨 PRODUCTION ROLLBACK CONFIRMATION"
    echo "===================================="
    echo ""
    echo "⚠️  This will rollback PRODUCTION infrastructure!"
    echo "⚠️  This may cause service disruption!"
    echo ""
    
    # Verify AWS account
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    echo "Current AWS Account: $ACCOUNT_ID"
    read -p "Is this the correct production account? (y/N): " account_confirm
    if [ "$account_confirm" != "y" ] && [ "$account_confirm" != "Y" ]; then
        print_error "Production rollback cancelled - wrong AWS account."
        exit 1
    fi
    
    read -p "Type 'ROLLBACK PRODUCTION' to confirm: " confirm
    if [ "$confirm" != "ROLLBACK PRODUCTION" ]; then
        print_error "Production rollback cancelled."
        exit 1
    fi
    
elif [ "$ENVIRONMENT" = "staging" ]; then
    if [ "$FORCE" != true ]; then
        echo ""
        read -p "⚠️  Rollback staging environment? This may disrupt testing. (y/N): " confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            print_error "Staging rollback cancelled."
            exit 1
        fi
    fi
    
else
    # Development environment
    if [ "$FORCE" != true ]; then
        echo ""
        read -p "Rollback development environment? (y/N): " confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            print_error "Development rollback cancelled."
            exit 1
        fi
    fi
fi

# Attempt rollback
print_status "Initiating stack rollback..."
echo ""

# Use CloudFormation continue-update-rollback for failed updates, or cancel-update-stack for in-progress updates
case $STACK_STATUS in
    "UPDATE_FAILED"|"UPDATE_ROLLBACK_FAILED")
        print_status "Using continue-update-rollback for failed stack..."
        aws cloudformation continue-update-rollback --stack-name "$STACK_NAME"
        ;;
    "UPDATE_IN_PROGRESS")
        print_status "Cancelling in-progress update..."
        aws cloudformation cancel-update-stack --stack-name "$STACK_NAME"
        ;;
    *)
        print_warning "Stack is in stable state. Manual rollback required."
        print_status "To rollback to a previous version, you need to:"
        echo "  1. Identify the previous working configuration"
        echo "  2. Update your CDK code to match that configuration"
        echo "  3. Run the update script: ./scripts/update-stack.sh $ENVIRONMENT"
        echo ""
        print_error "Automatic rollback not available for stable stacks"
        exit 1
        ;;
esac

# Wait for rollback to complete
print_status "Waiting for rollback to complete..."
aws cloudformation wait stack-update-complete --stack-name "$STACK_NAME" || {
    print_error "Rollback operation failed or timed out"
    
    echo ""
    print_status "Recent events during rollback:"
    aws cloudformation describe-stack-events \
        --stack-name "$STACK_NAME" \
        --max-items 10 \
        --query 'StackEvents[*].[Timestamp,ResourceStatus,ResourceType,LogicalResourceId,ResourceStatusReason]' \
        --output table
    
    exit 1
}

# Verify rollback success
FINAL_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].StackStatus' --output text)

if [[ "$FINAL_STATUS" == *"COMPLETE"* ]]; then
    print_success "✅ Stack rollback completed successfully!"
    print_status "Final stack status: $FINAL_STATUS"
    
    echo ""
    echo "📊 Stack Information After Rollback:"
    aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query 'Stacks[0].[StackName,StackStatus,CreationTime,LastUpdatedTime]' \
        --output table
    
    # Environment-specific post-rollback steps
    case $ENVIRONMENT in
        dev)
            echo ""
            echo "💡 Post-Rollback Steps for Development:"
            echo "   1. Verify application functionality"
            echo "   2. Run connectivity tests"
            echo "   3. Check for any configuration drift"
            ;;
        staging)
            echo ""
            echo "💡 Post-Rollback Steps for Staging:"
            echo "   1. Run full integration test suite"
            echo "   2. Verify all services are operational"
            echo "   3. Notify testing teams of rollback"
            echo "   4. Review what caused the need for rollback"
            ;;
        prod)
            echo ""
            echo "💡 Post-Rollback Steps for Production:"
            echo "   1. Verify patient portal is operational"
            echo "   2. Check all critical services"
            echo "   3. Monitor application health closely"
            echo "   4. Notify stakeholders of rollback completion"
            echo "   5. Conduct post-incident review"
            echo "   6. Document lessons learned"
            ;;
    esac
    
else
    print_error "❌ Stack rollback failed!"
    print_error "Final stack status: $FINAL_STATUS"
    
    echo ""
    print_status "Recent events:"
    aws cloudformation describe-stack-events \
        --stack-name "$STACK_NAME" \
        --max-items 10 \
        --query 'StackEvents[*].[Timestamp,ResourceStatus,ResourceType,LogicalResourceId,ResourceStatusReason]' \
        --output table
    
    echo ""
    echo "🆘 Emergency Procedures:"
    echo "   1. Contact AWS Support if stack is in an unrecoverable state"
    echo "   2. Review CloudFormation console for detailed error information"
    echo "   3. Consider manual resource cleanup if necessary"
    echo "   4. Escalate to senior DevOps team members"
    
    exit 1
fi