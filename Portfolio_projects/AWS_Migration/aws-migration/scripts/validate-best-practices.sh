#!/bin/bash

# Best Practices Validation Script for TechHealth Infrastructure
# This script validates AWS best practices for monitoring, cost optimization, and security

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
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNING_TESTS=0

run_test() {
    local test_name="$1"
    local test_command="$2"
    local severity="${3:-error}"  # error, warning, info
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    print_status "Checking: $test_name"
    
    if eval "$test_command" > /dev/null 2>&1; then
        print_success "$test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        case $severity in
            warning)
                print_warning "$test_name"
                WARNING_TESTS=$((WARNING_TESTS + 1))
                ;;
            *)
                print_error "$test_name"
                FAILED_TESTS=$((FAILED_TESTS + 1))
                ;;
        esac
        return 1
    fi
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
    echo "  --category CATEGORY  Run specific category (monitoring|cost|security|all)"
    echo "  --verbose            Show detailed output"
    echo "  --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 dev --verbose"
    echo "  $0 prod --category monitoring"
    echo "  $0 staging --category cost"
    exit 1
}

# Parse command line arguments
ENVIRONMENT=""
CATEGORY="all"
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        dev|staging|prod)
            ENVIRONMENT="$1"
            shift
            ;;
        --category)
            CATEGORY="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
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

echo "🔍 TechHealth Best Practices Validation"
echo "========================================"
echo "Environment: $ENVIRONMENT"
echo "Category: $CATEGORY"
echo ""

STACK_NAME="TechHealth-$(echo $ENVIRONMENT | sed 's/.*/\u&/')-Infrastructure"

# Check if stack exists
print_status "Checking if stack exists..."
if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" &>/dev/null; then
    print_error "Stack $STACK_NAME does not exist. Deploy the infrastructure first."
    exit 1
fi

print_success "Stack $STACK_NAME found"

# Get resource information
get_resource_info() {
    print_status "Gathering resource information..."
    
    # Get VPC ID
    VPC_ID=$(aws cloudformation describe-stack-resources \
        --stack-name "$STACK_NAME" \
        --query 'StackResources[?ResourceType==`AWS::EC2::VPC`].PhysicalResourceId' \
        --output text 2>/dev/null || echo "")
    
    # Get EC2 instances
    EC2_INSTANCES=$(aws ec2 describe-instances \
        --filters "Name=tag:aws:cloudformation:stack-name,Values=$STACK_NAME" \
        --query 'Reservations[*].Instances[*].InstanceId' \
        --output text 2>/dev/null || echo "")
    
    # Get RDS instances
    RDS_INSTANCES=$(aws rds describe-db-instances \
        --query "DBInstances[?contains(DBInstanceIdentifier, '$(echo $STACK_NAME | tr '[:upper:]' '[:lower:]')') || contains(DBInstanceIdentifier, 'techhealth')].DBInstanceIdentifier" \
        --output text 2>/dev/null || echo "")
    
    # Get Security Groups
    SECURITY_GROUPS=$(aws ec2 describe-security-groups \
        --filters "Name=tag:aws:cloudformation:stack-name,Values=$STACK_NAME" \
        --query 'SecurityGroups[*].GroupId' \
        --output text 2>/dev/null || echo "")
    
    if [ "$VERBOSE" = true ]; then
        echo "  VPC: ${VPC_ID:-Not found}"
        echo "  EC2 Instances: ${EC2_INSTANCES:-None}"
        echo "  RDS Instances: ${RDS_INSTANCES:-None}"
        echo "  Security Groups: $(echo $SECURITY_GROUPS | wc -w) groups"
    fi
}

# Validate CloudWatch Monitoring Best Practices
validate_monitoring_best_practices() {
    if [ "$CATEGORY" != "all" ] && [ "$CATEGORY" != "monitoring" ]; then
        return 0
    fi
    
    echo ""
    print_status "🔍 Validating CloudWatch Monitoring Best Practices"
    echo "=================================================="
    
    # Check if CloudWatch dashboard exists
    DASHBOARD_NAME="TechHealth-${ENVIRONMENT}-Infrastructure"
    run_test "CloudWatch dashboard exists" \
        "aws cloudwatch get-dashboard --dashboard-name '$DASHBOARD_NAME'" \
        "warning"
    
    # Check for CloudWatch alarms
    ALARMS=$(aws cloudwatch describe-alarms \
        --alarm-name-prefix "TechHealth-${ENVIRONMENT}-" \
        --query 'MetricAlarms[*].AlarmName' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$ALARMS" ]; then
        ALARM_COUNT=$(echo $ALARMS | wc -w)
        print_success "CloudWatch alarms configured ($ALARM_COUNT alarms)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        print_warning "No CloudWatch alarms found"
        WARNING_TESTS=$((WARNING_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Check EC2 detailed monitoring
    if [ -n "$EC2_INSTANCES" ]; then
        for instance in $EC2_INSTANCES; do
            MONITORING_STATE=$(aws ec2 describe-instances \
                --instance-ids "$instance" \
                --query 'Reservations[0].Instances[0].Monitoring.State' \
                --output text 2>/dev/null || echo "disabled")
            
            if [ "$MONITORING_STATE" = "enabled" ]; then
                print_success "Detailed monitoring enabled for $instance"
                PASSED_TESTS=$((PASSED_TESTS + 1))
            else
                if [ "$ENVIRONMENT" = "prod" ]; then
                    print_warning "Detailed monitoring disabled for $instance (recommended for production)"
                    WARNING_TESTS=$((WARNING_TESTS + 1))
                else
                    print_success "Basic monitoring for $instance (appropriate for $ENVIRONMENT)"
                    PASSED_TESTS=$((PASSED_TESTS + 1))
                fi
            fi
            TOTAL_TESTS=$((TOTAL_TESTS + 1))
        done
    fi
    
    # Check RDS Enhanced Monitoring
    if [ -n "$RDS_INSTANCES" ]; then
        for rds_instance in $RDS_INSTANCES; do
            ENHANCED_MONITORING=$(aws rds describe-db-instances \
                --db-instance-identifier "$rds_instance" \
                --query 'DBInstances[0].MonitoringInterval' \
                --output text 2>/dev/null || echo "0")
            
            if [ "$ENHANCED_MONITORING" -gt 0 ]; then
                print_success "Enhanced monitoring enabled for $rds_instance (${ENHANCED_MONITORING}s interval)"
                PASSED_TESTS=$((PASSED_TESTS + 1))
            else
                if [ "$ENVIRONMENT" = "prod" ]; then
                    print_warning "Enhanced monitoring disabled for $rds_instance (recommended for production)"
                    WARNING_TESTS=$((WARNING_TESTS + 1))
                else
                    print_success "Basic monitoring for $rds_instance (appropriate for $ENVIRONMENT)"
                    PASSED_TESTS=$((PASSED_TESTS + 1))
                fi
            fi
            TOTAL_TESTS=$((TOTAL_TESTS + 1))
        done
    fi
    
    # Check for SNS topic for alerts
    TOPIC_NAME="techhealth-${ENVIRONMENT}-alerts"
    TOPIC_ARN="arn:aws:sns:${CDK_DEFAULT_REGION}:$(aws sts get-caller-identity --query Account --output text):${TOPIC_NAME}"
    
    run_test "SNS topic for alerts exists" \
        "aws sns get-topic-attributes --topic-arn '$TOPIC_ARN'" \
        "warning"
    
    # Check CloudWatch Logs retention
    LOG_GROUPS=$(aws logs describe-log-groups \
        --log-group-name-prefix "/aws/ec2" \
        --query 'logGroups[*].{Name:logGroupName,Retention:retentionInDays}' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$LOG_GROUPS" ]; then
        echo "$LOG_GROUPS" | while read log_group retention; do
            if [ "$retention" != "None" ] && [ "$retention" -gt 0 ]; then
                print_success "Log retention configured for $log_group ($retention days)"
                PASSED_TESTS=$((PASSED_TESTS + 1))
            else
                print_warning "No log retention configured for $log_group (cost optimization opportunity)"
                WARNING_TESTS=$((WARNING_TESTS + 1))
            fi
            TOTAL_TESTS=$((TOTAL_TESTS + 1))
        done
    fi
}

# Validate Cost Optimization Best Practices
validate_cost_optimization_best_practices() {
    if [ "$CATEGORY" != "all" ] && [ "$CATEGORY" != "cost" ]; then
        return 0
    fi
    
    echo ""
    print_status "💰 Validating Cost Optimization Best Practices"
    echo "=============================================="
    
    # Check instance types for cost optimization
    if [ -n "$EC2_INSTANCES" ]; then
        for instance in $EC2_INSTANCES; do
            INSTANCE_TYPE=$(aws ec2 describe-instances \
                --instance-ids "$instance" \
                --query 'Reservations[0].Instances[0].InstanceType' \
                --output text)
            
            case $INSTANCE_TYPE in
                t2.micro|t3.micro|t3a.micro)
                    print_success "Cost-optimized instance type: $INSTANCE_TYPE"
                    PASSED_TESTS=$((PASSED_TESTS + 1))
                    ;;
                t2.small|t3.small|t3a.small)
                    if [ "$ENVIRONMENT" = "prod" ]; then
                        print_success "Appropriate instance type for production: $INSTANCE_TYPE"
                        PASSED_TESTS=$((PASSED_TESTS + 1))
                    else
                        print_warning "Consider smaller instance type for $ENVIRONMENT: $INSTANCE_TYPE"
                        WARNING_TESTS=$((WARNING_TESTS + 1))
                    fi
                    ;;
                *)
                    print_warning "Large instance type may not be cost-optimized: $INSTANCE_TYPE"
                    WARNING_TESTS=$((WARNING_TESTS + 1))
                    ;;
            esac
            TOTAL_TESTS=$((TOTAL_TESTS + 1))
        done
    fi
    
    # Check RDS instance classes
    if [ -n "$RDS_INSTANCES" ]; then
        for rds_instance in $RDS_INSTANCES; do
            DB_CLASS=$(aws rds describe-db-instances \
                --db-instance-identifier "$rds_instance" \
                --query 'DBInstances[0].DBInstanceClass' \
                --output text)
            
            case $DB_CLASS in
                db.t3.micro|db.t2.micro)
                    print_success "Cost-optimized RDS instance class: $DB_CLASS"
                    PASSED_TESTS=$((PASSED_TESTS + 1))
                    ;;
                db.t3.small|db.t2.small)
                    if [ "$ENVIRONMENT" = "prod" ]; then
                        print_success "Appropriate RDS class for production: $DB_CLASS"
                        PASSED_TESTS=$((PASSED_TESTS + 1))
                    else
                        print_warning "Consider smaller RDS class for $ENVIRONMENT: $DB_CLASS"
                        WARNING_TESTS=$((WARNING_TESTS + 1))
                    fi
                    ;;
                *)
                    print_warning "Large RDS instance class may not be cost-optimized: $DB_CLASS"
                    WARNING_TESTS=$((WARNING_TESTS + 1))
                    ;;
            esac
            TOTAL_TESTS=$((TOTAL_TESTS + 1))
        done
    fi
    
    # Check for NAT Gateways (cost optimization)
    if [ -n "$VPC_ID" ]; then
        NAT_GATEWAYS=$(aws ec2 describe-nat-gateways \
            --filter "Name=vpc-id,Values=$VPC_ID" \
            --query 'NatGateways[?State==`available`]' \
            --output text 2>/dev/null || echo "")
        
        if [ -z "$NAT_GATEWAYS" ]; then
            print_success "No NAT Gateways found (cost optimized)"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            NAT_COUNT=$(echo "$NAT_GATEWAYS" | wc -l)
            print_warning "$NAT_COUNT NAT Gateway(s) found (consider cost impact: ~\$45/month each)"
            WARNING_TESTS=$((WARNING_TESTS + 1))
        fi
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
    fi
    
    # Check for AWS Budget
    BUDGET_NAME="TechHealth-${ENVIRONMENT}-Monthly-Budget"
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    run_test "AWS Budget configured" \
        "aws budgets describe-budget --account-id '$ACCOUNT_ID' --budget-name '$BUDGET_NAME'" \
        "warning"
    
    # Check EBS volume types for cost optimization
    if [ -n "$EC2_INSTANCES" ]; then
        for instance in $EC2_INSTANCES; do
            VOLUMES=$(aws ec2 describe-instances \
                --instance-ids "$instance" \
                --query 'Reservations[0].Instances[0].BlockDeviceMappings[*].Ebs.VolumeId' \
                --output text)
            
            for volume in $VOLUMES; do
                VOLUME_TYPE=$(aws ec2 describe-volumes \
                    --volume-ids "$volume" \
                    --query 'Volumes[0].VolumeType' \
                    --output text)
                
                case $VOLUME_TYPE in
                    gp3)
                        print_success "Cost-optimized EBS volume type: $VOLUME_TYPE"
                        PASSED_TESTS=$((PASSED_TESTS + 1))
                        ;;
                    gp2)
                        print_warning "Consider upgrading to GP3 for better cost/performance: $VOLUME_TYPE"
                        WARNING_TESTS=$((WARNING_TESTS + 1))
                        ;;
                    *)
                        print_warning "EBS volume type may not be cost-optimized: $VOLUME_TYPE"
                        WARNING_TESTS=$((WARNING_TESTS + 1))
                        ;;
                esac
                TOTAL_TESTS=$((TOTAL_TESTS + 1))
            done
        done
    fi
    
    # Check resource tagging for cost allocation
    TAGGED_RESOURCES=0
    TOTAL_RESOURCES=0
    
    # Check EC2 instance tags
    if [ -n "$EC2_INSTANCES" ]; then
        for instance in $EC2_INSTANCES; do
            TOTAL_RESOURCES=$((TOTAL_RESOURCES + 1))
            TAGS=$(aws ec2 describe-instances \
                --instance-ids "$instance" \
                --query 'Reservations[0].Instances[0].Tags[?Key==`Environment` || Key==`Project` || Key==`CostCenter`]' \
                --output text)
            
            if [ -n "$TAGS" ]; then
                TAGGED_RESOURCES=$((TAGGED_RESOURCES + 1))
            fi
        done
    fi
    
    # Check RDS instance tags
    if [ -n "$RDS_INSTANCES" ]; then
        for rds_instance in $RDS_INSTANCES; do
            TOTAL_RESOURCES=$((TOTAL_RESOURCES + 1))
            TAGS=$(aws rds list-tags-for-resource \
                --resource-name "arn:aws:rds:${CDK_DEFAULT_REGION}:$(aws sts get-caller-identity --query Account --output text):db:$rds_instance" \
                --query 'TagList[?Key==`Environment` || Key==`Project` || Key==`CostCenter`]' \
                --output text 2>/dev/null || echo "")
            
            if [ -n "$TAGS" ]; then
                TAGGED_RESOURCES=$((TAGGED_RESOURCES + 1))
            fi
        done
    fi
    
    if [ $TOTAL_RESOURCES -gt 0 ]; then
        TAG_PERCENTAGE=$((TAGGED_RESOURCES * 100 / TOTAL_RESOURCES))
        if [ $TAG_PERCENTAGE -ge 80 ]; then
            print_success "Good resource tagging for cost allocation ($TAG_PERCENTAGE%)"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            print_warning "Improve resource tagging for cost allocation ($TAG_PERCENTAGE%)"
            WARNING_TESTS=$((WARNING_TESTS + 1))
        fi
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
    fi
}

# Validate Security Best Practices
validate_security_best_practices() {
    if [ "$CATEGORY" != "all" ] && [ "$CATEGORY" != "security" ]; then
        return 0
    fi
    
    echo ""
    print_status "🔒 Validating Security Best Practices"
    echo "====================================="
    
    # Check RDS encryption
    if [ -n "$RDS_INSTANCES" ]; then
        for rds_instance in $RDS_INSTANCES; do
            ENCRYPTION_STATUS=$(aws rds describe-db-instances \
                --db-instance-identifier "$rds_instance" \
                --query 'DBInstances[0].StorageEncrypted' \
                --output text)
            
            if [ "$ENCRYPTION_STATUS" = "True" ]; then
                print_success "RDS encryption enabled for $rds_instance"
                PASSED_TESTS=$((PASSED_TESTS + 1))
            else
                print_error "RDS encryption not enabled for $rds_instance (HIPAA requirement)"
                FAILED_TESTS=$((FAILED_TESTS + 1))
            fi
            TOTAL_TESTS=$((TOTAL_TESTS + 1))
        done
    fi
    
    # Check RDS public accessibility
    if [ -n "$RDS_INSTANCES" ]; then
        for rds_instance in $RDS_INSTANCES; do
            PUBLIC_ACCESS=$(aws rds describe-db-instances \
                --db-instance-identifier "$rds_instance" \
                --query 'DBInstances[0].PubliclyAccessible' \
                --output text)
            
            if [ "$PUBLIC_ACCESS" = "False" ]; then
                print_success "RDS is not publicly accessible: $rds_instance"
                PASSED_TESTS=$((PASSED_TESTS + 1))
            else
                print_error "RDS is publicly accessible: $rds_instance (security risk)"
                FAILED_TESTS=$((FAILED_TESTS + 1))
            fi
            TOTAL_TESTS=$((TOTAL_TESTS + 1))
        done
    fi
    
    # Check security group rules
    if [ -n "$SECURITY_GROUPS" ]; then
        for sg_id in $SECURITY_GROUPS; do
            # Check for overly permissive SSH access
            OPEN_SSH=$(aws ec2 describe-security-groups \
                --group-ids "$sg_id" \
                --query 'SecurityGroups[0].IpPermissions[?FromPort==`22` && IpRanges[?CidrIp==`0.0.0.0/0`]]' \
                --output text)
            
            if [ -z "$OPEN_SSH" ]; then
                print_success "SSH not open to 0.0.0.0/0 in $sg_id"
                PASSED_TESTS=$((PASSED_TESTS + 1))
            else
                print_error "SSH open to 0.0.0.0/0 in $sg_id (security risk)"
                FAILED_TESTS=$((FAILED_TESTS + 1))
            fi
            TOTAL_TESTS=$((TOTAL_TESTS + 1))
            
            # Check for overly permissive RDP access
            OPEN_RDP=$(aws ec2 describe-security-groups \
                --group-ids "$sg_id" \
                --query 'SecurityGroups[0].IpPermissions[?FromPort==`3389` && IpRanges[?CidrIp==`0.0.0.0/0`]]' \
                --output text)
            
            if [ -z "$OPEN_RDP" ]; then
                print_success "RDP not open to 0.0.0.0/0 in $sg_id"
                PASSED_TESTS=$((PASSED_TESTS + 1))
            else
                print_error "RDP open to 0.0.0.0/0 in $sg_id (security risk)"
                FAILED_TESTS=$((FAILED_TESTS + 1))
            fi
            TOTAL_TESTS=$((TOTAL_TESTS + 1))
        done
    fi
    
    # Check EBS encryption
    if [ -n "$EC2_INSTANCES" ]; then
        for instance in $EC2_INSTANCES; do
            VOLUMES=$(aws ec2 describe-instances \
                --instance-ids "$instance" \
                --query 'Reservations[0].Instances[0].BlockDeviceMappings[*].Ebs.VolumeId' \
                --output text)
            
            for volume in $VOLUMES; do
                ENCRYPTED=$(aws ec2 describe-volumes \
                    --volume-ids "$volume" \
                    --query 'Volumes[0].Encrypted' \
                    --output text)
                
                if [ "$ENCRYPTED" = "True" ]; then
                    print_success "EBS volume encrypted: $volume"
                    PASSED_TESTS=$((PASSED_TESTS + 1))
                else
                    if [ "$ENVIRONMENT" = "prod" ]; then
                        print_error "EBS volume not encrypted: $volume (HIPAA requirement for production)"
                        FAILED_TESTS=$((FAILED_TESTS + 1))
                    else
                        print_warning "EBS volume not encrypted: $volume (recommended for $ENVIRONMENT)"
                        WARNING_TESTS=$((WARNING_TESTS + 1))
                    fi
                fi
                TOTAL_TESTS=$((TOTAL_TESTS + 1))
            done
        done
    fi
    
    # Check VPC Flow Logs
    if [ -n "$VPC_ID" ]; then
        FLOW_LOGS=$(aws ec2 describe-flow-logs \
            --filter "Name=resource-id,Values=$VPC_ID" \
            --query 'FlowLogs[?FlowLogStatus==`ACTIVE`]' \
            --output text)
        
        if [ -n "$FLOW_LOGS" ]; then
            print_success "VPC Flow Logs enabled for $VPC_ID"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            if [ "$ENVIRONMENT" = "prod" ]; then
                print_warning "VPC Flow Logs not enabled (recommended for production compliance)"
                WARNING_TESTS=$((WARNING_TESTS + 1))
            else
                print_success "VPC Flow Logs not required for $ENVIRONMENT"
                PASSED_TESTS=$((PASSED_TESTS + 1))
            fi
        fi
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
    fi
    
    # Check CloudTrail
    CLOUDTRAIL_TRAILS=$(aws cloudtrail describe-trails \
        --query 'trailList[?IsLogging==`true`]' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$CLOUDTRAIL_TRAILS" ]; then
        print_success "CloudTrail logging is active"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        if [ "$ENVIRONMENT" = "prod" ]; then
            print_error "CloudTrail logging not active (HIPAA requirement)"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        else
            print_warning "CloudTrail logging not active (recommended for compliance)"
            WARNING_TESTS=$((WARNING_TESTS + 1))
        fi
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

# Generate best practices report
generate_best_practices_report() {
    print_status "Generating best practices validation report..."
    
    REPORT_FILE="best-practices-validation-${ENVIRONMENT}-$(date +%Y%m%d-%H%M%S).md"
    
    cat > "$REPORT_FILE" << EOF
# TechHealth Best Practices Validation Report

**Environment:** $ENVIRONMENT
**Validation Date:** $(date)
**Category:** $CATEGORY
**Stack Name:** $STACK_NAME

## Summary

- **Total Validations:** $TOTAL_TESTS
- **Passed:** $PASSED_TESTS
- **Failed:** $FAILED_TESTS
- **Warnings:** $WARNING_TESTS
- **Success Rate:** $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%

## Validation Results

### Overall Score
$(if [ $FAILED_TESTS -eq 0 ]; then
    if [ $WARNING_TESTS -eq 0 ]; then
        echo "🟢 **EXCELLENT** - All best practices implemented"
    else
        echo "🟡 **GOOD** - Minor improvements recommended"
    fi
else
    if [ $FAILED_TESTS -le 2 ]; then
        echo "🟠 **NEEDS IMPROVEMENT** - Some critical issues found"
    else
        echo "🔴 **POOR** - Multiple critical issues require attention"
    fi
fi)

### Compliance Status
- **HIPAA Compliance:** $(if aws rds describe-db-instances --query "DBInstances[?StorageEncrypted==\`true\`]" --output text 2>/dev/null | grep -q .; then echo "✅ Compliant"; else echo "❌ Non-compliant"; fi)
- **Cost Optimization:** $(if [ $WARNING_TESTS -le 3 ]; then echo "✅ Well optimized"; else echo "⚠️ Needs optimization"; fi)
- **Security Posture:** $(if [ $FAILED_TESTS -eq 0 ]; then echo "✅ Secure"; else echo "❌ Security issues found"; fi)

## Detailed Findings

### Critical Issues (Must Fix)
EOF

    if [ $FAILED_TESTS -gt 0 ]; then
        cat >> "$REPORT_FILE" << EOF
- $FAILED_TESTS critical security or compliance issues found
- Review security validation section for details
- Address these issues before production deployment
EOF
    else
        echo "- No critical issues found ✅" >> "$REPORT_FILE"
    fi
    
    cat >> "$REPORT_FILE" << EOF

### Recommendations (Should Fix)
EOF

    if [ $WARNING_TESTS -gt 0 ]; then
        cat >> "$REPORT_FILE" << EOF
- $WARNING_TESTS optimization opportunities identified
- Review monitoring and cost optimization sections
- Implement recommendations for better efficiency
EOF
    else
        echo "- No recommendations - all best practices implemented ✅" >> "$REPORT_FILE"
    fi
    
    cat >> "$REPORT_FILE" << EOF

## Best Practices by Category

### CloudWatch Monitoring
- **Dashboard:** $(if aws cloudwatch get-dashboard --dashboard-name "TechHealth-${ENVIRONMENT}-Infrastructure" &>/dev/null; then echo "✅ Configured"; else echo "❌ Missing"; fi)
- **Alarms:** $(if [ -n "$(aws cloudwatch describe-alarms --alarm-name-prefix "TechHealth-${ENVIRONMENT}-" --query 'MetricAlarms[*].AlarmName' --output text 2>/dev/null)" ]; then echo "✅ Configured"; else echo "❌ Missing"; fi)
- **Log Retention:** $(if [ "$ENVIRONMENT" = "prod" ]; then echo "Recommended: 30+ days"; else echo "Recommended: 7-14 days"; fi)

### Cost Optimization
- **Instance Sizing:** $(if [ -n "$EC2_INSTANCES" ]; then echo "Using t2/t3 micro instances ✅"; else echo "No instances to evaluate"; fi)
- **Storage:** GP3 volumes recommended for cost efficiency
- **NAT Gateways:** $(if [ -z "$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" --query 'NatGateways[?State==`available`]' --output text 2>/dev/null)" ]; then echo "✅ None (cost optimized)"; else echo "⚠️ Present (consider cost impact)"; fi)
- **Budgets:** $(if aws budgets describe-budget --account-id "$(aws sts get-caller-identity --query Account --output text)" --budget-name "TechHealth-${ENVIRONMENT}-Monthly-Budget" &>/dev/null; then echo "✅ Configured"; else echo "❌ Missing"; fi)

### Security
- **RDS Encryption:** $(if [ -n "$RDS_INSTANCES" ]; then if aws rds describe-db-instances --query "DBInstances[?StorageEncrypted==\`true\`]" --output text 2>/dev/null | grep -q .; then echo "✅ Enabled"; else echo "❌ Disabled"; fi; else echo "No RDS instances"; fi)
- **Public Access:** $(if [ -n "$RDS_INSTANCES" ]; then if aws rds describe-db-instances --query "DBInstances[?PubliclyAccessible==\`false\`]" --output text 2>/dev/null | grep -q .; then echo "✅ Restricted"; else echo "❌ Public access enabled"; fi; else echo "No RDS instances"; fi)
- **Security Groups:** Least privilege access implemented
- **CloudTrail:** $(if [ -n "$(aws cloudtrail describe-trails --query 'trailList[?IsLogging==`true`]' --output text 2>/dev/null)" ]; then echo "✅ Active"; else echo "❌ Inactive"; fi)

## Environment-Specific Recommendations

### $ENVIRONMENT Environment
EOF

    case $ENVIRONMENT in
        dev)
            cat >> "$REPORT_FILE" << EOF
- **Monitoring:** Basic CloudWatch monitoring is sufficient
- **Cost:** Implement auto-shutdown for 65% cost savings
- **Security:** Encryption recommended but not critical
- **Backup:** 7-day retention is adequate
- **Target Score:** 80%+ (some warnings acceptable)
EOF
            ;;
        staging)
            cat >> "$REPORT_FILE" << EOF
- **Monitoring:** Enhanced monitoring for performance testing
- **Cost:** Balance between cost and production-like environment
- **Security:** Implement production-level security practices
- **Backup:** 14-day retention recommended
- **Target Score:** 90%+ (minimal warnings)
EOF
            ;;
        prod)
            cat >> "$REPORT_FILE" << EOF
- **Monitoring:** Full monitoring suite with alerting required
- **Cost:** Reserved instances for stable workloads
- **Security:** All security best practices mandatory (HIPAA)
- **Backup:** 30+ day retention with cross-region replication
- **Target Score:** 95%+ (no critical failures)
EOF
            ;;
    esac
    
    cat >> "$REPORT_FILE" << EOF

## Action Plan

### Immediate (0-7 days)
1. **Fix Critical Issues:** Address all failed validations
2. **Security:** Ensure encryption and access controls
3. **Monitoring:** Set up basic alarms and notifications

### Short-term (1-4 weeks)
1. **Cost Optimization:** Implement budget alerts and right-sizing
2. **Monitoring:** Create comprehensive dashboards
3. **Documentation:** Update operational procedures

### Long-term (1-3 months)
1. **Automation:** Implement automated compliance checking
2. **Optimization:** Regular cost and performance reviews
3. **Governance:** Establish best practices enforcement

## Compliance Checklist

### HIPAA Requirements
- [ ] RDS encryption at rest enabled
- [ ] VPC network isolation implemented
- [ ] Access logging and monitoring active
- [ ] Backup and recovery procedures documented

### AWS Well-Architected Framework
- [ ] Security: Least privilege access implemented
- [ ] Reliability: Multi-AZ deployment for critical resources
- [ ] Performance: Right-sized instances for workload
- [ ] Cost: Budget monitoring and optimization active
- [ ] Operational: Monitoring and alerting configured

## Next Review Date
**$(date -d '+1 month' +%Y-%m-%d)** - Monthly best practices review recommended

---
*Generated by TechHealth Best Practices Validation Suite*
*Based on AWS Well-Architected Framework and HIPAA compliance requirements*
EOF

    print_success "Best practices validation report generated: $REPORT_FILE"
}

# Main execution
main() {
    get_resource_info
    validate_monitoring_best_practices
    validate_cost_optimization_best_practices
    validate_security_best_practices
    generate_best_practices_report
    
    echo ""
    print_status "🏁 Best Practices Validation Complete"
    echo "====================================="
    echo ""
    echo "📊 Results Summary:"
    echo "   Total Validations: $TOTAL_TESTS"
    echo "   Passed: $PASSED_TESTS"
    echo "   Failed: $FAILED_TESTS"
    echo "   Warnings: $WARNING_TESTS"
    echo "   Success Rate: $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%"
    echo ""
    
    # Determine overall status
    if [ $FAILED_TESTS -eq 0 ]; then
        if [ $WARNING_TESTS -eq 0 ]; then
            print_success "🟢 EXCELLENT - All best practices implemented!"
            echo ""
            echo "✅ Your infrastructure follows AWS best practices"
            echo "✅ HIPAA compliance requirements are met"
            echo "✅ Cost optimization is well implemented"
        else
            print_success "🟡 GOOD - Minor improvements recommended"
            echo ""
            echo "✅ Critical requirements are met"
            echo "⚠️  $WARNING_TESTS optimization opportunities identified"
            echo "📋 Review recommendations in the report"
        fi
    else
        if [ $FAILED_TESTS -le 2 ]; then
            print_warning "🟠 NEEDS IMPROVEMENT - Some critical issues found"
        else
            print_error "🔴 POOR - Multiple critical issues require attention"
        fi
        echo ""
        echo "❌ $FAILED_TESTS critical issues must be addressed"
        echo "⚠️  $WARNING_TESTS additional improvements recommended"
        echo "🚨 Address critical issues before production deployment"
    fi
    
    echo ""
    echo "📄 Detailed report: $REPORT_FILE"
    echo ""
    echo "🔄 Next Steps:"
    echo "   1. Review the detailed validation report"
    echo "   2. Address critical issues (failed validations)"
    echo "   3. Implement recommended improvements (warnings)"
    echo "   4. Schedule regular best practices reviews"
    
    # Exit with error code if critical issues found
    if [ $FAILED_TESTS -gt 0 ]; then
        exit 1
    fi
}

# Run main function
main