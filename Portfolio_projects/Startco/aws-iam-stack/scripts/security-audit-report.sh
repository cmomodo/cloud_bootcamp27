#!/bin/bash

# Automated Security Audit and Reporting Tool
# This script generates comprehensive security audit reports

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT="production"
REPORT_FORMAT="html"
INCLUDE_RECOMMENDATIONS=true
VERBOSE=false

# Audit categories
AUDIT_CATEGORIES=("identity" "access" "encryption" "monitoring" "compliance" "network")

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
Automated Security Audit and Reporting Tool

Usage: $0 [OPTIONS]

Options:
    -e, --environment ENV    Target environment (production, staging, development) [default: production]
    -f, --format FORMAT     Report format (html, json, txt) [default: html]
    --no-recommendations    Skip security recommendations
    --verbose               Enable verbose output
    -h, --help              Show this help message

Examples:
    $0                                    # Generate HTML audit report for production
    $0 -f json --verbose                 # Generate JSON report with verbose output
    $0 -e staging -f txt                 # Generate text report for staging

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -f|--format)
            REPORT_FORMAT="$2"
            shift 2
            ;;
        --no-recommendations)
            INCLUDE_RECOMMENDATIONS=false
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

# Validate inputs
if [[ ! "$ENVIRONMENT" =~ ^(production|staging|development)$ ]]; then
    print_error "Invalid environment: $ENVIRONMENT"
    exit 1
fi

if [[ ! "$REPORT_FORMAT" =~ ^(html|json|txt)$ ]]; then
    print_error "Invalid report format: $REPORT_FORMAT"
    exit 1
fi

STACK_NAME="AwsSecurityStack-$ENVIRONMENT"
AWS_REGION=$(aws configure get region || echo "us-east-1")
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_FILE="security-audit-report-$TIMESTAMP.$REPORT_FORMAT"

print_status "🔍 Starting Automated Security Audit"
print_status "Environment: $ENVIRONMENT"
print_status "Account: $ACCOUNT_ID"
print_status "Region: $AWS_REGION"
print_status "Report Format: $REPORT_FORMAT"

# Check if stack exists
if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" &> /dev/null; then
    print_error "Stack $STACK_NAME not found in region $AWS_REGION"
    exit 1
fi

# Function to collect audit data
collect_audit_data() {
    print_status "📊 Collecting audit data..."
    
    # Identity and Access Management Data
    print_status "Collecting IAM data..."
    IAM_USERS=$(aws iam list-users --query 'Users' --output json)
    IAM_GROUPS=$(aws iam list-groups --query 'Groups' --output json)
    IAM_POLICIES=$(aws iam list-policies --scope Local --query 'Policies' --output json)
    ACCOUNT_SUMMARY=$(aws iam get-account-summary --query 'SummaryMap' --output json)
    
    # Try to get password policy (may not exist)
    PASSWORD_POLICY=$(aws iam get-account-password-policy --query 'PasswordPolicy' --output json 2>/dev/null || echo '{}')
    
    # CloudTrail Data
    print_status "Collecting CloudTrail data..."
    CLOUDTRAIL_TRAILS=$(aws cloudtrail describe-trails --query 'trailList' --output json)
    
    # CloudFormation Stack Data
    print_status "Collecting CloudFormation data..."
    STACK_RESOURCES=$(aws cloudformation list-stack-resources --stack-name "$STACK_NAME" --query 'StackResourceSummaries' --output json)
    STACK_INFO=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0]' --output json)
    
    # Security Group Data (if accessible)
    SECURITY_GROUPS=$(aws ec2 describe-security-groups --query 'SecurityGroups' --output json 2>/dev/null || echo '[]')
    
    # Cost and Billing Data (if accessible)
    COST_DATA=$(aws ce get-cost-and-usage --time-period Start=$(date -d '30 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) --granularity MONTHLY --metrics BlendedCost --query 'ResultsByTime' --output json 2>/dev/null || echo '[]')
}

# Function to analyze security posture
analyze_security_posture() {
    print_status "🔍 Analyzing security posture..."
    
    # Count resources
    USER_COUNT=$(echo "$IAM_USERS" | jq '. | length')
    GROUP_COUNT=$(echo "$IAM_GROUPS" | jq '. | length')
    POLICY_COUNT=$(echo "$IAM_POLICIES" | jq '. | length')
    
    # Check MFA status
    MFA_ENABLED=$(echo "$ACCOUNT_SUMMARY" | jq -r '.AccountMFAEnabled // 0')
    
    # Check password policy
    PASSWORD_MIN_LENGTH=$(echo "$PASSWORD_POLICY" | jq -r '.MinimumPasswordLength // 0')
    PASSWORD_COMPLEXITY=$(echo "$PASSWORD_POLICY" | jq -r '.RequireSymbols and .RequireNumbers and .RequireUppercaseCharacters and .RequireLowercaseCharacters // false')
    
    # Check CloudTrail
    CLOUDTRAIL_COUNT=$(echo "$CLOUDTRAIL_TRAILS" | jq '. | length')
    CLOUDTRAIL_LOGGING=$(echo "$CLOUDTRAIL_TRAILS" | jq '[.[] | select(.IsLogging == true)] | length')
    
    # Analyze user access patterns
    USERS_WITH_CONSOLE_ACCESS=$(echo "$IAM_USERS" | jq '[.[] | select(.PasswordLastUsed != null)] | length')
    USERS_WITH_ACCESS_KEYS=$(aws iam list-users --query 'Users[*].UserName' --output text | while read user; do aws iam list-access-keys --user-name "$user" --query 'AccessKeyMetadata | length(@)' --output text; done | awk '{sum+=$1} END {print sum+0}')
    
    # Security score calculation (0-100)
    SECURITY_SCORE=0
    
    # MFA enabled (20 points)
    [ "$MFA_ENABLED" = "1" ] && SECURITY_SCORE=$((SECURITY_SCORE + 20))
    
    # Strong password policy (20 points)
    [ "$PASSWORD_MIN_LENGTH" -ge 12 ] && SECURITY_SCORE=$((SECURITY_SCORE + 10))
    [ "$PASSWORD_COMPLEXITY" = "true" ] && SECURITY_SCORE=$((SECURITY_SCORE + 10))
    
    # CloudTrail logging (20 points)
    [ "$CLOUDTRAIL_LOGGING" -gt 0 ] && SECURITY_SCORE=$((SECURITY_SCORE + 20))
    
    # Proper IAM structure (20 points)
    [ "$GROUP_COUNT" -ge 4 ] && SECURITY_SCORE=$((SECURITY_SCORE + 10))
    [ "$POLICY_COUNT" -ge 4 ] && SECURITY_SCORE=$((SECURITY_SCORE + 10))
    
    # No direct user policies (10 points)
    USERS_WITH_DIRECT_POLICIES=$(echo "$IAM_USERS" | jq '[.[] | select(.UserName)] | length' | while read user; do aws iam list-attached-user-policies --user-name "$user" --query 'AttachedPolicies | length(@)' --output text 2>/dev/null || echo 0; done | awk '{sum+=$1} END {print sum+0}')
    [ "$USERS_WITH_DIRECT_POLICIES" -eq 0 ] && SECURITY_SCORE=$((SECURITY_SCORE + 10))
    
    # Users in groups (10 points)
    USERS_IN_GROUPS=$(aws iam list-users --query 'Users[*].UserName' --output text | while read user; do aws iam get-groups-for-user --user-name "$user" --query 'Groups | length(@)' --output text 2>/dev/null || echo 0; done | awk '{if($1>0) count++} END {print count+0}')
    [ "$USERS_IN_GROUPS" -eq "$USER_COUNT" ] && SECURITY_SCORE=$((SECURITY_SCORE + 10))
}

# Function to generate recommendations
generate_recommendations() {
    RECOMMENDATIONS=()
    
    # MFA recommendations
    if [ "$MFA_ENABLED" != "1" ]; then
        RECOMMENDATIONS+=("Enable MFA for the root account immediately")
    fi
    
    # Password policy recommendations
    if [ "$PASSWORD_MIN_LENGTH" -lt 12 ]; then
        RECOMMENDATIONS+=("Increase minimum password length to 12+ characters")
    fi
    
    if [ "$PASSWORD_COMPLEXITY" != "true" ]; then
        RECOMMENDATIONS+=("Enable password complexity requirements (uppercase, lowercase, numbers, symbols)")
    fi
    
    # CloudTrail recommendations
    if [ "$CLOUDTRAIL_LOGGING" -eq 0 ]; then
        RECOMMENDATIONS+=("Enable CloudTrail logging for audit trail")
    fi
    
    # IAM structure recommendations
    if [ "$GROUP_COUNT" -lt 4 ]; then
        RECOMMENDATIONS+=("Create role-based IAM groups for better access management")
    fi
    
    if [ "$USERS_WITH_DIRECT_POLICIES" -gt 0 ]; then
        RECOMMENDATIONS+=("Remove direct policy attachments from users, use groups instead")
    fi
    
    # Access key recommendations
    if [ "$USERS_WITH_ACCESS_KEYS" -gt 0 ]; then
        RECOMMENDATIONS+=("Review and rotate access keys regularly (every 90 days)")
    fi
    
    # Additional security recommendations
    RECOMMENDATIONS+=("Implement regular access reviews (monthly)")
    RECOMMENDATIONS+=("Enable AWS Config for configuration compliance monitoring")
    RECOMMENDATIONS+=("Set up CloudWatch alarms for security events")
    RECOMMENDATIONS+=("Implement permission boundaries for additional security")
    RECOMMENDATIONS+=("Regular security training for all team members")
}

# Function to generate HTML report
generate_html_report() {
    cat > "$REPORT_FILE" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AWS Security Audit Report - $ENVIRONMENT</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .header { text-align: center; border-bottom: 2px solid #007cba; padding-bottom: 20px; margin-bottom: 30px; }
        .score { font-size: 48px; font-weight: bold; color: #007cba; }
        .score-label { font-size: 18px; color: #666; }
        .section { margin: 30px 0; }
        .section h2 { color: #007cba; border-bottom: 1px solid #ddd; padding-bottom: 10px; }
        .metric { display: inline-block; margin: 10px 20px; text-align: center; }
        .metric-value { font-size: 24px; font-weight: bold; color: #007cba; }
        .metric-label { font-size: 14px; color: #666; }
        .status-good { color: #28a745; }
        .status-warning { color: #ffc107; }
        .status-danger { color: #dc3545; }
        .recommendations { background: #f8f9fa; padding: 20px; border-radius: 5px; }
        .recommendations ul { margin: 0; padding-left: 20px; }
        .recommendations li { margin: 10px 0; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #f8f9fa; font-weight: bold; }
        .footer { text-align: center; margin-top: 40px; padding-top: 20px; border-top: 1px solid #ddd; color: #666; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>AWS Security Audit Report</h1>
            <p><strong>Environment:</strong> $ENVIRONMENT | <strong>Account:</strong> $ACCOUNT_ID | <strong>Date:</strong> $(date)</p>
            <div class="score">$SECURITY_SCORE</div>
            <div class="score-label">Security Score (out of 100)</div>
        </div>

        <div class="section">
            <h2>Executive Summary</h2>
            <p>This automated security audit report provides a comprehensive assessment of the AWS security implementation for the $ENVIRONMENT environment. The security score of <strong>$SECURITY_SCORE/100</strong> is calculated based on key security controls and best practices.</p>
        </div>

        <div class="section">
            <h2>Key Metrics</h2>
            <div class="metric">
                <div class="metric-value">$USER_COUNT</div>
                <div class="metric-label">IAM Users</div>
            </div>
            <div class="metric">
                <div class="metric-value">$GROUP_COUNT</div>
                <div class="metric-label">IAM Groups</div>
            </div>
            <div class="metric">
                <div class="metric-value">$POLICY_COUNT</div>
                <div class="metric-label">Custom Policies</div>
            </div>
            <div class="metric">
                <div class="metric-value">$CLOUDTRAIL_LOGGING</div>
                <div class="metric-label">Active CloudTrails</div>
            </div>
        </div>

        <div class="section">
            <h2>Security Controls Assessment</h2>
            <table>
                <tr>
                    <th>Control</th>
                    <th>Status</th>
                    <th>Details</th>
                </tr>
                <tr>
                    <td>Root Account MFA</td>
                    <td class="$([ "$MFA_ENABLED" = "1" ] && echo "status-good" || echo "status-danger")">$([ "$MFA_ENABLED" = "1" ] && echo "✅ Enabled" || echo "❌ Disabled")</td>
                    <td>$([ "$MFA_ENABLED" = "1" ] && echo "Root account has MFA enabled" || echo "Root account MFA should be enabled immediately")</td>
                </tr>
                <tr>
                    <td>Password Policy</td>
                    <td class="$([ "$PASSWORD_MIN_LENGTH" -ge 12 ] && echo "status-good" || echo "status-warning")">$([ "$PASSWORD_MIN_LENGTH" -ge 12 ] && echo "✅ Strong" || echo "⚠️ Weak")</td>
                    <td>Minimum length: $PASSWORD_MIN_LENGTH characters, Complexity: $([ "$PASSWORD_COMPLEXITY" = "true" ] && echo "Enabled" || echo "Disabled")</td>
                </tr>
                <tr>
                    <td>CloudTrail Logging</td>
                    <td class="$([ "$CLOUDTRAIL_LOGGING" -gt 0 ] && echo "status-good" || echo "status-danger")">$([ "$CLOUDTRAIL_LOGGING" -gt 0 ] && echo "✅ Active" || echo "❌ Inactive")</td>
                    <td>$CLOUDTRAIL_LOGGING out of $CLOUDTRAIL_COUNT trails are actively logging</td>
                </tr>
                <tr>
                    <td>IAM Structure</td>
                    <td class="$([ "$GROUP_COUNT" -ge 4 ] && echo "status-good" || echo "status-warning")">$([ "$GROUP_COUNT" -ge 4 ] && echo "✅ Proper" || echo "⚠️ Needs Improvement")</td>
                    <td>$GROUP_COUNT groups configured for role-based access control</td>
                </tr>
            </table>
        </div>

        <div class="section">
            <h2>Resource Inventory</h2>
            <table>
                <tr>
                    <th>Resource Type</th>
                    <th>Count</th>
                    <th>Notes</th>
                </tr>
                <tr>
                    <td>IAM Users</td>
                    <td>$USER_COUNT</td>
                    <td>$USERS_WITH_CONSOLE_ACCESS have console access</td>
                </tr>
                <tr>
                    <td>IAM Groups</td>
                    <td>$GROUP_COUNT</td>
                    <td>Role-based access control groups</td>
                </tr>
                <tr>
                    <td>Custom Policies</td>
                    <td>$POLICY_COUNT</td>
                    <td>Locally managed policies</td>
                </tr>
                <tr>
                    <td>CloudFormation Resources</td>
                    <td>$(echo "$STACK_RESOURCES" | jq '. | length')</td>
                    <td>Resources managed by CDK stack</td>
                </tr>
            </table>
        </div>
EOF

    if [ "$INCLUDE_RECOMMENDATIONS" = true ]; then
        cat >> "$REPORT_FILE" << EOF
        <div class="section">
            <h2>Security Recommendations</h2>
            <div class="recommendations">
                <ul>
EOF
        for rec in "${RECOMMENDATIONS[@]}"; do
            echo "                    <li>$rec</li>" >> "$REPORT_FILE"
        done
        
        cat >> "$REPORT_FILE" << EOF
                </ul>
            </div>
        </div>
EOF
    fi

    cat >> "$REPORT_FILE" << EOF
        <div class="footer">
            <p>Report generated on $(date) by AWS Security Audit Tool</p>
            <p>Stack: $STACK_NAME | Region: $AWS_REGION</p>
        </div>
    </div>
</body>
</html>
EOF
}

# Function to generate JSON report
generate_json_report() {
    cat > "$REPORT_FILE" << EOF
{
  "audit_metadata": {
    "timestamp": "$(date -Iseconds)",
    "environment": "$ENVIRONMENT",
    "account_id": "$ACCOUNT_ID",
    "region": "$AWS_REGION",
    "stack_name": "$STACK_NAME",
    "auditor": "$(aws sts get-caller-identity --query Arn --output text)"
  },
  "security_score": $SECURITY_SCORE,
  "metrics": {
    "iam_users": $USER_COUNT,
    "iam_groups": $GROUP_COUNT,
    "custom_policies": $POLICY_COUNT,
    "cloudtrail_trails": $CLOUDTRAIL_COUNT,
    "active_cloudtrails": $CLOUDTRAIL_LOGGING,
    "users_with_console": $USERS_WITH_CONSOLE_ACCESS,
    "users_with_access_keys": $USERS_WITH_ACCESS_KEYS
  },
  "security_controls": {
    "root_mfa_enabled": $([ "$MFA_ENABLED" = "1" ] && echo "true" || echo "false"),
    "password_policy": {
      "minimum_length": $PASSWORD_MIN_LENGTH,
      "complexity_enabled": $([ "$PASSWORD_COMPLEXITY" = "true" ] && echo "true" || echo "false")
    },
    "cloudtrail_logging": $([ "$CLOUDTRAIL_LOGGING" -gt 0 ] && echo "true" || echo "false"),
    "proper_iam_structure": $([ "$GROUP_COUNT" -ge 4 ] && echo "true" || echo "false")
  },
  "recommendations": [
EOF

    # Add recommendations to JSON
    for i in "${!RECOMMENDATIONS[@]}"; do
        echo "    \"${RECOMMENDATIONS[$i]}\"$([ $i -lt $((${#RECOMMENDATIONS[@]} - 1)) ] && echo "," || echo "")" >> "$REPORT_FILE"
    done

    cat >> "$REPORT_FILE" << EOF
  ],
  "raw_data": {
    "iam_users": $IAM_USERS,
    "iam_groups": $IAM_GROUPS,
    "iam_policies": $IAM_POLICIES,
    "account_summary": $ACCOUNT_SUMMARY,
    "password_policy": $PASSWORD_POLICY,
    "cloudtrail_trails": $CLOUDTRAIL_TRAILS,
    "stack_resources": $STACK_RESOURCES,
    "stack_info": $STACK_INFO
  }
}
EOF
}

# Function to generate text report
generate_txt_report() {
    cat > "$REPORT_FILE" << EOF
AWS Security Audit Report
=========================

Report Details:
- Environment: $ENVIRONMENT
- AWS Account: $ACCOUNT_ID
- AWS Region: $AWS_REGION
- Stack Name: $STACK_NAME
- Audit Time: $(date)
- Audited By: $(aws sts get-caller-identity --query Arn --output text)

Security Score: $SECURITY_SCORE/100

Key Metrics:
- IAM Users: $USER_COUNT
- IAM Groups: $GROUP_COUNT
- Custom Policies: $POLICY_COUNT
- CloudTrail Trails: $CLOUDTRAIL_COUNT (Active: $CLOUDTRAIL_LOGGING)
- Users with Console Access: $USERS_WITH_CONSOLE_ACCESS
- Users with Access Keys: $USERS_WITH_ACCESS_KEYS

Security Controls Assessment:
- Root Account MFA: $([ "$MFA_ENABLED" = "1" ] && echo "✅ Enabled" || echo "❌ Disabled")
- Password Policy: $([ "$PASSWORD_MIN_LENGTH" -ge 12 ] && echo "✅ Strong" || echo "⚠️ Weak") (Min: $PASSWORD_MIN_LENGTH chars, Complexity: $([ "$PASSWORD_COMPLEXITY" = "true" ] && echo "Yes" || echo "No"))
- CloudTrail Logging: $([ "$CLOUDTRAIL_LOGGING" -gt 0 ] && echo "✅ Active" || echo "❌ Inactive")
- IAM Structure: $([ "$GROUP_COUNT" -ge 4 ] && echo "✅ Proper" || echo "⚠️ Needs Improvement")

EOF

    if [ "$INCLUDE_RECOMMENDATIONS" = true ]; then
        echo "Security Recommendations:" >> "$REPORT_FILE"
        for i in "${!RECOMMENDATIONS[@]}"; do
            echo "$((i + 1)). ${RECOMMENDATIONS[$i]}" >> "$REPORT_FILE"
        done
        echo >> "$REPORT_FILE"
    fi

    cat >> "$REPORT_FILE" << EOF
Resource Inventory:
- CloudFormation Resources: $(echo "$STACK_RESOURCES" | jq '. | length')
- Stack Status: $(echo "$STACK_INFO" | jq -r '.StackStatus')
- Stack Creation Time: $(echo "$STACK_INFO" | jq -r '.CreationTime')

Report generated by AWS Security Audit Tool
EOF
}

# Main execution
collect_audit_data
analyze_security_posture

if [ "$INCLUDE_RECOMMENDATIONS" = true ]; then
    generate_recommendations
fi

print_status "📝 Generating $REPORT_FORMAT report..."

case $REPORT_FORMAT in
    "html")
        generate_html_report
        ;;
    "json")
        generate_json_report
        ;;
    "txt")
        generate_txt_report
        ;;
esac

print_success "Security audit report generated: $REPORT_FILE"

# Final summary
echo
print_status "🏁 Security Audit Summary:"
echo "  🏆 Security Score: $SECURITY_SCORE/100"
echo "  👥 IAM Users: $USER_COUNT"
echo "  👥 IAM Groups: $GROUP_COUNT"
echo "  📋 Custom Policies: $POLICY_COUNT"
echo "  📊 CloudTrail Status: $CLOUDTRAIL_LOGGING/$CLOUDTRAIL_COUNT active"
echo "  📄 Report File: $REPORT_FILE"

if [ "$SECURITY_SCORE" -ge 80 ]; then
    print_success "🎉 Excellent security posture! Score: $SECURITY_SCORE/100"
elif [ "$SECURITY_SCORE" -ge 60 ]; then
    print_warning "⚠️  Good security posture with room for improvement. Score: $SECURITY_SCORE/100"
else
    print_error "❌ Security posture needs significant improvement. Score: $SECURITY_SCORE/100"
fi

exit 0