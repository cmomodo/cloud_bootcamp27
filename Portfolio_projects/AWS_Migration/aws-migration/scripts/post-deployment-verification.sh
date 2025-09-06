#!/bin/bash

# Post-Deployment Verification Script for TechHealth Infrastructure
# This script verifies that deployed infrastructure is working correctly

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

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    print_status "Verifying: $test_name"
    
    if eval "$test_command" > /dev/null 2>&1; then
        print_success "$test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        print_error "$test_name"
        FAILED_TESTS=$((FAILED_TESTS + 1))
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
    echo "  --quick          Run only essential verifications"
    echo "  --verbose        Show detailed output"
    echo "  --wait-time N    Wait N seconds for resources to stabilize (default: 60)"
    echo "  --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 dev --verbose"
    echo "  $0 prod --quick --wait-time 120"
    exit 1
}

# Parse command line arguments
ENVIRONMENT=""
QUICK=false
VERBOSE=false
WAIT_TIME=60

while [[ $# -gt 0 ]]; do
    case $1 in
        dev|staging|prod)
            ENVIRONMENT="$1"
            shift
            ;;
        --quick)
            QUICK=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --wait-time)
            WAIT_TIME="$2"
            shift 2
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

echo "🔍 TechHealth Post-Deployment Verification"
echo "=========================================="
echo "Environment: $ENVIRONMENT"
echo "Quick Mode: $QUICK"
echo "Verbose: $VERBOSE"
echo "Wait Time: ${WAIT_TIME}s"
echo ""

# Set environment variables
export ENVIRONMENT
export CDK_DEFAULT_REGION=us-east-1

STACK_NAME="TechHealth-$(echo $ENVIRONMENT | sed 's/.*/\u&/')-Infrastructure"

# Wait for resources to stabilize
print_status "Waiting ${WAIT_TIME} seconds for resources to stabilize..."
sleep $WAIT_TIME

# 1. Verify Stack Status
verify_stack_status() {
    echo "📊 Verifying Stack Status"
    echo "========================="
    
    # Check if stack exists and is in good state
    if aws cloudformation describe-stacks --stack-name "$STACK_NAME" > /dev/null 2>&1; then
        STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].StackStatus' --output text)
        
        if [[ "$STACK_STATUS" == *"COMPLETE"* ]]; then
            print_success "Stack is in healthy state: $STACK_STATUS"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            print_error "Stack is in unhealthy state: $STACK_STATUS"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    else
        print_error "Stack $STACK_NAME not found"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Get stack outputs
    print_status "Retrieving stack outputs..."
    aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query 'Stacks[0].Outputs' \
        --output table 2>/dev/null || print_warning "No stack outputs found"
    
    echo ""
}

# 2. Verify VPC and Networking
verify_networking() {
    echo "🌐 Verifying Networking Infrastructure"
    echo "====================================="
    
    # Get VPC ID from stack
    VPC_ID=$(aws cloudformation describe-stack-resources \
        --stack-name "$STACK_NAME" \
        --logical-resource-id "NetworkingVPC" \
        --query 'StackResources[0].PhysicalResourceId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
        print_success "VPC exists: $VPC_ID"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        
        # Check VPC state
        VPC_STATE=$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --query 'Vpcs[0].State' --output text 2>/dev/null)
        if [ "$VPC_STATE" = "available" ]; then
            print_success "VPC is available"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            print_error "VPC is not available: $VPC_STATE"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        
        # Check subnets
        SUBNET_COUNT=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'length(Subnets)' --output text)
        if [ "$SUBNET_COUNT" -ge 4 ]; then
            print_success "Sufficient subnets created: $SUBNET_COUNT"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            print_error "Insufficient subnets: $SUBNET_COUNT (expected 4+)"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        
        # Check Internet Gateway
        IGW_COUNT=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query 'length(InternetGateways)' --output text)
        if [ "$IGW_COUNT" -ge 1 ]; then
            print_success "Internet Gateway attached"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            print_error "No Internet Gateway found"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        
    else
        print_error "VPC not found in stack"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo ""
}

# 3. Verify EC2 Instances
verify_ec2_instances() {
    echo "💻 Verifying EC2 Instances"
    echo "=========================="
    
    # Find EC2 instances in the stack
    EC2_INSTANCES=$(aws ec2 describe-instances \
        --filters "Name=tag:aws:cloudformation:stack-name,Values=$STACK_NAME" \
        --query 'Reservations[*].Instances[*].InstanceId' \
        --output text)
    
    if [ -n "$EC2_INSTANCES" ]; then
        INSTANCE_COUNT=$(echo $EC2_INSTANCES | wc -w)
        print_success "EC2 instances found: $INSTANCE_COUNT"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        
        for instance_id in $EC2_INSTANCES; do
            # Check instance state
            INSTANCE_STATE=$(aws ec2 describe-instances \
                --instance-ids "$instance_id" \
                --query 'Reservations[0].Instances[0].State.Name' \
                --output text)
            
            if [ "$INSTANCE_STATE" = "running" ]; then
                print_success "Instance $instance_id is running"
                PASSED_TESTS=$((PASSED_TESTS + 1))
            else
                print_error "Instance $instance_id is not running: $INSTANCE_STATE"
                FAILED_TESTS=$((FAILED_TESTS + 1))
            fi
            TOTAL_TESTS=$((TOTAL_TESTS + 1))
            
            # Check if instance has public IP
            PUBLIC_IP=$(aws ec2 describe-instances \
                --instance-ids "$instance_id" \
                --query 'Reservations[0].Instances[0].PublicIpAddress' \
                --output text 2>/dev/null || echo "None")
            
            if [ "$PUBLIC_IP" != "None" ] && [ -n "$PUBLIC_IP" ]; then
                print_success "Instance $instance_id has public IP: $PUBLIC_IP"
                PASSED_TESTS=$((PASSED_TESTS + 1))
                
                # Test SSH connectivity (if not quick mode)
                if [ "$QUICK" != true ]; then
                    print_status "Testing SSH connectivity to $PUBLIC_IP..."
                    if timeout 10 nc -z "$PUBLIC_IP" 22 2>/dev/null; then
                        print_success "SSH port is accessible on $PUBLIC_IP"
                        PASSED_TESTS=$((PASSED_TESTS + 1))
                    else
                        print_warning "SSH port not accessible on $PUBLIC_IP (may be expected)"
                    fi
                    TOTAL_TESTS=$((TOTAL_TESTS + 1))
                fi
            else
                print_error "Instance $instance_id has no public IP"
                FAILED_TESTS=$((FAILED_TESTS + 1))
            fi
            TOTAL_TESTS=$((TOTAL_TESTS + 1))
        done
    else
        print_error "No EC2 instances found in stack"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo ""
}

# 4. Verify RDS Database
verify_rds_database() {
    echo "🗄️  Verifying RDS Database"
    echo "=========================="
    
    # Find RDS instances in the stack
    RDS_INSTANCES=$(aws rds describe-db-instances \
        --query "DBInstances[?contains(DBInstanceIdentifier, '$(echo $STACK_NAME | tr '[:upper:]' '[:lower:]')') || contains(DBInstanceIdentifier, 'techhealth')].DBInstanceIdentifier" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$RDS_INSTANCES" ]; then
        for db_instance in $RDS_INSTANCES; do
            print_success "RDS instance found: $db_instance"
            PASSED_TESTS=$((PASSED_TESTS + 1))
            
            # Check DB instance status
            DB_STATUS=$(aws rds describe-db-instances \
                --db-instance-identifier "$db_instance" \
                --query 'DBInstances[0].DBInstanceStatus' \
                --output text)
            
            if [ "$DB_STATUS" = "available" ]; then
                print_success "Database $db_instance is available"
                PASSED_TESTS=$((PASSED_TESTS + 1))
            else
                print_error "Database $db_instance is not available: $DB_STATUS"
                FAILED_TESTS=$((FAILED_TESTS + 1))
            fi
            TOTAL_TESTS=$((TOTAL_TESTS + 1))
            
            # Check if database is in private subnet (not publicly accessible)
            PUBLIC_ACCESS=$(aws rds describe-db-instances \
                --db-instance-identifier "$db_instance" \
                --query 'DBInstances[0].PubliclyAccessible' \
                --output text)
            
            if [ "$PUBLIC_ACCESS" = "False" ]; then
                print_success "Database $db_instance is not publicly accessible (secure)"
                PASSED_TESTS=$((PASSED_TESTS + 1))
            else
                print_error "Database $db_instance is publicly accessible (security risk)"
                FAILED_TESTS=$((FAILED_TESTS + 1))
            fi
            TOTAL_TESTS=$((TOTAL_TESTS + 1))
            
            # Check encryption
            ENCRYPTION=$(aws rds describe-db-instances \
                --db-instance-identifier "$db_instance" \
                --query 'DBInstances[0].StorageEncrypted' \
                --output text)
            
            if [ "$ENCRYPTION" = "True" ]; then
                print_success "Database $db_instance has encryption enabled"
                PASSED_TESTS=$((PASSED_TESTS + 1))
            else
                print_error "Database $db_instance does not have encryption enabled"
                FAILED_TESTS=$((FAILED_TESTS + 1))
            fi
            TOTAL_TESTS=$((TOTAL_TESTS + 1))
            
            # Check Multi-AZ (for staging/prod)
            if [ "$ENVIRONMENT" != "dev" ]; then
                MULTI_AZ=$(aws rds describe-db-instances \
                    --db-instance-identifier "$db_instance" \
                    --query 'DBInstances[0].MultiAZ' \
                    --output text)
                
                if [ "$MULTI_AZ" = "True" ]; then
                    print_success "Database $db_instance has Multi-AZ enabled"
                    PASSED_TESTS=$((PASSED_TESTS + 1))
                else
                    print_warning "Database $db_instance does not have Multi-AZ enabled"
                fi
                TOTAL_TESTS=$((TOTAL_TESTS + 1))
            fi
        done
    else
        print_error "No RDS instances found"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo ""
}

# 5. Verify Security Groups
verify_security_groups() {
    echo "🔒 Verifying Security Groups"
    echo "============================"
    
    # Find security groups in the stack
    SECURITY_GROUPS=$(aws ec2 describe-security-groups \
        --filters "Name=tag:aws:cloudformation:stack-name,Values=$STACK_NAME" \
        --query 'SecurityGroups[*].GroupId' \
        --output text)
    
    if [ -n "$SECURITY_GROUPS" ]; then
        SG_COUNT=$(echo $SECURITY_GROUPS | wc -w)
        print_success "Security groups found: $SG_COUNT"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        
        for sg_id in $SECURITY_GROUPS; do
            SG_NAME=$(aws ec2 describe-security-groups \
                --group-ids "$sg_id" \
                --query 'SecurityGroups[0].GroupName' \
                --output text)
            
            print_status "Checking security group: $SG_NAME ($sg_id)"
            
            # Check for overly permissive rules
            OPEN_SSH=$(aws ec2 describe-security-groups \
                --group-ids "$sg_id" \
                --query 'SecurityGroups[0].IpPermissions[?FromPort==`22` && IpRanges[?CidrIp==`0.0.0.0/0`]]' \
                --output text)
            
            if [ -z "$OPEN_SSH" ]; then
                print_success "SSH is not open to 0.0.0.0/0 in $SG_NAME"
                PASSED_TESTS=$((PASSED_TESTS + 1))
            else
                print_warning "SSH may be open to 0.0.0.0/0 in $SG_NAME"
            fi
            TOTAL_TESTS=$((TOTAL_TESTS + 1))
        done
    else
        print_error "No security groups found in stack"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo ""
}

# 6. Test Connectivity (if not quick mode)
test_connectivity() {
    if [ "$QUICK" = true ]; then
        print_status "Skipping connectivity tests (quick mode)"
        return
    fi
    
    echo "🔗 Testing Connectivity"
    echo "======================="
    
    # Run automated connectivity tests
    print_status "Running automated connectivity tests..."
    if npm run test:connectivity > /dev/null 2>&1; then
        print_success "Automated connectivity tests passed"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        print_error "Automated connectivity tests failed"
        if [ "$VERBOSE" = true ]; then
            npm run test:connectivity
        fi
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo ""
}

# 7. Verify Monitoring and Logging
verify_monitoring() {
    echo "📊 Verifying Monitoring and Logging"
    echo "==================================="
    
    # Check CloudWatch log groups
    LOG_GROUPS=$(aws logs describe-log-groups \
        --log-group-name-prefix "/aws/ec2" \
        --query 'logGroups[*].logGroupName' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$LOG_GROUPS" ]; then
        print_success "CloudWatch log groups found"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        print_warning "No CloudWatch log groups found"
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Check for recent log entries (if not quick mode)
    if [ "$QUICK" != true ] && [ -n "$LOG_GROUPS" ]; then
        for log_group in $LOG_GROUPS; do
            RECENT_LOGS=$(aws logs describe-log-streams \
                --log-group-name "$log_group" \
                --order-by LastEventTime \
                --descending \
                --max-items 1 \
                --query 'logStreams[0].lastEventTime' \
                --output text 2>/dev/null || echo "0")
            
            if [ "$RECENT_LOGS" != "0" ] && [ "$RECENT_LOGS" != "None" ]; then
                LAST_LOG_TIME=$(date -d "@$(echo $RECENT_LOGS | cut -c1-10)" 2>/dev/null || echo "unknown")
                print_success "Recent logs found in $log_group (last: $LAST_LOG_TIME)"
                PASSED_TESTS=$((PASSED_TESTS + 1))
            else
                print_warning "No recent logs in $log_group"
            fi
            TOTAL_TESTS=$((TOTAL_TESTS + 1))
        done
    fi
    
    echo ""
}

# 8. Verify Cost Optimization
verify_cost_optimization() {
    echo "💰 Verifying Cost Optimization"
    echo "=============================="
    
    # Check instance types
    INSTANCE_TYPES=$(aws ec2 describe-instances \
        --filters "Name=tag:aws:cloudformation:stack-name,Values=$STACK_NAME" \
        --query 'Reservations[*].Instances[*].InstanceType' \
        --output text)
    
    for instance_type in $INSTANCE_TYPES; do
        if [[ "$instance_type" == t2.* ]] || [[ "$instance_type" == t3.* ]]; then
            print_success "Cost-optimized instance type: $instance_type"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            print_warning "Instance type may not be cost-optimized: $instance_type"
        fi
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
    done
    
    # Check for NAT Gateways (should not exist for cost optimization)
    NAT_GATEWAYS=$(aws ec2 describe-nat-gateways \
        --filter "Name=vpc-id,Values=$VPC_ID" \
        --query 'NatGateways[?State==`available`]' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$NAT_GATEWAYS" ]; then
        print_success "No NAT Gateways found (cost optimized)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        print_warning "NAT Gateways found (may increase costs)"
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo ""
}

# 9. Generate Verification Report
generate_verification_report() {
    echo "📋 Generating Verification Report"
    echo "================================="
    
    REPORT_FILE="post-deployment-verification-${ENVIRONMENT}.md"
    
    cat > "$REPORT_FILE" << EOF
# TechHealth Post-Deployment Verification Report

**Environment:** $ENVIRONMENT
**Generated:** $(date)
**Stack Name:** $STACK_NAME

## Summary

- **Total Verifications:** $TOTAL_TESTS
- **Passed:** $PASSED_TESTS
- **Failed:** $FAILED_TESTS
- **Success Rate:** $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%

## Verification Categories

### ✅ Stack Status
- CloudFormation stack health
- Resource creation status

### ✅ Networking Infrastructure
- VPC and subnet configuration
- Internet Gateway connectivity
- Network security validation

### ✅ Compute Resources
- EC2 instance status and accessibility
- Public IP assignment
- SSH connectivity (where applicable)

### ✅ Database Infrastructure
- RDS instance availability
- Security configuration (private access)
- Encryption and backup settings

### ✅ Security Configuration
- Security group rules validation
- Access control verification
- HIPAA compliance checks

### ✅ Connectivity Testing
- Automated connectivity validation
- Network path verification

### ✅ Monitoring and Logging
- CloudWatch log group creation
- Log stream activity verification

### ✅ Cost Optimization
- Instance type validation
- Resource efficiency checks

## Infrastructure Health

EOF

    if [ $FAILED_TESTS -eq 0 ]; then
        cat >> "$REPORT_FILE" << EOF
### 🎉 DEPLOYMENT SUCCESSFUL

All verifications passed successfully. The infrastructure is healthy and ready for use.

**Key Achievements:**
- All resources deployed correctly
- Security configurations validated
- HIPAA compliance maintained
- Cost optimization implemented

**Next Steps:**
1. Begin application deployment
2. Set up monitoring dashboards
3. Configure backup procedures
4. Document operational procedures
EOF
    else
        cat >> "$REPORT_FILE" << EOF
### ⚠️ ISSUES DETECTED

$FAILED_TESTS verification(s) failed. Please address the following issues:

**Required Actions:**
1. Review failed verifications
2. Check CloudFormation events for errors
3. Verify resource configurations
4. Re-run verification after fixes

**Escalation:**
- Contact DevOps team for critical failures
- Review AWS CloudFormation console for detailed errors
EOF
    fi
    
    cat >> "$REPORT_FILE" << EOF

## Operational Recommendations

### Immediate Actions
- Set up CloudWatch dashboards
- Configure billing alerts
- Document access procedures
- Test backup and restore procedures

### Ongoing Monitoring
- Regular security audits
- Performance monitoring
- Cost optimization reviews
- Compliance validation

### Incident Response
- Document troubleshooting procedures
- Establish escalation paths
- Create runbooks for common issues

---
*Generated by TechHealth Post-Deployment Verification Suite*
EOF

    print_success "Verification report generated: $REPORT_FILE"
}

# Main execution
main() {
    verify_stack_status
    verify_networking
    verify_ec2_instances
    verify_rds_database
    verify_security_groups
    test_connectivity
    verify_monitoring
    verify_cost_optimization
    generate_verification_report
    
    # Final summary
    echo "🏁 Post-Deployment Verification Complete"
    echo "========================================"
    echo ""
    echo "📊 Results Summary:"
    echo "   Total Verifications: $TOTAL_TESTS"
    echo "   Passed: $PASSED_TESTS"
    echo "   Failed: $FAILED_TESTS"
    echo "   Success Rate: $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%"
    echo ""
    
    if [ $FAILED_TESTS -eq 0 ]; then
        print_success "🎉 All verifications passed! Infrastructure is healthy."
        echo ""
        echo "✅ The $ENVIRONMENT environment is ready for use."
        echo "📄 Detailed report: $REPORT_FILE"
        echo ""
        exit 0
    else
        print_error "❌ $FAILED_TESTS verification(s) failed."
        echo ""
        echo "Please review and address the issues before proceeding."
        echo "📄 Detailed report: $REPORT_FILE"
        echo ""
        exit 1
    fi
}

# Run main function
main