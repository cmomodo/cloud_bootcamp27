#!/bin/bash

# AWS Security Stack Validation Script
# This script validates the deployed IAM policies and permissions

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT="production"
VERBOSE=false
GENERATE_REPORT=true

# Counters for validation results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

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

# Function to run a validation test
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="$3"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    if [ "$VERBOSE" = true ]; then
        print_status "Running test: $test_name"
        print_status "Command: $test_command"
    fi
    
    # Execute the test command
    local result
    if result=$(eval "$test_command" 2>&1); then
        if [ "$expected_result" = "success" ]; then
            print_success "✅ $test_name"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            return 0
        else
            print_error "❌ $test_name (expected failure but got success)"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            return 1
        fi
    else
        if [ "$expected_result" = "failure" ]; then
            print_success "✅ $test_name (correctly failed as expected)"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            return 0
        else
            print_error "❌ $test_name"
            if [ "$VERBOSE" = true ]; then
                echo "Error output: $result"
            fi
            TESTS_FAILED=$((TESTS_FAILED + 1))
            return 1
        fi
    fi
}

# Function to show usage
show_usage() {
    cat << EOF
AWS Security Stack Validation Script

Usage: $0 [OPTIONS]

Options:
    -e, --environment ENV    Target environment (production, staging, development) [default: production]
    --verbose               Enable verbose output
    --no-report            Skip generating validation report
    -h, --help              Show this help message

Examples:
    $0                                    # Validate production environment
    $0 -e staging --verbose               # Validate staging with verbose output
    $0 --no-report                        # Validate without generating report

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --no-report)
            GENERATE_REPORT=false
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
    exit 1
fi

STACK_NAME="AwsSecurityStack-$ENVIRONMENT"
AWS_REGION=$(aws configure get region || echo "us-east-1")

print_status "Starting validation for $ENVIRONMENT environment"
print_status "Stack: $STACK_NAME"
print_status "Region: $AWS_REGION"

# Check if stack exists
print_status "Checking if stack exists..."
if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" &> /dev/null; then
    print_error "Stack $STACK_NAME not found in region $AWS_REGION"
    exit 1
fi

print_success "Stack found"

# Validation Tests

print_status "🔍 Running IAM Groups Validation..."

# Test 1: Check if all required IAM groups exist
run_test "Developer group exists" \
    "aws iam get-group --group-name Developers" \
    "success"

run_test "Operations group exists" \
    "aws iam get-group --group-name Operations" \
    "success"

run_test "Finance group exists" \
    "aws iam get-group --group-name Finance" \
    "success"

run_test "Analysts group exists" \
    "aws iam get-group --group-name Analysts" \
    "success"

print_status "🔍 Running IAM Users Validation..."

# Test 2: Check if users exist and are in correct groups
EXPECTED_USERS=("dev1" "dev2" "dev3" "ops1" "ops2" "finance1" "finance2" "analyst1" "analyst2" "analyst3")

for user in "${EXPECTED_USERS[@]}"; do
    run_test "User $user exists" \
        "aws iam get-user --user-name $user" \
        "success"
done

# Test 3: Check group memberships
run_test "dev1 is in Developers group" \
    "aws iam get-groups-for-user --user-name dev1 | grep -q 'Developers'" \
    "success"

run_test "ops1 is in Operations group" \
    "aws iam get-groups-for-user --user-name ops1 | grep -q 'Operations'" \
    "success"

run_test "finance1 is in Finance group" \
    "aws iam get-groups-for-user --user-name finance1 | grep -q 'Finance'" \
    "success"

run_test "analyst1 is in Analysts group" \
    "aws iam get-groups-for-user --user-name analyst1 | grep -q 'Analysts'" \
    "success"

print_status "🔍 Running IAM Policies Validation..."

# Test 4: Check if managed policies exist
EXPECTED_POLICIES=("DeveloperPermissions" "OperationsPermissions" "FinancePermissions" "AnalystPermissions" "RequireMFAForAllActions")

for policy in "${EXPECTED_POLICIES[@]}"; do
    run_test "Policy $policy exists" \
        "aws iam get-policy --policy-arn arn:aws:iam::\$(aws sts get-caller-identity --query Account --output text):policy/$policy" \
        "success"
done

# Test 5: Check policy attachments to groups
run_test "DeveloperPermissions attached to Developers group" \
    "aws iam list-attached-group-policies --group-name Developers | grep -q 'DeveloperPermissions'" \
    "success"

run_test "OperationsPermissions attached to Operations group" \
    "aws iam list-attached-group-policies --group-name Operations | grep -q 'OperationsPermissions'" \
    "success"

print_status "🔍 Running Permission Simulation Tests..."

# Test 6: Simulate permissions for different roles
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Developer permissions test
run_test "Developer can describe EC2 instances" \
    "aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::$ACCOUNT_ID:user/dev1 --action-names ec2:DescribeInstances --resource-arns '*' | grep -q 'allowed'" \
    "success"

run_test "Developer cannot create IAM users (should fail)" \
    "aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::$ACCOUNT_ID:user/dev1 --action-names iam:CreateUser --resource-arns '*' | grep -q 'implicitDeny'" \
    "success"

# Operations permissions test
run_test "Operations can manage EC2 instances" \
    "aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::$ACCOUNT_ID:user/ops1 --action-names ec2:RunInstances --resource-arns '*' | grep -q 'allowed'" \
    "success"

# Finance permissions test
run_test "Finance can access Cost Explorer" \
    "aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::$ACCOUNT_ID:user/finance1 --action-names ce:GetCostAndUsage --resource-arns '*' | grep -q 'allowed'" \
    "success"

# Analyst permissions test
run_test "Analyst can read S3 data buckets" \
    "aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::$ACCOUNT_ID:user/analyst1 --action-names s3:GetObject --resource-arns 'arn:aws:s3:::data-*/*' | grep -q 'allowed'" \
    "success"

run_test "Analyst cannot write to S3 data buckets (should fail)" \
    "aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::$ACCOUNT_ID:user/analyst1 --action-names s3:PutObject --resource-arns 'arn:aws:s3:::data-*/*' | grep -q 'implicitDeny'" \
    "success"

print_status "🔍 Running Security Policy Validation..."

# Test 7: Check password policy
run_test "Account password policy exists" \
    "aws iam get-account-password-policy" \
    "success"

# Test 8: Check MFA policy
run_test "MFA policy exists and is configured" \
    "aws iam get-policy --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/RequireMFAForAllActions" \
    "success"

print_status "🔍 Running CloudFormation Stack Validation..."

# Test 9: Check stack status
run_test "Stack is in CREATE_COMPLETE or UPDATE_COMPLETE status" \
    "aws cloudformation describe-stacks --stack-name $STACK_NAME --query 'Stacks[0].StackStatus' --output text | grep -E '(CREATE_COMPLETE|UPDATE_COMPLETE)'" \
    "success"

# Test 10: Check for stack drift
print_status "Checking for stack drift (this may take a moment)..."
DRIFT_DETECTION_ID=$(aws cloudformation detect-stack-drift --stack-name "$STACK_NAME" --query 'StackDriftDetectionId' --output text)
sleep 10  # Wait for drift detection to complete

run_test "Stack has no drift" \
    "aws cloudformation describe-stack-drift-detection-status --stack-drift-detection-id $DRIFT_DETECTION_ID --query 'StackDriftStatus' --output text | grep -q 'IN_SYNC'" \
    "success"

print_status "🔍 Running Resource Validation..."

# Test 11: Count resources
EXPECTED_RESOURCE_COUNTS=(
    "AWS::IAM::Group:4"
    "AWS::IAM::User:10"
    "AWS::IAM::ManagedPolicy:5"
)

for resource_count in "${EXPECTED_RESOURCE_COUNTS[@]}"; do
    resource_type=$(echo $resource_count | cut -d: -f1-3)
    expected_count=$(echo $resource_count | cut -d: -f4)
    
    run_test "$resource_type count is $expected_count" \
        "[ \$(aws cloudformation list-stack-resources --stack-name $STACK_NAME --query \"StackResourceSummaries[?ResourceType=='$resource_type'] | length(@)\") -eq $expected_count ]" \
        "success"
done

# Generate validation report
if [ "$GENERATE_REPORT" = true ]; then
    print_status "Generating validation report..."
    REPORT_FILE="validation-report-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > $REPORT_FILE << EOF
AWS Security Stack Validation Report
====================================

Validation Details:
- Environment: $ENVIRONMENT
- Stack Name: $STACK_NAME
- AWS Region: $AWS_REGION
- Validation Time: $(date)
- Validated By: $(aws sts get-caller-identity --query Arn --output text)

Test Results:
- Total Tests: $TESTS_TOTAL
- Passed: $TESTS_PASSED
- Failed: $TESTS_FAILED
- Success Rate: $(( TESTS_PASSED * 100 / TESTS_TOTAL ))%

Stack Information:
$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].{Status:StackStatus,Created:CreationTime,Updated:LastUpdatedTime}' --output table)

IAM Resources Summary:
Groups: $(aws iam list-groups --query 'Groups | length(@)')
Users: $(aws iam list-users --query 'Users | length(@)')
Policies: $(aws iam list-policies --scope Local --query 'Policies | length(@)')

Security Recommendations:
1. Ensure all users have MFA devices configured
2. Regularly review and rotate access keys
3. Monitor CloudTrail logs for suspicious activity
4. Conduct quarterly access reviews
5. Test emergency access procedures

EOF

    if [ $TESTS_FAILED -gt 0 ]; then
        echo "VALIDATION ISSUES DETECTED - REVIEW REQUIRED" >> $REPORT_FILE
    else
        echo "ALL VALIDATIONS PASSED - DEPLOYMENT VERIFIED" >> $REPORT_FILE
    fi

    print_success "Validation report saved to: $REPORT_FILE"
fi

# Final summary
echo
print_status "🏁 Validation Summary:"
echo "  📊 Total Tests: $TESTS_TOTAL"
echo "  ✅ Passed: $TESTS_PASSED"
echo "  ❌ Failed: $TESTS_FAILED"
echo "  📈 Success Rate: $(( TESTS_PASSED * 100 / TESTS_TOTAL ))%"

if [ $TESTS_FAILED -eq 0 ]; then
    print_success "🎉 All validations passed! Deployment is verified."
    exit 0
else
    print_error "⚠️  Some validations failed. Please review and fix issues."
    exit 1
fi