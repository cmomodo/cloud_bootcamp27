#!/bin/bash

# Permission Boundary Testing Script
# This script tests least privilege implementation and permission boundaries

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
TEST_USER=""
COMPREHENSIVE=false

# Test counters
BOUNDARY_TESTS_PASSED=0
BOUNDARY_TESTS_FAILED=0
BOUNDARY_TESTS_TOTAL=0

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

# Function to test permission boundary
test_permission_boundary() {
    local test_name="$1"
    local user_arn="$2"
    local action="$3"
    local resource="$4"
    local expected_result="$5"  # "allow" or "deny"
    local risk_level="$6"       # "HIGH", "MEDIUM", "LOW"
    
    BOUNDARY_TESTS_TOTAL=$((BOUNDARY_TESTS_TOTAL + 1))
    
    if [ "$VERBOSE" = true ]; then
        print_status "Testing: $test_name"
        print_status "User: $(basename $user_arn)"
        print_status "Action: $action"
        print_status "Resource: $resource"
        print_status "Expected: $expected_result"
        print_status "Risk Level: $risk_level"
    fi
    
    # Run policy simulation
    local result
    result=$(aws iam simulate-principal-policy \
        --policy-source-arn "$user_arn" \
        --action-names "$action" \
        --resource-arns "$resource" \
        --query 'EvaluationResults[0].EvalDecision' \
        --output text 2>/dev/null)
    
    # Check if result matches expectation
    if [ "$result" = "$expected_result" ]; then
        print_success "✅ $test_name"
        BOUNDARY_TESTS_PASSED=$((BOUNDARY_TESTS_PASSED + 1))
        return 0
    else
        if [ "$risk_level" = "HIGH" ]; then
            print_error "❌ $test_name (Expected: $expected_result, Got: $result) - HIGH RISK"
        else
            print_warning "⚠️  $test_name (Expected: $expected_result, Got: $result) - $risk_level RISK"
        fi
        BOUNDARY_TESTS_FAILED=$((BOUNDARY_TESTS_FAILED + 1))
        return 1
    fi
}

# Function to show usage
show_usage() {
    cat << EOF
Permission Boundary Testing Script

Usage: $0 [OPTIONS]

Options:
    -e, --environment ENV    Target environment (production, staging, development) [default: production]
    -u, --user USER         Test specific user only
    -c, --comprehensive     Run comprehensive boundary tests (slower)
    --verbose               Enable verbose output
    -h, --help              Show this help message

Examples:
    $0                                    # Test all users in production
    $0 -u dev1 --verbose                 # Test specific user with verbose output
    $0 -c -e staging                     # Comprehensive test on staging

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -u|--user)
            TEST_USER="$2"
            shift 2
            ;;
        -c|--comprehensive)
            COMPREHENSIVE=true
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
    exit 1
fi

STACK_NAME="AwsSecurityStack-$ENVIRONMENT"
AWS_REGION=$(aws configure get region || echo "us-east-1")
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

print_status "🔒 Starting Permission Boundary Testing"
print_status "Environment: $ENVIRONMENT"
print_status "Account: $ACCOUNT_ID"
print_status "Region: $AWS_REGION"

# Check if stack exists
if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" &> /dev/null; then
    print_error "Stack $STACK_NAME not found in region $AWS_REGION"
    exit 1
fi

# Get list of users to test
if [ -n "$TEST_USER" ]; then
    if aws iam get-user --user-name "$TEST_USER" &>/dev/null; then
        USERS_TO_TEST=("$TEST_USER")
    else
        print_error "User $TEST_USER not found"
        exit 1
    fi
else
    # Get all users from our stack
    USERS_TO_TEST=($(aws iam list-users --query 'Users[?starts_with(UserName, `dev`) || starts_with(UserName, `ops`) || starts_with(UserName, `finance`) || starts_with(UserName, `analyst`)].UserName' --output text))
fi

print_status "Testing ${#USERS_TO_TEST[@]} users: ${USERS_TO_TEST[*]}"

# Test each user's permission boundaries
for user in "${USERS_TO_TEST[@]}"; do
    user_arn="arn:aws:iam::$ACCOUNT_ID:user/$user"
    
    # Determine user role based on username
    if [[ $user == dev* ]]; then
        role="DEVELOPER"
    elif [[ $user == ops* ]]; then
        role="OPERATIONS"
    elif [[ $user == finance* ]]; then
        role="FINANCE"
    elif [[ $user == analyst* ]]; then
        role="ANALYST"
    else
        print_warning "Unknown role for user $user, skipping"
        continue
    fi
    
    print_status "🧪 Testing Permission Boundaries for $user ($role)"
    
    # Developer Permission Boundary Tests
    if [ "$role" = "DEVELOPER" ]; then
        
        print_status "🔧 Developer Permission Boundary Tests"
        
        # Should be allowed
        test_permission_boundary \
            "Developer can describe EC2 instances" \
            "$user_arn" \
            "ec2:DescribeInstances" \
            "*" \
            "allowed" \
            "MEDIUM"
        
        test_permission_boundary \
            "Developer can start EC2 instances" \
            "$user_arn" \
            "ec2:StartInstances" \
            "*" \
            "allowed" \
            "MEDIUM"
        
        test_permission_boundary \
            "Developer can access app S3 buckets" \
            "$user_arn" \
            "s3:GetObject" \
            "arn:aws:s3:::app-*/*" \
            "allowed" \
            "MEDIUM"
        
        test_permission_boundary \
            "Developer can read CloudWatch logs" \
            "$user_arn" \
            "logs:GetLogEvents" \
            "*" \
            "allowed" \
            "LOW"
        
        # Should be denied - High Risk if allowed
        test_permission_boundary \
            "Developer CANNOT create EC2 instances" \
            "$user_arn" \
            "ec2:RunInstances" \
            "*" \
            "implicitDeny" \
            "HIGH"
        
        test_permission_boundary \
            "Developer CANNOT terminate EC2 instances" \
            "$user_arn" \
            "ec2:TerminateInstances" \
            "*" \
            "implicitDeny" \
            "HIGH"
        
        test_permission_boundary \
            "Developer CANNOT access data S3 buckets" \
            "$user_arn" \
            "s3:GetObject" \
            "arn:aws:s3:::data-*/*" \
            "implicitDeny" \
            "HIGH"
        
        test_permission_boundary \
            "Developer CANNOT create IAM users" \
            "$user_arn" \
            "iam:CreateUser" \
            "*" \
            "implicitDeny" \
            "HIGH"
        
        test_permission_boundary \
            "Developer CANNOT access RDS" \
            "$user_arn" \
            "rds:CreateDBInstance" \
            "*" \
            "implicitDeny" \
            "HIGH"
        
        if [ "$COMPREHENSIVE" = true ]; then
            # Additional comprehensive tests for developers
            test_permission_boundary \
                "Developer CANNOT modify security groups" \
                "$user_arn" \
                "ec2:CreateSecurityGroup" \
                "*" \
                "implicitDeny" \
                "HIGH"
            
            test_permission_boundary \
                "Developer CANNOT access billing" \
                "$user_arn" \
                "ce:GetCostAndUsage" \
                "*" \
                "implicitDeny" \
                "MEDIUM"
        fi
    fi
    
    # Operations Permission Boundary Tests
    if [ "$role" = "OPERATIONS" ]; then
        
        print_status "⚙️ Operations Permission Boundary Tests"
        
        # Should be allowed
        test_permission_boundary \
            "Operations can manage EC2 instances" \
            "$user_arn" \
            "ec2:RunInstances" \
            "*" \
            "allowed" \
            "MEDIUM"
        
        test_permission_boundary \
            "Operations can manage RDS" \
            "$user_arn" \
            "rds:CreateDBInstance" \
            "*" \
            "allowed" \
            "MEDIUM"
        
        test_permission_boundary \
            "Operations can access CloudWatch" \
            "$user_arn" \
            "cloudwatch:PutMetricData" \
            "*" \
            "allowed" \
            "LOW"
        
        test_permission_boundary \
            "Operations can use Systems Manager" \
            "$user_arn" \
            "ssm:StartSession" \
            "*" \
            "allowed" \
            "MEDIUM"
        
        # Should be denied - High Risk if allowed
        test_permission_boundary \
            "Operations CANNOT create IAM users" \
            "$user_arn" \
            "iam:CreateUser" \
            "*" \
            "implicitDeny" \
            "HIGH"
        
        test_permission_boundary \
            "Operations CANNOT access billing" \
            "$user_arn" \
            "ce:GetCostAndUsage" \
            "*" \
            "implicitDeny" \
            "HIGH"
        
        if [ "$COMPREHENSIVE" = true ]; then
            # Additional comprehensive tests for operations
            test_permission_boundary \
                "Operations CANNOT modify IAM policies" \
                "$user_arn" \
                "iam:CreatePolicy" \
                "*" \
                "implicitDeny" \
                "HIGH"
        fi
    fi
    
    # Finance Permission Boundary Tests
    if [ "$role" = "FINANCE" ]; then
        
        print_status "💰 Finance Permission Boundary Tests"
        
        # Should be allowed
        test_permission_boundary \
            "Finance can access Cost Explorer" \
            "$user_arn" \
            "ce:GetCostAndUsage" \
            "*" \
            "allowed" \
            "LOW"
        
        test_permission_boundary \
            "Finance can manage budgets" \
            "$user_arn" \
            "budgets:CreateBudget" \
            "*" \
            "allowed" \
            "LOW"
        
        test_permission_boundary \
            "Finance can describe EC2 for cost allocation" \
            "$user_arn" \
            "ec2:DescribeInstances" \
            "*" \
            "allowed" \
            "LOW"
        
        # Should be denied - High Risk if allowed
        test_permission_boundary \
            "Finance CANNOT run EC2 instances" \
            "$user_arn" \
            "ec2:RunInstances" \
            "*" \
            "implicitDeny" \
            "HIGH"
        
        test_permission_boundary \
            "Finance CANNOT access S3 data" \
            "$user_arn" \
            "s3:GetObject" \
            "arn:aws:s3:::app-*/*" \
            "implicitDeny" \
            "HIGH"
        
        test_permission_boundary \
            "Finance CANNOT create IAM users" \
            "$user_arn" \
            "iam:CreateUser" \
            "*" \
            "implicitDeny" \
            "HIGH"
        
        if [ "$COMPREHENSIVE" = true ]; then
            # Additional comprehensive tests for finance
            test_permission_boundary \
                "Finance CANNOT modify RDS" \
                "$user_arn" \
                "rds:CreateDBInstance" \
                "*" \
                "implicitDeny" \
                "HIGH"
        fi
    fi
    
    # Analyst Permission Boundary Tests
    if [ "$role" = "ANALYST" ]; then
        
        print_status "📊 Analyst Permission Boundary Tests"
        
        # Should be allowed
        test_permission_boundary \
            "Analyst can read data S3 buckets" \
            "$user_arn" \
            "s3:GetObject" \
            "arn:aws:s3:::data-*/*" \
            "allowed" \
            "LOW"
        
        test_permission_boundary \
            "Analyst can get CloudWatch metrics" \
            "$user_arn" \
            "cloudwatch:GetMetricStatistics" \
            "*" \
            "allowed" \
            "LOW"
        
        test_permission_boundary \
            "Analyst can describe RDS instances" \
            "$user_arn" \
            "rds:DescribeDBInstances" \
            "*" \
            "allowed" \
            "LOW"
        
        # Should be denied - High Risk if allowed
        test_permission_boundary \
            "Analyst CANNOT write to data S3 buckets" \
            "$user_arn" \
            "s3:PutObject" \
            "arn:aws:s3:::data-*/*" \
            "implicitDeny" \
            "HIGH"
        
        test_permission_boundary \
            "Analyst CANNOT access app S3 buckets" \
            "$user_arn" \
            "s3:GetObject" \
            "arn:aws:s3:::app-*/*" \
            "implicitDeny" \
            "HIGH"
        
        test_permission_boundary \
            "Analyst CANNOT run EC2 instances" \
            "$user_arn" \
            "ec2:RunInstances" \
            "*" \
            "implicitDeny" \
            "HIGH"
        
        test_permission_boundary \
            "Analyst CANNOT create IAM users" \
            "$user_arn" \
            "iam:CreateUser" \
            "*" \
            "implicitDeny" \
            "HIGH"
        
        if [ "$COMPREHENSIVE" = true ]; then
            # Additional comprehensive tests for analysts
            test_permission_boundary \
                "Analyst CANNOT delete S3 objects" \
                "$user_arn" \
                "s3:DeleteObject" \
                "arn:aws:s3:::data-*/*" \
                "implicitDeny" \
                "HIGH"
        fi
    fi
    
    # Universal tests for all roles
    print_status "🔒 Universal Security Boundary Tests"
    
    # Critical security boundaries that should apply to ALL roles
    test_permission_boundary \
        "$role CANNOT assume admin role" \
        "$user_arn" \
        "sts:AssumeRole" \
        "arn:aws:iam::$ACCOUNT_ID:role/AdminRole" \
        "implicitDeny" \
        "HIGH"
    
    test_permission_boundary \
        "$role CANNOT modify account settings" \
        "$user_arn" \
        "account:PutAccountAttributes" \
        "*" \
        "implicitDeny" \
        "HIGH"
    
    test_permission_boundary \
        "$role CANNOT access other users' resources" \
        "$user_arn" \
        "iam:GetUser" \
        "arn:aws:iam::$ACCOUNT_ID:user/root" \
        "implicitDeny" \
        "HIGH"
    
    if [ "$COMPREHENSIVE" = true ]; then
        # Additional universal tests
        test_permission_boundary \
            "$role CANNOT modify CloudTrail" \
            "$user_arn" \
            "cloudtrail:StopLogging" \
            "*" \
            "implicitDeny" \
            "HIGH"
        
        test_permission_boundary \
            "$role CANNOT access AWS Config" \
            "$user_arn" \
            "config:DeleteConfigRule" \
            "*" \
            "implicitDeny" \
            "HIGH"
    fi
    
    echo
done

# Generate permission boundary test report
print_status "📊 Generating permission boundary test report..."
REPORT_FILE="permission-boundary-test-$(date +%Y%m%d-%H%M%S).txt"

cat > $REPORT_FILE << EOF
Permission Boundary Test Report
===============================

Test Details:
- Environment: $ENVIRONMENT
- Stack Name: $STACK_NAME
- AWS Account: $ACCOUNT_ID
- AWS Region: $AWS_REGION
- Test Time: $(date)
- Tested By: $(aws sts get-caller-identity --query Arn --output text)
- Users Tested: ${USERS_TO_TEST[*]}
- Comprehensive Mode: $COMPREHENSIVE

Test Results Summary:
- Total Boundary Tests: $BOUNDARY_TESTS_TOTAL
- Passed: $BOUNDARY_TESTS_PASSED
- Failed: $BOUNDARY_TESTS_FAILED
- Success Rate: $(( BOUNDARY_TESTS_PASSED * 100 / BOUNDARY_TESTS_TOTAL ))%

Security Assessment:
EOF

if [ $BOUNDARY_TESTS_FAILED -eq 0 ]; then
    echo "✅ SECURE - All permission boundaries properly enforced" >> $REPORT_FILE
else
    echo "❌ SECURITY RISK - $BOUNDARY_TESTS_FAILED boundary violations detected" >> $REPORT_FILE
fi

cat >> $REPORT_FILE << EOF

Least Privilege Validation:
- Developer role: Limited to necessary EC2 and app resources
- Operations role: Full infrastructure access, no IAM/billing
- Finance role: Cost management only, no infrastructure access
- Analyst role: Read-only data access, no modification rights

Risk Assessment:
- HIGH RISK failures require immediate remediation
- MEDIUM RISK failures should be addressed within 7 days
- LOW RISK failures should be reviewed and documented

Recommendations:
1. Address all HIGH RISK boundary violations immediately
2. Review and tighten policies for failed tests
3. Implement additional permission boundaries if needed
4. Schedule regular boundary testing (weekly)
5. Monitor for privilege escalation attempts

Next Steps:
1. Remediate failed boundary tests
2. Update IAM policies as needed
3. Re-run tests to verify fixes
4. Document any accepted risks
5. Schedule follow-up testing

EOF

if [ $BOUNDARY_TESTS_FAILED -gt 0 ]; then
    echo "⚠️  IMMEDIATE ACTION REQUIRED - SECURITY BOUNDARIES COMPROMISED" >> $REPORT_FILE
else
    echo "✅ BOUNDARIES VERIFIED - LEAST PRIVILEGE ENFORCED" >> $REPORT_FILE
fi

print_success "Permission boundary test report saved to: $REPORT_FILE"

# Final summary
echo
print_status "🏁 Permission Boundary Testing Summary:"
echo "  👥 Users Tested: ${#USERS_TO_TEST[@]}"
echo "  📋 Total Tests: $BOUNDARY_TESTS_TOTAL"
echo "  ✅ Passed: $BOUNDARY_TESTS_PASSED"
echo "  ❌ Failed: $BOUNDARY_TESTS_FAILED"
echo "  📈 Success Rate: $(( BOUNDARY_TESTS_PASSED * 100 / BOUNDARY_TESTS_TOTAL ))%"

if [ $BOUNDARY_TESTS_FAILED -eq 0 ]; then
    print_success "🎉 All permission boundaries properly enforced! Least privilege verified."
    exit 0
else
    print_error "⚠️  Permission boundary violations detected. $BOUNDARY_TESTS_FAILED tests failed."
    exit 1
fi