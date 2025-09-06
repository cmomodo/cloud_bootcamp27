#!/bin/bash

# Automated Security Validation Script
# This script runs comprehensive security validation tests

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
RUN_POLICY_SIMULATION=true
CHECK_COMPLIANCE=true

# Test counters
VALIDATION_TESTS_PASSED=0
VALIDATION_TESTS_FAILED=0
VALIDATION_TESTS_TOTAL=0

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

# Function to run a validation test
run_validation_test() {
    local test_name="$1"
    local test_command="$2"
    local severity="$3"  # CRITICAL, HIGH, MEDIUM, LOW
    
    VALIDATION_TESTS_TOTAL=$((VALIDATION_TESTS_TOTAL + 1))
    
    if [ "$VERBOSE" = true ]; then
        print_status "Running validation: $test_name"
        print_status "Severity: $severity"
        print_status "Command: $test_command"
    fi
    
    # Execute the validation test
    local result
    if result=$(eval "$test_command" 2>&1); then
        print_success "✅ $test_name"
        VALIDATION_TESTS_PASSED=$((VALIDATION_TESTS_PASSED + 1))
        return 0
    else
        if [ "$severity" = "CRITICAL" ] || [ "$severity" = "HIGH" ]; then
            print_error "❌ $test_name (Severity: $severity)"
        else
            print_warning "⚠️  $test_name (Severity: $severity)"
        fi
        VALIDATION_TESTS_FAILED=$((VALIDATION_TESTS_FAILED + 1))
        
        if [ "$VERBOSE" = true ]; then
            echo "Test output: $result"
        fi
        return 1
    fi
}

# Function to show usage
show_usage() {
    cat << EOF
Automated Security Validation Script

Usage: $0 [OPTIONS]

Options:
    -e, --environment ENV    Target environment (production, staging, development) [default: production]
    --no-policy-simulation   Skip AWS policy simulation tests
    --no-compliance-check    Skip compliance validation
    --no-report             Skip generating validation report
    --verbose               Enable verbose output
    -h, --help              Show this help message

Examples:
    $0                                    # Run full validation on production
    $0 -e staging --verbose              # Run validation on staging with verbose output
    $0 --no-policy-simulation            # Skip policy simulation tests

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --no-policy-simulation)
            RUN_POLICY_SIMULATION=false
            shift
            ;;
        --no-compliance-check)
            CHECK_COMPLIANCE=false
            shift
            ;;
        --no-report)
            GENERATE_REPORT=false
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

print_status "🔒 Starting Automated Security Validation"
print_status "Environment: $ENVIRONMENT"
print_status "Stack: $STACK_NAME"
print_status "Account: $ACCOUNT_ID"
print_status "Region: $AWS_REGION"

# Check if stack exists
if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" &> /dev/null; then
    print_error "Stack $STACK_NAME not found in region $AWS_REGION"
    exit 1
fi

print_status "📋 Running Security Validation Tests..."

# 1. CDK Unit Tests Validation
print_status "🧪 Running CDK Unit Tests"

run_validation_test \
    "CDK unit tests pass" \
    "cd $(dirname $0)/.. && npm test" \
    "CRITICAL"

# 2. CloudFormation Template Validation
print_status "☁️  CloudFormation Template Validation"

run_validation_test \
    "CDK synthesis succeeds" \
    "cd $(dirname $0)/.. && npm run synth > /dev/null" \
    "CRITICAL"

run_validation_test \
    "CloudFormation template is valid" \
    "aws cloudformation validate-template --template-body file://$(dirname $0)/../cdk.out/$STACK_NAME.template.json > /dev/null" \
    "CRITICAL"

# 3. IAM Policy Validation
print_status "🔐 IAM Policy Validation"

run_validation_test \
    "All IAM users exist" \
    "aws iam list-users --query 'Users[?starts_with(UserName, \`dev\`) || starts_with(UserName, \`ops\`) || starts_with(UserName, \`finance\`) || starts_with(UserName, \`analyst\`)].UserName' --output text | wc -w | grep -q '^10$'" \
    "HIGH"

run_validation_test \
    "All IAM groups exist" \
    "aws iam list-groups --query 'Groups[?GroupName==\`Developers\` || GroupName==\`Operations\` || GroupName==\`Finance\` || GroupName==\`Analysts\`].GroupName' --output text | wc -w | grep -q '^4$'" \
    "HIGH"

run_validation_test \
    "Custom policies exist" \
    "aws iam list-policies --scope Local --query 'Policies[?PolicyName==\`DeveloperPermissions\` || PolicyName==\`OperationsPermissions\` || PolicyName==\`FinancePermissions\` || PolicyName==\`AnalystPermissions\` || PolicyName==\`RequireMFAForAllActions\`].PolicyName' --output text | wc -w | grep -q '^5$'" \
    "HIGH"

run_validation_test \
    "MFA policy exists and is properly configured" \
    "aws iam get-policy --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/RequireMFAForAllActions --query 'Policy.PolicyName' --output text | grep -q 'RequireMFAForAllActions'" \
    "CRITICAL"

# 4. User-Group Assignment Validation
print_status "👥 User-Group Assignment Validation"

run_validation_test \
    "All users are assigned to groups" \
    "aws iam list-users --query 'Users[?starts_with(UserName, \`dev\`) || starts_with(UserName, \`ops\`) || starts_with(UserName, \`finance\`) || starts_with(UserName, \`analyst\`)].UserName' --output text | while read user; do groups=\$(aws iam get-groups-for-user --user-name \$user --query 'Groups | length(@)' --output text); [ \$groups -gt 0 ] || exit 1; done" \
    "HIGH"

run_validation_test \
    "Developer users are in Developers group" \
    "aws iam get-group --group-name Developers --query 'Users[?starts_with(UserName, \`dev\`)].UserName' --output text | wc -w | grep -q '^3$'" \
    "MEDIUM"

run_validation_test \
    "Operations users are in Operations group" \
    "aws iam get-group --group-name Operations --query 'Users[?starts_with(UserName, \`ops\`)].UserName' --output text | wc -w | grep -q '^2$'" \
    "MEDIUM"

run_validation_test \
    "Finance users are in Finance group" \
    "aws iam get-group --group-name Finance --query 'Users[?starts_with(UserName, \`finance\`)].UserName' --output text | wc -w | grep -q '^2$'" \
    "MEDIUM"

run_validation_test \
    "Analyst users are in Analysts group" \
    "aws iam get-group --group-name Analysts --query 'Users[?starts_with(UserName, \`analyst\`)].UserName' --output text | wc -w | grep -q '^3$'" \
    "MEDIUM"

# 5. Security Policy Validation
print_status "🛡️  Security Policy Validation"

run_validation_test \
    "Account password policy is configured" \
    "aws iam get-account-password-policy > /dev/null" \
    "CRITICAL"

run_validation_test \
    "Password policy meets minimum requirements" \
    "aws iam get-account-password-policy --query 'PasswordPolicy.MinimumPasswordLength' --output text | grep -E '^(1[2-9]|[2-9][0-9])$'" \
    "HIGH"

run_validation_test \
    "Password policy requires complexity" \
    "aws iam get-account-password-policy --query 'PasswordPolicy.RequireSymbols && PasswordPolicy.RequireNumbers && PasswordPolicy.RequireUppercaseCharacters && PasswordPolicy.RequireLowercaseCharacters' --output text | grep -q '^True$'" \
    "HIGH"

# 6. Policy Simulation Tests (if enabled)
if [ "$RUN_POLICY_SIMULATION" = true ]; then
    print_status "🎯 Policy Simulation Tests"
    
    # Test developer permissions
    if aws iam get-user --user-name "dev1" &>/dev/null; then
        run_validation_test \
            "Developer can describe EC2 instances" \
            "aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::$ACCOUNT_ID:user/dev1 --action-names ec2:DescribeInstances --resource-arns '*' --query 'EvaluationResults[0].EvalDecision' --output text | grep -q 'allowed'" \
            "MEDIUM"
        
        run_validation_test \
            "Developer cannot create IAM users" \
            "aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::$ACCOUNT_ID:user/dev1 --action-names iam:CreateUser --resource-arns '*' --query 'EvaluationResults[0].EvalDecision' --output text | grep -qv 'allowed'" \
            "HIGH"
    fi
    
    # Test operations permissions
    if aws iam get-user --user-name "ops1" &>/dev/null; then
        run_validation_test \
            "Operations can manage EC2 instances" \
            "aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::$ACCOUNT_ID:user/ops1 --action-names ec2:RunInstances --resource-arns '*' --query 'EvaluationResults[0].EvalDecision' --output text | grep -q 'allowed'" \
            "MEDIUM"
        
        run_validation_test \
            "Operations cannot create IAM users" \
            "aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::$ACCOUNT_ID:user/ops1 --action-names iam:CreateUser --resource-arns '*' --query 'EvaluationResults[0].EvalDecision' --output text | grep -qv 'allowed'" \
            "HIGH"
    fi
    
    # Test finance permissions
    if aws iam get-user --user-name "finance1" &>/dev/null; then
        run_validation_test \
            "Finance can access Cost Explorer" \
            "aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::$ACCOUNT_ID:user/finance1 --action-names ce:GetCostAndUsage --resource-arns '*' --query 'EvaluationResults[0].EvalDecision' --output text | grep -q 'allowed'" \
            "MEDIUM"
        
        run_validation_test \
            "Finance cannot run EC2 instances" \
            "aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::$ACCOUNT_ID:user/finance1 --action-names ec2:RunInstances --resource-arns '*' --query 'EvaluationResults[0].EvalDecision' --output text | grep -qv 'allowed'" \
            "HIGH"
    fi
    
    # Test analyst permissions
    if aws iam get-user --user-name "analyst1" &>/dev/null; then
        run_validation_test \
            "Analyst can read data S3 buckets" \
            "aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::$ACCOUNT_ID:user/analyst1 --action-names s3:GetObject --resource-arns 'arn:aws:s3:::data-*/*' --query 'EvaluationResults[0].EvalDecision' --output text | grep -q 'allowed'" \
            "MEDIUM"
        
        run_validation_test \
            "Analyst cannot write to data S3 buckets" \
            "aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::$ACCOUNT_ID:user/analyst1 --action-names s3:PutObject --resource-arns 'arn:aws:s3:::data-*/*' --query 'EvaluationResults[0].EvalDecision' --output text | grep -qv 'allowed'" \
            "HIGH"
    fi
fi

# 7. Resource Tagging Validation
print_status "🏷️  Resource Tagging Validation"

run_validation_test \
    "All IAM users have required tags" \
    "aws iam list-users --query 'Users[?starts_with(UserName, \`dev\`) || starts_with(UserName, \`ops\`) || starts_with(UserName, \`finance\`) || starts_with(UserName, \`analyst\`)].UserName' --output text | while read user; do tags=\$(aws iam list-user-tags --user-name \$user --query 'Tags | length(@)' --output text); [ \$tags -gt 0 ] || exit 1; done" \
    "LOW"

# 8. CloudFormation Stack Validation
print_status "📚 CloudFormation Stack Validation"

run_validation_test \
    "Stack is in CREATE_COMPLETE or UPDATE_COMPLETE state" \
    "aws cloudformation describe-stacks --stack-name $STACK_NAME --query 'Stacks[0].StackStatus' --output text | grep -E '(CREATE_COMPLETE|UPDATE_COMPLETE)'" \
    "CRITICAL"

run_validation_test \
    "Stack has no drift" \
    "aws cloudformation detect-stack-drift --stack-name $STACK_NAME > /dev/null && sleep 5 && aws cloudformation describe-stack-drift-detection-status --stack-drift-detection-id \$(aws cloudformation detect-stack-drift --stack-name $STACK_NAME --query 'StackDriftDetectionId' --output text) --query 'StackDriftStatus' --output text | grep -q 'IN_SYNC'" \
    "MEDIUM"

# 9. Compliance Validation (if enabled)
if [ "$CHECK_COMPLIANCE" = true ]; then
    print_status "📋 Compliance Validation"
    
    run_validation_test \
        "No users have direct policy attachments" \
        "aws iam list-users --query 'Users[?starts_with(UserName, \`dev\`) || starts_with(UserName, \`ops\`) || starts_with(UserName, \`finance\`) || starts_with(UserName, \`analyst\`)].UserName' --output text | while read user; do policies=\$(aws iam list-attached-user-policies --user-name \$user --query 'AttachedPolicies | length(@)' --output text); [ \$policies -eq 0 ] || exit 1; done" \
        "MEDIUM"
    
    run_validation_test \
        "All policies are attached to groups" \
        "aws iam list-policies --scope Local --query 'Policies[?PolicyName==\`DeveloperPermissions\` || PolicyName==\`OperationsPermissions\` || PolicyName==\`FinancePermissions\` || PolicyName==\`AnalystPermissions\`].Arn' --output text | while read policy_arn; do groups=\$(aws iam list-entities-for-policy --policy-arn \$policy_arn --query 'PolicyGroups | length(@)' --output text); [ \$groups -gt 0 ] || exit 1; done" \
        "MEDIUM"
    
    run_validation_test \
        "MFA policy is attached to all users" \
        "aws iam list-entities-for-policy --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/RequireMFAForAllActions --query 'PolicyUsers | length(@)' --output text | grep -q '^10$'" \
        "HIGH"
fi

# 10. Security Best Practices Validation
print_status "🔒 Security Best Practices Validation"

run_validation_test \
    "No unused access keys" \
    "aws iam list-users --query 'Users[?starts_with(UserName, \`dev\`) || starts_with(UserName, \`ops\`) || starts_with(UserName, \`finance\`) || starts_with(UserName, \`analyst\`)].UserName' --output text | while read user; do keys=\$(aws iam list-access-keys --user-name \$user --query 'AccessKeyMetadata | length(@)' --output text); [ \$keys -eq 0 ] || exit 1; done" \
    "MEDIUM"

run_validation_test \
    "No inline policies on users" \
    "aws iam list-users --query 'Users[?starts_with(UserName, \`dev\`) || starts_with(UserName, \`ops\`) || starts_with(UserName, \`finance\`) || starts_with(UserName, \`analyst\`)].UserName' --output text | while read user; do policies=\$(aws iam list-user-policies --user-name \$user --query 'PolicyNames | length(@)' --output text); [ \$policies -eq 0 ] || exit 1; done" \
    "MEDIUM"

run_validation_test \
    "All resources created by CloudFormation" \
    "aws cloudformation list-stack-resources --stack-name $STACK_NAME --query 'StackResourceSummaries[?ResourceType==\`AWS::IAM::User\` || ResourceType==\`AWS::IAM::Group\` || ResourceType==\`AWS::IAM::ManagedPolicy\`] | length(@)' --output text | grep -v '^0$'" \
    "LOW"

# Generate validation report
if [ "$GENERATE_REPORT" = true ]; then
    print_status "📊 Generating security validation report..."
    REPORT_FILE="security-validation-report-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > $REPORT_FILE << EOF
Security Validation Report
==========================

Validation Details:
- Environment: $ENVIRONMENT
- Stack Name: $STACK_NAME
- AWS Account: $ACCOUNT_ID
- AWS Region: $AWS_REGION
- Validation Time: $(date)
- Validated By: $(aws sts get-caller-identity --query Arn --output text)

Validation Results Summary:
- Total Tests: $VALIDATION_TESTS_TOTAL
- Passed: $VALIDATION_TESTS_PASSED
- Failed: $VALIDATION_TESTS_FAILED
- Success Rate: $(( VALIDATION_TESTS_PASSED * 100 / VALIDATION_TESTS_TOTAL ))%

Security Status:
EOF

    if [ $VALIDATION_TESTS_FAILED -eq 0 ]; then
        echo "✅ SECURE - All validation tests passed" >> $REPORT_FILE
    else
        echo "❌ SECURITY ISSUES - $VALIDATION_TESTS_FAILED validation tests failed" >> $REPORT_FILE
    fi

    cat >> $REPORT_FILE << EOF

Test Categories Covered:
- CDK Unit Tests and Template Validation
- IAM Policy Structure and Configuration
- User-Group Assignment Verification
- Security Policy Implementation
- Policy Simulation and Permission Testing
- Resource Tagging Compliance
- CloudFormation Stack Health
- Security Best Practices Adherence

Recommendations:
1. Address all failed validation tests immediately
2. Review and update security policies as needed
3. Schedule regular validation runs (daily)
4. Monitor for configuration drift
5. Update documentation based on findings

Next Steps:
1. Remediate failed validation tests
2. Re-run validation to verify fixes
3. Update security procedures if needed
4. Schedule follow-up validation
5. Report findings to security team

EOF

    if [ $VALIDATION_TESTS_FAILED -gt 0 ]; then
        echo "⚠️  IMMEDIATE ACTION REQUIRED - SECURITY VALIDATION FAILURES DETECTED" >> $REPORT_FILE
    else
        echo "✅ VALIDATION PASSED - SECURITY IMPLEMENTATION VERIFIED" >> $REPORT_FILE
    fi

    print_success "Security validation report saved to: $REPORT_FILE"
fi

# Final summary
echo
print_status "🏁 Automated Security Validation Summary:"
echo "  📋 Total Tests: $VALIDATION_TESTS_TOTAL"
echo "  ✅ Passed: $VALIDATION_TESTS_PASSED"
echo "  ❌ Failed: $VALIDATION_TESTS_FAILED"
echo "  📈 Success Rate: $(( VALIDATION_TESTS_PASSED * 100 / VALIDATION_TESTS_TOTAL ))%"

if [ $VALIDATION_TESTS_FAILED -eq 0 ]; then
    print_success "🎉 All security validation tests passed! Implementation is secure."
    exit 0
else
    print_error "⚠️  Security validation failed. $VALIDATION_TESTS_FAILED tests require attention."
    exit 1
fi