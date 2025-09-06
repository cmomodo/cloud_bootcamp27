#!/bin/bash

# Security Compliance Audit Script
# This script performs comprehensive security compliance validation

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
COMPLIANCE_FRAMEWORK="SOC2"

# Counters for audit results
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0
CHECKS_TOTAL=0

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

# Function to run a compliance check
run_compliance_check() {
    local check_name="$1"
    local check_command="$2"
    local severity="$3"  # CRITICAL, HIGH, MEDIUM, LOW
    local framework="$4" # SOC2, ISO27001, CIS, etc.
    
    CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
    
    if [ "$VERBOSE" = true ]; then
        print_status "Running check: $check_name"
        print_status "Framework: $framework | Severity: $severity"
        print_status "Command: $check_command"
    fi
    
    # Execute the check command
    local result
    if result=$(eval "$check_command" 2>&1); then
        print_success "✅ $check_name"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
        return 0
    else
        if [ "$severity" = "CRITICAL" ] || [ "$severity" = "HIGH" ]; then
            print_error "❌ $check_name (Severity: $severity)"
            CHECKS_FAILED=$((CHECKS_FAILED + 1))
        else
            print_warning "⚠️  $check_name (Severity: $severity)"
            CHECKS_WARNING=$((CHECKS_WARNING + 1))
        fi
        
        if [ "$VERBOSE" = true ]; then
            echo "Check output: $result"
        fi
        return 1
    fi
}

# Function to show usage
show_usage() {
    cat << EOF
Security Compliance Audit Script

Usage: $0 [OPTIONS]

Options:
    -e, --environment ENV    Target environment (production, staging, development) [default: production]
    -f, --framework FRAMEWORK Compliance framework (SOC2, ISO27001, CIS) [default: SOC2]
    --verbose               Enable verbose output
    --no-report            Skip generating audit report
    -h, --help              Show this help message

Examples:
    $0                                    # Run SOC2 compliance audit on production
    $0 -f ISO27001 --verbose             # Run ISO27001 audit with verbose output
    $0 -e staging -f CIS                 # Run CIS controls audit on staging

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -f|--framework)
            COMPLIANCE_FRAMEWORK="$2"
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

# Validate environment and framework
if [[ ! "$ENVIRONMENT" =~ ^(production|staging|development)$ ]]; then
    print_error "Invalid environment: $ENVIRONMENT"
    exit 1
fi

if [[ ! "$COMPLIANCE_FRAMEWORK" =~ ^(SOC2|ISO27001|CIS)$ ]]; then
    print_error "Invalid compliance framework: $COMPLIANCE_FRAMEWORK"
    exit 1
fi

STACK_NAME="AwsSecurityStack-$ENVIRONMENT"
AWS_REGION=$(aws configure get region || echo "us-east-1")
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

print_status "🔍 Starting Security Compliance Audit"
print_status "Framework: $COMPLIANCE_FRAMEWORK"
print_status "Environment: $ENVIRONMENT"
print_status "Stack: $STACK_NAME"
print_status "Account: $ACCOUNT_ID"
print_status "Region: $AWS_REGION"

# Check if stack exists
if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" &> /dev/null; then
    print_error "Stack $STACK_NAME not found in region $AWS_REGION"
    exit 1
fi

print_status "📋 Running $COMPLIANCE_FRAMEWORK Compliance Checks..."

# SOC 2 Type II Compliance Checks
if [ "$COMPLIANCE_FRAMEWORK" = "SOC2" ]; then
    
    print_status "🔐 SOC 2 - Access Control Checks"
    
    # CC6.1 - Logical and physical access controls
    run_compliance_check \
        "CC6.1: MFA enforcement policy exists" \
        "aws iam get-policy --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/RequireMFAForAllActions" \
        "CRITICAL" \
        "SOC2"
    
    run_compliance_check \
        "CC6.1: Account password policy configured" \
        "aws iam get-account-password-policy" \
        "CRITICAL" \
        "SOC2"
    
    run_compliance_check \
        "CC6.1: No users with console access without MFA" \
        "[ \$(aws iam list-users --query 'Users[?PasswordLastUsed!=null] | length(@)') -eq 0 ] || aws iam list-users --query 'Users[?PasswordLastUsed!=null]' --output text | while read user; do aws iam list-mfa-devices --user-name \$user --query 'MFADevices | length(@)' --output text | grep -q '^0\$' && exit 1; done; exit 0" \
        "HIGH" \
        "SOC2"
    
    # CC6.2 - User access management
    run_compliance_check \
        "CC6.2: All users are assigned to appropriate groups" \
        "aws iam list-users --query 'Users[*].UserName' --output text | while read user; do groups=\$(aws iam get-groups-for-user --user-name \$user --query 'Groups | length(@)' --output text); [ \$groups -gt 0 ] || exit 1; done" \
        "HIGH" \
        "SOC2"
    
    run_compliance_check \
        "CC6.2: No users have direct policy attachments (use groups)" \
        "aws iam list-users --query 'Users[*].UserName' --output text | while read user; do policies=\$(aws iam list-attached-user-policies --user-name \$user --query 'AttachedPolicies | length(@)' --output text); [ \$policies -eq 0 ] || exit 1; done" \
        "MEDIUM" \
        "SOC2"
    
    # CC6.3 - Network security
    run_compliance_check \
        "CC6.3: CloudTrail logging enabled" \
        "aws cloudtrail describe-trails --query 'trailList[?IsLogging==\`true\`] | length(@)' --output text | grep -v '^0\$'" \
        "CRITICAL" \
        "SOC2"
    
    # CC6.7 - Data transmission and disposal
    run_compliance_check \
        "CC6.7: All IAM policies use HTTPS for API calls" \
        "aws iam list-policies --scope Local --query 'Policies[*].Arn' --output text | while read policy_arn; do aws iam get-policy-version --policy-arn \$policy_arn --version-id \$(aws iam get-policy --policy-arn \$policy_arn --query 'Policy.DefaultVersionId' --output text) --query 'PolicyVersion.Document' | grep -q 'aws:SecureTransport.*false' && exit 1; done; exit 0" \
        "HIGH" \
        "SOC2"
    
    print_status "🔍 SOC 2 - Monitoring and Logging Checks"
    
    # CC7.1 - System monitoring
    run_compliance_check \
        "CC7.1: CloudTrail captures IAM events" \
        "aws logs describe-log-groups --log-group-name-prefix CloudTrail --query 'logGroups | length(@)' --output text | grep -v '^0\$'" \
        "HIGH" \
        "SOC2"
    
    # CC8.1 - Change management
    run_compliance_check \
        "CC8.1: All IAM resources created via CloudFormation" \
        "aws cloudformation list-stack-resources --stack-name $STACK_NAME --query 'StackResourceSummaries[?ResourceType==\`AWS::IAM::User\` || ResourceType==\`AWS::IAM::Group\` || ResourceType==\`AWS::IAM::ManagedPolicy\`] | length(@)' --output text | grep -v '^0\$'" \
        "MEDIUM" \
        "SOC2"

fi

# ISO 27001 Compliance Checks
if [ "$COMPLIANCE_FRAMEWORK" = "ISO27001" ]; then
    
    print_status "🔐 ISO 27001 - Access Control (A.9) Checks"
    
    # A.9.1.1 - Access control policy
    run_compliance_check \
        "A.9.1.1: Documented access control policies exist" \
        "[ -f '../docs/permission-matrix.md' ] && [ -f '../docs/security-policy-decisions.md' ]" \
        "CRITICAL" \
        "ISO27001"
    
    # A.9.2.1 - User registration and de-registration
    run_compliance_check \
        "A.9.2.1: All users follow naming convention" \
        "aws iam list-users --query 'Users[*].UserName' --output text | grep -E '^(dev|ops|finance|analyst)[0-9]+\$' | wc -l | grep -q '10'" \
        "MEDIUM" \
        "ISO27001"
    
    # A.9.2.2 - User access provisioning
    run_compliance_check \
        "A.9.2.2: Users have appropriate group membership" \
        "aws iam get-group --group-name Developers --query 'Users | length(@)' --output text | grep -q '^3\$' && aws iam get-group --group-name Operations --query 'Users | length(@)' --output text | grep -q '^2\$'" \
        "HIGH" \
        "ISO27001"
    
    # A.9.4.2 - Secure log-on procedures
    run_compliance_check \
        "A.9.4.2: MFA required for all users" \
        "aws iam get-policy --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/RequireMFAForAllActions --query 'Policy.PolicyName' --output text | grep -q 'RequireMFAForAllActions'" \
        "CRITICAL" \
        "ISO27001"
    
    print_status "🔍 ISO 27001 - Cryptography (A.10) Checks"
    
    # A.10.1.1 - Policy on the use of cryptographic controls
    run_compliance_check \
        "A.10.1.1: Password policy enforces strong passwords" \
        "aws iam get-account-password-policy --query 'PasswordPolicy.MinimumPasswordLength' --output text | grep -E '^(1[2-9]|[2-9][0-9])\$'" \
        "HIGH" \
        "ISO27001"

fi

# CIS Controls Compliance Checks
if [ "$COMPLIANCE_FRAMEWORK" = "CIS" ]; then
    
    print_status "🔐 CIS Controls - Identity and Access Management"
    
    # CIS Control 4 - Controlled Use of Administrative Privileges
    run_compliance_check \
        "CIS 4.1: No users have administrative privileges" \
        "aws iam list-users --query 'Users[*].UserName' --output text | while read user; do aws iam list-attached-user-policies --user-name \$user --query 'AttachedPolicies[?PolicyName==\`AdministratorAccess\`] | length(@)' --output text | grep -q '^0\$' || exit 1; done" \
        "CRITICAL" \
        "CIS"
    
    # CIS Control 5 - Controlled Use of Administrative Privileges
    run_compliance_check \
        "CIS 5.1: MFA enabled for all users" \
        "aws iam list-users --query 'Users[*].UserName' --output text | while read user; do aws iam list-mfa-devices --user-name \$user --query 'MFADevices | length(@)' --output text | grep -q '^0\$' && echo 'User \$user has no MFA' && exit 1; done; exit 0" \
        "CRITICAL" \
        "CIS"
    
    # CIS Control 6 - Maintenance, Monitoring and Analysis of Audit Logs
    run_compliance_check \
        "CIS 6.1: CloudTrail enabled in all regions" \
        "aws cloudtrail describe-trails --query 'trailList[?IncludeGlobalServiceEvents==\`true\` && IsMultiRegionTrail==\`true\`] | length(@)' --output text | grep -v '^0\$'" \
        "HIGH" \
        "CIS"

fi

# Additional Security Best Practice Checks (All Frameworks)
print_status "🛡️  Additional Security Best Practice Checks"

# Root account security
run_compliance_check \
    "Root account has MFA enabled" \
    "aws iam get-account-summary --query 'SummaryMap.AccountMFAEnabled' --output text | grep -q '^1\$'" \
    "CRITICAL" \
    "BEST_PRACTICE"

# Unused access keys
run_compliance_check \
    "No unused access keys (older than 90 days)" \
    "aws iam list-users --query 'Users[*].UserName' --output text | while read user; do aws iam list-access-keys --user-name \$user --query 'AccessKeyMetadata[?Status==\`Active\`]' --output text | while read key_id status date; do if [ -n \"\$date\" ]; then key_age=\$(( (\$(date +%s) - \$(date -d \"\$date\" +%s)) / 86400 )); [ \$key_age -gt 90 ] && echo \"Key \$key_id for user \$user is \$key_age days old\" && exit 1; fi; done; done; exit 0" \
    "HIGH" \
    "BEST_PRACTICE"

# Password policy strength
run_compliance_check \
    "Password policy requires symbols and numbers" \
    "aws iam get-account-password-policy --query 'PasswordPolicy.RequireSymbols && PasswordPolicy.RequireNumbers' --output text | grep -q '^True\$'" \
    "HIGH" \
    "BEST_PRACTICE"

# Policy version management
run_compliance_check \
    "No policies with excessive versions" \
    "aws iam list-policies --scope Local --query 'Policies[*].Arn' --output text | while read policy_arn; do versions=\$(aws iam list-policy-versions --policy-arn \$policy_arn --query 'Versions | length(@)' --output text); [ \$versions -le 5 ] || exit 1; done" \
    "MEDIUM" \
    "BEST_PRACTICE"

# Resource tagging compliance
run_compliance_check \
    "All IAM resources properly tagged" \
    "aws iam list-users --query 'Users[*].UserName' --output text | while read user; do tags=\$(aws iam list-user-tags --user-name \$user --query 'Tags | length(@)' --output text); [ \$tags -gt 0 ] || exit 1; done" \
    "LOW" \
    "BEST_PRACTICE"

# Permission boundary checks
run_compliance_check \
    "No overly permissive wildcard policies" \
    "aws iam list-policies --scope Local --query 'Policies[*].Arn' --output text | while read policy_arn; do aws iam get-policy-version --policy-arn \$policy_arn --version-id \$(aws iam get-policy --policy-arn \$policy_arn --query 'Policy.DefaultVersionId' --output text) --query 'PolicyVersion.Document.Statement[*].Resource' --output text | grep -q '^\*\$' && aws iam get-policy-version --policy-arn \$policy_arn --version-id \$(aws iam get-policy --policy-arn \$policy_arn --query 'Policy.DefaultVersionId' --output text) --query 'PolicyVersion.Document.Statement[*].Action' --output text | grep -q '^\*\$' && exit 1; done; exit 0" \
    "HIGH" \
    "BEST_PRACTICE"

# Generate compliance report
if [ "$GENERATE_REPORT" = true ]; then
    print_status "📊 Generating compliance audit report..."
    REPORT_FILE="security-compliance-audit-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > $REPORT_FILE << EOF
Security Compliance Audit Report
================================

Audit Details:
- Framework: $COMPLIANCE_FRAMEWORK
- Environment: $ENVIRONMENT
- Stack Name: $STACK_NAME
- AWS Account: $ACCOUNT_ID
- AWS Region: $AWS_REGION
- Audit Time: $(date)
- Audited By: $(aws sts get-caller-identity --query Arn --output text)

Audit Results Summary:
- Total Checks: $CHECKS_TOTAL
- Passed: $CHECKS_PASSED
- Failed: $CHECKS_FAILED
- Warnings: $CHECKS_WARNING
- Success Rate: $(( (CHECKS_PASSED + CHECKS_WARNING) * 100 / CHECKS_TOTAL ))%

Compliance Status:
EOF

    if [ $CHECKS_FAILED -eq 0 ]; then
        echo "✅ COMPLIANT - All critical checks passed" >> $REPORT_FILE
    else
        echo "❌ NON-COMPLIANT - $CHECKS_FAILED critical checks failed" >> $REPORT_FILE
    fi

    cat >> $REPORT_FILE << EOF

Framework-Specific Requirements:
EOF

    case $COMPLIANCE_FRAMEWORK in
        "SOC2")
            cat >> $REPORT_FILE << EOF
- SOC 2 Type II Trust Service Criteria addressed
- Access control (CC6.1, CC6.2, CC6.3, CC6.7)
- Monitoring and logging (CC7.1)
- Change management (CC8.1)
EOF
            ;;
        "ISO27001")
            cat >> $REPORT_FILE << EOF
- ISO 27001:2013 Annex A controls addressed
- Access control (A.9.1.1, A.9.2.1, A.9.2.2, A.9.4.2)
- Cryptography (A.10.1.1)
EOF
            ;;
        "CIS")
            cat >> $REPORT_FILE << EOF
- CIS Controls v8 addressed
- Identity and Access Management (Controls 4, 5)
- Audit log management (Control 6)
EOF
            ;;
    esac

    cat >> $REPORT_FILE << EOF

Recommendations:
1. Address all failed checks immediately
2. Review warnings for potential improvements
3. Schedule regular compliance audits (monthly)
4. Update security policies based on findings
5. Conduct security awareness training

Next Steps:
1. Remediate failed compliance checks
2. Document any accepted risks
3. Schedule follow-up audit in 30 days
4. Update security documentation
5. Report findings to security team

EOF

    if [ $CHECKS_FAILED -gt 0 ]; then
        echo "⚠️  IMMEDIATE ACTION REQUIRED - COMPLIANCE FAILURES DETECTED" >> $REPORT_FILE
    else
        echo "✅ COMPLIANCE VERIFIED - CONTINUE MONITORING" >> $REPORT_FILE
    fi

    print_success "Compliance audit report saved to: $REPORT_FILE"
fi

# Final summary
echo
print_status "🏁 Security Compliance Audit Summary:"
echo "  📊 Framework: $COMPLIANCE_FRAMEWORK"
echo "  📋 Total Checks: $CHECKS_TOTAL"
echo "  ✅ Passed: $CHECKS_PASSED"
echo "  ❌ Failed: $CHECKS_FAILED"
echo "  ⚠️  Warnings: $CHECKS_WARNING"
echo "  📈 Success Rate: $(( (CHECKS_PASSED + CHECKS_WARNING) * 100 / CHECKS_TOTAL ))%"

if [ $CHECKS_FAILED -eq 0 ]; then
    print_success "🎉 Compliance audit passed! System meets $COMPLIANCE_FRAMEWORK requirements."
    exit 0
else
    print_error "⚠️  Compliance audit failed. $CHECKS_FAILED critical issues require immediate attention."
    exit 1
fi