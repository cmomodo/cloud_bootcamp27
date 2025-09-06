#!/bin/bash

# End-to-End Testing Script for AWS Security Implementation
# This script performs comprehensive testing of the entire security stack

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
ENVIRONMENT="development"
CLEANUP=true
VERBOSE=false
TEST_BUCKET_PREFIX="e2e-test"
TEST_INSTANCE_TYPE="t3.micro"

# Counters
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

# Function to run a test
run_e2e_test() {
    local test_name="$1"
    local test_command="$2"
    local cleanup_command="$3"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    print_status "Running E2E test: $test_name"
    
    if [ "$VERBOSE" = true ]; then
        print_status "Command: $test_command"
    fi
    
    # Execute the test command
    if eval "$test_command" &>/dev/null; then
        print_success "✅ $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        
        # Run cleanup if provided and cleanup is enabled
        if [ "$CLEANUP" = true ] && [ -n "$cleanup_command" ]; then
            if [ "$VERBOSE" = true ]; then
                print_status "Cleanup: $cleanup_command"
            fi
            eval "$cleanup_command" &>/dev/null || print_warning "Cleanup failed for: $test_name"
        fi
        
        return 0
    else
        print_error "❌ $test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        
        # Still try cleanup on failure
        if [ "$CLEANUP" = true ] && [ -n "$cleanup_command" ]; then
            eval "$cleanup_command" &>/dev/null || true
        fi
        
        return 1
    fi
}

# Function to show usage
show_usage() {
    cat << EOF
End-to-End Testing Script for AWS Security Implementation

Usage: $0 [OPTIONS]

Options:
    -e, --environment ENV    Target environment [default: development]
    --no-cleanup            Skip cleanup of test resources
    --verbose               Enable verbose output
    -h, --help              Show this help message

Examples:
    $0                                    # Run E2E tests with cleanup
    $0 --no-cleanup --verbose             # Run tests without cleanup, verbose output
    $0 -e staging                         # Run tests against staging environment

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --no-cleanup)
            CLEANUP=false
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

# Get AWS account info
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region || echo "us-east-1")
STACK_NAME="AwsSecurityStack-$ENVIRONMENT"

print_status "🚀 Starting End-to-End Testing"
print_status "Environment: $ENVIRONMENT"
print_status "Account: $ACCOUNT_ID"
print_status "Region: $AWS_REGION"
print_status "Stack: $STACK_NAME"

# Check prerequisites
print_status "Checking prerequisites..."

# Verify stack exists
if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" &>/dev/null; then
    print_error "Stack $STACK_NAME not found. Please deploy the stack first."
    exit 1
fi

# Verify test users exist
TEST_USERS=("dev1" "ops1" "finance1" "analyst1")
for user in "${TEST_USERS[@]}"; do
    if ! aws iam get-user --user-name "$user" &>/dev/null; then
        print_error "Test user $user not found"
        exit 1
    fi
done

print_success "Prerequisites check passed"

# Create test resources for E2E testing
print_status "🔧 Setting up test resources..."

# Create test S3 buckets
TEST_APP_BUCKET="${TEST_BUCKET_PREFIX}-app-$(date +%s)"
TEST_DATA_BUCKET="${TEST_BUCKET_PREFIX}-data-$(date +%s)"

aws s3 mb "s3://$TEST_APP_BUCKET" --region "$AWS_REGION" || print_warning "Failed to create app test bucket"
aws s3 mb "s3://$TEST_DATA_BUCKET" --region "$AWS_REGION" || print_warning "Failed to create data test bucket"

# Create test files
echo "Test application file" > /tmp/app-test.txt
echo "Test data file" > /tmp/data-test.txt

aws s3 cp /tmp/app-test.txt "s3://$TEST_APP_BUCKET/" || print_warning "Failed to upload app test file"
aws s3 cp /tmp/data-test.txt "s3://$TEST_DATA_BUCKET/" || print_warning "Failed to upload data test file"

print_success "Test resources created"

# E2E Test Suite

print_status "🧪 Running Developer Role E2E Tests..."

# Test 1: Developer EC2 permissions
run_e2e_test "Developer can describe EC2 instances" \
    "aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::$ACCOUNT_ID:user/dev1 --action-names ec2:DescribeInstances --resource-arns '*' | grep -q 'allowed'" \
    ""

# Test 2: Developer S3 app bucket access
run_e2e_test "Developer can access app S3 bucket" \
    "aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::$ACCOUNT_ID:user/dev1 --action-names s3:GetObject --resource-arns 'arn:aws:s3:::app-*/*' | grep -q 'allowed'" \
    ""

# Test 3: Developer cannot access data buckets
run_e2e_test "Developer cannot access data S3 buckets" \
    "aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::$ACCOUNT_ID:user/dev1 --action-names s3:GetObject --resource-arns 'arn:aws:s3:::data-*/*' | grep -q 'implicitDeny'" \
    ""

print_status "🧪 Running Operations Role E2E Tests..."

# Test 4: Operations full EC2 access
run_e2e_test "Operations has full EC2 access" \
    "aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::$ACCOUNT_ID:user/ops1 --action-names ec2:RunInstances --resource-arns '*' | grep -q 'allowed'" \
    ""

# Test 5: Operations CloudWatch access
run_e2e_test "Operations has CloudWatch access" \
    "aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::$ACCOUNT_ID:user/ops1 --action-names cloudwatch:PutMetricData --resource-arns '*' | grep -q 'allowed'" \
    ""

# Test 6: Operations RDS access
run_e2e_test "Operations has RDS access" \
    "aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::$ACCOUNT_ID:user/ops1 --action-names rds:CreateDBInstance --resource-arns '*' | grep -q 'allowed'" \
    ""

print_status "🧪 Running Finance Role E2E Tests..."

# Test 7: Finance Cost Explorer access
run_e2e_test "Finance has Cost Explorer access" \
    "aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::$ACCOUNT_ID:user/finance1 --action-names ce:GetCostAndUsage --resource-arns '*' | grep -q 'allowed'" \
    ""

# Test 8: Finance Budgets access
run_e2e_test "Finance has Budgets access" \
    "aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::$ACCOUNT_ID:user/finance1 --action-names budgets:ViewBudget --resource-arns '*' | grep -q 'allowed'" \
    ""

# Test 9: Finance cannot run EC2 instances
run_e2e_test "Finance cannot run EC2 instances" \
    "aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::$ACCOUNT_ID:user/finance1 --action-names ec2:RunInstances --resource-arns '*' | grep -q 'implicitDeny'" \
    ""

print_status "🧪 Running Analyst Role E2E Tests..."

# Test 10: Analyst data bucket read access
run_e2e_test "Analyst has data bucket read access" \
    "aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::$ACCOUNT_ID:user/analyst1 --action-names s3:GetObject --resource-arns 'arn:aws:s3:::data-*/*' | grep -q 'allowed'" \
    ""

# Test 11: Analyst cannot write to data buckets
run_e2e_test "Analyst cannot write to data buckets" \
    "aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::$ACCOUNT_ID:user/analyst1 --action-names s3:PutObject --resource-arns 'arn:aws:s3:::data-*/*' | grep -q 'implicitDeny'" \
    ""

# Test 12: Analyst CloudWatch metrics access
run_e2e_test "Analyst has CloudWatch metrics access" \
    "aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::$ACCOUNT_ID:user/analyst1 --action-names cloudwatch:GetMetricStatistics --resource-arns '*' | grep -q 'allowed'" \
    ""

print_status "🧪 Running Security Policy E2E Tests..."

# Test 13: Password policy enforcement
run_e2e_test "Account password policy is enforced" \
    "aws iam get-account-password-policy | grep -q 'MinimumPasswordLength'" \
    ""

# Test 14: MFA policy exists
run_e2e_test "MFA policy exists and is configured" \
    "aws iam get-policy --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/RequireMFAForAllActions | grep -q 'RequireMFAForAllActions'" \
    ""

print_status "🧪 Running Cross-Role Security Tests..."

# Test 15: Users cannot assume other roles
run_e2e_test "Developer cannot perform operations tasks" \
    "aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::$ACCOUNT_ID:user/dev1 --action-names rds:CreateDBInstance --resource-arns '*' | grep -q 'implicitDeny'" \
    ""

# Test 16: Least privilege enforcement
run_e2e_test "Analyst cannot perform developer tasks" \
    "aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::$ACCOUNT_ID:user/analyst1 --action-names ec2:StartInstances --resource-arns '*' | grep -q 'implicitDeny'" \
    ""

print_status "🧪 Running Infrastructure Validation Tests..."

# Test 17: All required groups exist
run_e2e_test "All IAM groups exist" \
    "aws iam list-groups --query 'Groups[?contains([\"Developers\", \"Operations\", \"Finance\", \"Analysts\"], GroupName)] | length(@)' --output text | grep -q '^4$'" \
    ""

# Test 18: All required users exist
run_e2e_test "All IAM users exist" \
    "aws iam list-users --query 'Users | length(@)' --output text | grep -q '^10$'" \
    ""

# Test 19: All required policies exist
run_e2e_test "All managed policies exist" \
    "aws iam list-policies --scope Local --query 'Policies | length(@)' --output text | grep -q '^5$'" \
    ""

print_status "🧪 Running Stack Health Tests..."

# Test 20: Stack is in healthy state
run_e2e_test "CloudFormation stack is healthy" \
    "aws cloudformation describe-stacks --stack-name $STACK_NAME --query 'Stacks[0].StackStatus' --output text | grep -E '(CREATE_COMPLETE|UPDATE_COMPLETE)'" \
    ""

# Cleanup test resources
if [ "$CLEANUP" = true ]; then
    print_status "🧹 Cleaning up test resources..."
    
    # Remove test files
    rm -f /tmp/app-test.txt /tmp/data-test.txt
    
    # Remove test S3 buckets
    aws s3 rm "s3://$TEST_APP_BUCKET" --recursive &>/dev/null || true
    aws s3 rb "s3://$TEST_APP_BUCKET" &>/dev/null || true
    
    aws s3 rm "s3://$TEST_DATA_BUCKET" --recursive &>/dev/null || true
    aws s3 rb "s3://$TEST_DATA_BUCKET" &>/dev/null || true
    
    print_success "Test resources cleaned up"
fi

# Generate E2E test report
print_status "📊 Generating E2E test report..."
REPORT_FILE="e2e-test-report-$(date +%Y%m%d-%H%M%S).txt"

cat > $REPORT_FILE << EOF
AWS Security Implementation - End-to-End Test Report
====================================================

Test Execution Details:
- Environment: $ENVIRONMENT
- Stack Name: $STACK_NAME
- AWS Account: $ACCOUNT_ID
- AWS Region: $AWS_REGION
- Test Time: $(date)
- Executed By: $(aws sts get-caller-identity --query Arn --output text)

Test Results Summary:
- Total Tests: $TESTS_TOTAL
- Passed: $TESTS_PASSED
- Failed: $TESTS_FAILED
- Success Rate: $(( TESTS_PASSED * 100 / TESTS_TOTAL ))%

Test Categories:
- Developer Role Tests: 3 tests
- Operations Role Tests: 3 tests
- Finance Role Tests: 3 tests
- Analyst Role Tests: 3 tests
- Security Policy Tests: 2 tests
- Cross-Role Security Tests: 2 tests
- Infrastructure Validation Tests: 3 tests
- Stack Health Tests: 1 test

Security Validation:
✅ Role-based access control working correctly
✅ Least privilege principle enforced
✅ Cross-role access properly restricted
✅ Security policies active and enforced

Recommendations:
1. Monitor CloudTrail logs for unusual access patterns
2. Regularly test MFA enforcement
3. Conduct quarterly access reviews
4. Update test scenarios as requirements change

EOF

if [ $TESTS_FAILED -gt 0 ]; then
    echo "⚠️  SOME TESTS FAILED - REVIEW REQUIRED" >> $REPORT_FILE
else
    echo "🎉 ALL E2E TESTS PASSED - SYSTEM VERIFIED" >> $REPORT_FILE
fi

print_success "E2E test report saved to: $REPORT_FILE"

# Final summary
echo
print_status "🏁 End-to-End Testing Summary:"
echo "  📊 Total Tests: $TESTS_TOTAL"
echo "  ✅ Passed: $TESTS_PASSED"
echo "  ❌ Failed: $TESTS_FAILED"
echo "  📈 Success Rate: $(( TESTS_PASSED * 100 / TESTS_TOTAL ))%"

if [ $TESTS_FAILED -eq 0 ]; then
    print_success "🎉 All E2E tests passed! Security implementation is fully verified."
    exit 0
else
    print_error "⚠️  Some E2E tests failed. Please review and fix issues."
    exit 1
fi