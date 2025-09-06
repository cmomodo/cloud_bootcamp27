#!/bin/bash

# AWS IAM Permission Testing Script
# This script tests IAM permissions using AWS policy simulation

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
USER=""
ROLE=""
INTERACTIVE=false
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
AWS IAM Permission Testing Script

Usage: $0 [OPTIONS]

Options:
    -u, --user USER         Test permissions for specific IAM user
    -r, --role ROLE         Test permissions for specific role (developer, operations, finance, analyst)
    -i, --interactive       Interactive mode for custom permission testing
    --verbose               Enable verbose output
    -h, --help              Show this help message

Examples:
    $0 -u dev1                           # Test permissions for user dev1
    $0 -r developer                      # Test all developer permissions
    $0 -i                                # Interactive permission testing
    $0 -r operations --verbose           # Test operations permissions with verbose output

Role Options:
    developer    - Test developer team permissions
    operations   - Test operations team permissions  
    finance      - Test finance team permissions
    analyst      - Test analyst team permissions
    all          - Test all role permissions

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--user)
            USER="$2"
            shift 2
            ;;
        -r|--role)
            ROLE="$2"
            shift 2
            ;;
        -i|--interactive)
            INTERACTIVE=true
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

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Function to test a specific permission
test_permission() {
    local principal_arn="$1"
    local action="$2"
    local resource="$3"
    local description="$4"
    
    local result
    result=$(aws iam simulate-principal-policy \
        --policy-source-arn "$principal_arn" \
        --action-names "$action" \
        --resource-arns "$resource" \
        --query 'EvaluationResults[0].EvalDecision' \
        --output text 2>/dev/null)
    
    if [ "$result" = "allowed" ]; then
        print_success "✅ $description"
        if [ "$VERBOSE" = true ]; then
            echo "   Action: $action"
            echo "   Resource: $resource"
            echo "   Result: ALLOWED"
        fi
        return 0
    else
        print_error "❌ $description"
        if [ "$VERBOSE" = true ]; then
            echo "   Action: $action"
            echo "   Resource: $resource"
            echo "   Result: $result"
        fi
        return 1
    fi
}

# Function to test developer permissions
test_developer_permissions() {
    local user_arn="$1"
    local username=$(basename "$user_arn")
    
    print_status "🔧 Testing Developer Permissions for $username"
    
    # EC2 permissions
    test_permission "$user_arn" "ec2:DescribeInstances" "*" "Can describe EC2 instances"
    test_permission "$user_arn" "ec2:StartInstances" "*" "Can start EC2 instances"
    test_permission "$user_arn" "ec2:StopInstances" "*" "Can stop EC2 instances"
    test_permission "$user_arn" "ec2:RebootInstances" "*" "Can reboot EC2 instances"
    
    # S3 permissions (app buckets)
    test_permission "$user_arn" "s3:ListBucket" "arn:aws:s3:::app-*" "Can list app S3 buckets"
    test_permission "$user_arn" "s3:GetObject" "arn:aws:s3:::app-*/*" "Can read from app S3 buckets"
    test_permission "$user_arn" "s3:PutObject" "arn:aws:s3:::app-*/*" "Can write to app S3 buckets"
    
    # CloudWatch Logs permissions
    test_permission "$user_arn" "logs:DescribeLogGroups" "*" "Can describe CloudWatch log groups"
    test_permission "$user_arn" "logs:GetLogEvents" "*" "Can read CloudWatch log events"
    
    # Should NOT have these permissions
    print_status "🚫 Testing Restricted Permissions (should fail)"
    if aws iam simulate-principal-policy --policy-source-arn "$user_arn" --action-names "iam:CreateUser" --resource-arns "*" --query 'EvaluationResults[0].EvalDecision' --output text 2>/dev/null | grep -q "allowed"; then
        print_error "❌ Developer should NOT be able to create IAM users"
    else
        print_success "✅ Developer correctly cannot create IAM users"
    fi
    
    if aws iam simulate-principal-policy --policy-source-arn "$user_arn" --action-names "rds:CreateDBInstance" --resource-arns "*" --query 'EvaluationResults[0].EvalDecision' --output text 2>/dev/null | grep -q "allowed"; then
        print_error "❌ Developer should NOT be able to create RDS instances"
    else
        print_success "✅ Developer correctly cannot create RDS instances"
    fi
}

# Function to test operations permissions
test_operations_permissions() {
    local user_arn="$1"
    local username=$(basename "$user_arn")
    
    print_status "⚙️ Testing Operations Permissions for $username"
    
    # Full EC2 permissions
    test_permission "$user_arn" "ec2:*" "*" "Has full EC2 permissions"
    
    # CloudWatch permissions
    test_permission "$user_arn" "cloudwatch:*" "*" "Has full CloudWatch permissions"
    test_permission "$user_arn" "logs:*" "*" "Has full CloudWatch Logs permissions"
    
    # Systems Manager permissions
    test_permission "$user_arn" "ssm:*" "*" "Has full Systems Manager permissions"
    
    # RDS permissions
    test_permission "$user_arn" "rds:*" "*" "Has full RDS permissions"
    
    # Should NOT have these permissions
    print_status "🚫 Testing Restricted Permissions (should fail)"
    if aws iam simulate-principal-policy --policy-source-arn "$user_arn" --action-names "iam:CreateUser" --resource-arns "*" --query 'EvaluationResults[0].EvalDecision' --output text 2>/dev/null | grep -q "allowed"; then
        print_error "❌ Operations should NOT be able to create IAM users"
    else
        print_success "✅ Operations correctly cannot create IAM users"
    fi
}

# Function to test finance permissions
test_finance_permissions() {
    local user_arn="$1"
    local username=$(basename "$user_arn")
    
    print_status "💰 Testing Finance Permissions for $username"
    
    # Cost Explorer permissions
    test_permission "$user_arn" "ce:GetCostAndUsage" "*" "Can access Cost Explorer"
    test_permission "$user_arn" "ce:GetUsageReport" "*" "Can get usage reports"
    
    # Budgets permissions
    test_permission "$user_arn" "budgets:ViewBudget" "*" "Can view budgets"
    test_permission "$user_arn" "budgets:ModifyBudget" "*" "Can modify budgets"
    
    # Read-only resource access
    test_permission "$user_arn" "ec2:Describe*" "*" "Can describe EC2 resources"
    test_permission "$user_arn" "s3:ListAllMyBuckets" "*" "Can list S3 buckets"
    test_permission "$user_arn" "rds:Describe*" "*" "Can describe RDS resources"
    
    # Should NOT have these permissions
    print_status "🚫 Testing Restricted Permissions (should fail)"
    if aws iam simulate-principal-policy --policy-source-arn "$user_arn" --action-names "ec2:RunInstances" --resource-arns "*" --query 'EvaluationResults[0].EvalDecision' --output text 2>/dev/null | grep -q "allowed"; then
        print_error "❌ Finance should NOT be able to run EC2 instances"
    else
        print_success "✅ Finance correctly cannot run EC2 instances"
    fi
}

# Function to test analyst permissions
test_analyst_permissions() {
    local user_arn="$1"
    local username=$(basename "$user_arn")
    
    print_status "📊 Testing Analyst Permissions for $username"
    
    # S3 data bucket permissions (read-only)
    test_permission "$user_arn" "s3:ListBucket" "arn:aws:s3:::data-*" "Can list data S3 buckets"
    test_permission "$user_arn" "s3:GetObject" "arn:aws:s3:::data-*/*" "Can read from data S3 buckets"
    
    # CloudWatch metrics permissions
    test_permission "$user_arn" "cloudwatch:GetMetricStatistics" "*" "Can get CloudWatch metrics"
    test_permission "$user_arn" "cloudwatch:ListMetrics" "*" "Can list CloudWatch metrics"
    
    # Read-only database permissions
    test_permission "$user_arn" "rds:DescribeDBInstances" "*" "Can describe RDS instances"
    test_permission "$user_arn" "rds:DescribeDBClusters" "*" "Can describe RDS clusters"
    
    # Should NOT have these permissions
    print_status "🚫 Testing Restricted Permissions (should fail)"
    if aws iam simulate-principal-policy --policy-source-arn "$user_arn" --action-names "s3:PutObject" --resource-arns "arn:aws:s3:::data-*/*" --query 'EvaluationResults[0].EvalDecision' --output text 2>/dev/null | grep -q "allowed"; then
        print_error "❌ Analyst should NOT be able to write to data buckets"
    else
        print_success "✅ Analyst correctly cannot write to data buckets"
    fi
    
    if aws iam simulate-principal-policy --policy-source-arn "$user_arn" --action-names "ec2:RunInstances" --resource-arns "*" --query 'EvaluationResults[0].EvalDecision' --output text 2>/dev/null | grep -q "allowed"; then
        print_error "❌ Analyst should NOT be able to run EC2 instances"
    else
        print_success "✅ Analyst correctly cannot run EC2 instances"
    fi
}

# Interactive mode
interactive_mode() {
    print_status "🎯 Interactive Permission Testing Mode"
    echo
    
    while true; do
        echo "Select an option:"
        echo "1. Test specific user"
        echo "2. Test by role"
        echo "3. Custom permission test"
        echo "4. Exit"
        echo
        read -p "Enter your choice (1-4): " choice
        
        case $choice in
            1)
                read -p "Enter IAM username: " test_user
                if aws iam get-user --user-name "$test_user" &>/dev/null; then
                    user_arn="arn:aws:iam::$ACCOUNT_ID:user/$test_user"
                    
                    # Determine role based on group membership
                    groups=$(aws iam get-groups-for-user --user-name "$test_user" --query 'Groups[].GroupName' --output text)
                    
                    if echo "$groups" | grep -q "Developers"; then
                        test_developer_permissions "$user_arn"
                    elif echo "$groups" | grep -q "Operations"; then
                        test_operations_permissions "$user_arn"
                    elif echo "$groups" | grep -q "Finance"; then
                        test_finance_permissions "$user_arn"
                    elif echo "$groups" | grep -q "Analysts"; then
                        test_analyst_permissions "$user_arn"
                    else
                        print_warning "User $test_user is not in any recognized group"
                    fi
                else
                    print_error "User $test_user not found"
                fi
                ;;
            2)
                echo "Select role to test:"
                echo "1. Developer"
                echo "2. Operations"
                echo "3. Finance"
                echo "4. Analyst"
                read -p "Enter choice (1-4): " role_choice
                
                case $role_choice in
                    1) test_role="developer" ;;
                    2) test_role="operations" ;;
                    3) test_role="finance" ;;
                    4) test_role="analyst" ;;
                    *) print_error "Invalid choice"; continue ;;
                esac
                
                test_role_permissions "$test_role"
                ;;
            3)
                read -p "Enter IAM user ARN: " custom_arn
                read -p "Enter action to test: " custom_action
                read -p "Enter resource ARN: " custom_resource
                
                test_permission "$custom_arn" "$custom_action" "$custom_resource" "Custom permission test"
                ;;
            4)
                print_status "Exiting interactive mode"
                break
                ;;
            *)
                print_error "Invalid choice. Please enter 1-4."
                ;;
        esac
        
        echo
        read -p "Press Enter to continue..."
        echo
    done
}

# Function to test permissions for a specific role
test_role_permissions() {
    local role="$1"
    
    case $role in
        "developer")
            # Test with first developer user
            if aws iam get-user --user-name "dev1" &>/dev/null; then
                test_developer_permissions "arn:aws:iam::$ACCOUNT_ID:user/dev1"
            else
                print_error "Developer user dev1 not found"
            fi
            ;;
        "operations")
            # Test with first operations user
            if aws iam get-user --user-name "ops1" &>/dev/null; then
                test_operations_permissions "arn:aws:iam::$ACCOUNT_ID:user/ops1"
            else
                print_error "Operations user ops1 not found"
            fi
            ;;
        "finance")
            # Test with first finance user
            if aws iam get-user --user-name "finance1" &>/dev/null; then
                test_finance_permissions "arn:aws:iam::$ACCOUNT_ID:user/finance1"
            else
                print_error "Finance user finance1 not found"
            fi
            ;;
        "analyst")
            # Test with first analyst user
            if aws iam get-user --user-name "analyst1" &>/dev/null; then
                test_analyst_permissions "arn:aws:iam::$ACCOUNT_ID:user/analyst1"
            else
                print_error "Analyst user analyst1 not found"
            fi
            ;;
        "all")
            print_status "🎯 Testing All Role Permissions"
            test_role_permissions "developer"
            echo
            test_role_permissions "operations"
            echo
            test_role_permissions "finance"
            echo
            test_role_permissions "analyst"
            ;;
        *)
            print_error "Invalid role: $role"
            exit 1
            ;;
    esac
}

# Main execution logic
if [ "$INTERACTIVE" = true ]; then
    interactive_mode
elif [ -n "$USER" ]; then
    # Test specific user
    if aws iam get-user --user-name "$USER" &>/dev/null; then
        user_arn="arn:aws:iam::$ACCOUNT_ID:user/$USER"
        
        # Determine role based on group membership
        groups=$(aws iam get-groups-for-user --user-name "$USER" --query 'Groups[].GroupName' --output text)
        
        if echo "$groups" | grep -q "Developers"; then
            test_developer_permissions "$user_arn"
        elif echo "$groups" | grep -q "Operations"; then
            test_operations_permissions "$user_arn"
        elif echo "$groups" | grep -q "Finance"; then
            test_finance_permissions "$user_arn"
        elif echo "$groups" | grep -q "Analysts"; then
            test_analyst_permissions "$user_arn"
        else
            print_warning "User $USER is not in any recognized group"
        fi
    else
        print_error "User $USER not found"
        exit 1
    fi
elif [ -n "$ROLE" ]; then
    # Test specific role
    test_role_permissions "$ROLE"
else
    print_error "Please specify either --user, --role, or --interactive"
    show_usage
    exit 1
fi

print_status "🏁 Permission testing completed"