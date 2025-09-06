#!/bin/bash

# Resource Cleanup Script for TechHealth Infrastructure
# This script safely cleans up test environment resources to avoid ongoing charges

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

# Function to display usage
usage() {
    echo "Usage: $0 <environment> [options]"
    echo ""
    echo "Environments:"
    echo "  dev       - Development environment (safe to cleanup)"
    echo "  staging   - Staging environment (requires confirmation)"
    echo "  prod      - Production environment (BLOCKED for safety)"
    echo ""
    echo "Options:"
    echo "  --dry-run        Show what would be deleted without actually deleting"
    echo "  --force          Skip confirmation prompts (dev only)"
    echo "  --keep-data      Preserve RDS snapshots and S3 data"
    echo "  --cleanup-all    Also cleanup CloudWatch logs, alarms, and budgets"
    echo "  --verbose        Show detailed output"
    echo "  --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 dev --dry-run"
    echo "  $0 dev --force --cleanup-all"
    echo "  $0 staging --keep-data"
    exit 1
}

# Parse command line arguments
ENVIRONMENT=""
DRY_RUN=false
FORCE=false
KEEP_DATA=false
CLEANUP_ALL=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        dev|staging|prod)
            ENVIRONMENT="$1"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --keep-data)
            KEEP_DATA=true
            shift
            ;;
        --cleanup-all)
            CLEANUP_ALL=true
            shift
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

# Block production cleanup for safety
if [ "$ENVIRONMENT" = "prod" ]; then
    print_error "🚨 PRODUCTION CLEANUP IS BLOCKED FOR SAFETY"
    echo ""
    echo "Production resources should never be automatically cleaned up."
    echo "If you need to remove production resources:"
    echo "  1. Use the AWS Console with proper approvals"
    echo "  2. Follow your organization's change management process"
    echo "  3. Ensure proper backups and stakeholder notification"
    echo ""
    exit 1
fi

# Set environment variables
export ENVIRONMENT
export CDK_DEFAULT_REGION=us-east-1

echo "🧹 TechHealth Resource Cleanup"
echo "=============================="
echo "Environment: $ENVIRONMENT"
echo "Dry Run: $DRY_RUN"
echo "Keep Data: $KEEP_DATA"
echo "Cleanup All: $CLEANUP_ALL"
echo ""

STACK_NAME="TechHealth-$(echo $ENVIRONMENT | sed 's/.*/\u&/')-Infrastructure"

# Safety confirmation for staging
if [ "$ENVIRONMENT" = "staging" ] && [ "$FORCE" != true ]; then
    print_warning "⚠️  STAGING ENVIRONMENT CLEANUP"
    echo ""
    echo "This will remove staging infrastructure which may impact:"
    echo "  - Integration testing"
    echo "  - QA validation"
    echo "  - Performance testing"
    echo ""
    read -p "Are you sure you want to cleanup staging resources? (type 'CLEANUP STAGING' to confirm): " confirm
    if [ "$confirm" != "CLEANUP STAGING" ]; then
        print_error "Staging cleanup cancelled."
        exit 1
    fi
fi

# Development environment confirmation
if [ "$ENVIRONMENT" = "dev" ] && [ "$FORCE" != true ]; then
    echo ""
    read -p "Cleanup development environment resources? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        print_error "Development cleanup cancelled."
        exit 1
    fi
fi

# Check if stack exists
print_status "Checking if stack exists..."
if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" &>/dev/null; then
    print_warning "Stack $STACK_NAME does not exist"
    STACK_EXISTS=false
else
    print_success "Stack $STACK_NAME found"
    STACK_EXISTS=true
fi

# Get resource information before cleanup
get_resource_info() {
    if [ "$STACK_EXISTS" = false ]; then
        return 0
    fi
    
    print_status "Gathering resource information..."
    
    # Get EC2 instances
    EC2_INSTANCES=$(aws ec2 describe-instances \
        --filters "Name=tag:aws:cloudformation:stack-name,Values=$STACK_NAME" \
        --query 'Reservations[*].Instances[*].InstanceId' \
        --output text 2>/dev/null || echo "")
    
    # Get RDS instances
    RDS_INSTANCES=$(aws rds describe-db-instances \
        --query "DBInstances[?contains(DBInstanceIdentifier, '$(echo $STACK_NAME | tr '[:upper:]' '[:lower:]')') || contains(DBInstanceIdentifier, 'techhealth')].DBInstanceIdentifier" \
        --output text 2>/dev/null || echo "")
    
    # Get VPC ID
    VPC_ID=$(aws cloudformation describe-stack-resources \
        --stack-name "$STACK_NAME" \
        --query 'StackResources[?ResourceType==`AWS::EC2::VPC`].PhysicalResourceId' \
        --output text 2>/dev/null || echo "")
    
    # Get Security Groups
    SECURITY_GROUPS=$(aws ec2 describe-security-groups \
        --filters "Name=tag:aws:cloudformation:stack-name,Values=$STACK_NAME" \
        --query 'SecurityGroups[*].GroupId' \
        --output text 2>/dev/null || echo "")
    
    echo ""
    echo "📋 Resources to be cleaned up:"
    echo "   Stack: $STACK_NAME"
    echo "   VPC: ${VPC_ID:-Not found}"
    echo "   EC2 Instances: ${EC2_INSTANCES:-None}"
    echo "   RDS Instances: ${RDS_INSTANCES:-None}"
    echo "   Security Groups: $(echo $SECURITY_GROUPS | wc -w) groups"
    echo ""
}

# Create RDS snapshots before cleanup
create_rds_snapshots() {
    if [ -z "$RDS_INSTANCES" ] || [ "$KEEP_DATA" != true ]; then
        return 0
    fi
    
    print_status "Creating RDS snapshots before cleanup..."
    
    for rds_instance in $RDS_INSTANCES; do
        SNAPSHOT_ID="${rds_instance}-final-snapshot-$(date +%Y%m%d-%H%M%S)"
        
        if [ "$DRY_RUN" = true ]; then
            print_status "[DRY RUN] Would create snapshot: $SNAPSHOT_ID"
        else
            print_status "Creating snapshot: $SNAPSHOT_ID"
            if aws rds create-db-snapshot \
                --db-instance-identifier "$rds_instance" \
                --db-snapshot-identifier "$SNAPSHOT_ID" > /dev/null; then
                print_success "Snapshot created: $SNAPSHOT_ID"
            else
                print_error "Failed to create snapshot for $rds_instance"
            fi
        fi
    done
}

# Stop EC2 instances before stack deletion
stop_ec2_instances() {
    if [ -z "$EC2_INSTANCES" ]; then
        return 0
    fi
    
    print_status "Stopping EC2 instances..."
    
    for instance in $EC2_INSTANCES; do
        INSTANCE_STATE=$(aws ec2 describe-instances \
            --instance-ids "$instance" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text 2>/dev/null || echo "unknown")
        
        if [ "$INSTANCE_STATE" = "running" ]; then
            if [ "$DRY_RUN" = true ]; then
                print_status "[DRY RUN] Would stop instance: $instance"
            else
                print_status "Stopping instance: $instance"
                aws ec2 stop-instances --instance-ids "$instance" > /dev/null
                print_success "Instance $instance stopped"
            fi
        else
            print_status "Instance $instance is already $INSTANCE_STATE"
        fi
    done
    
    if [ "$DRY_RUN" != true ] && [ -n "$EC2_INSTANCES" ]; then
        print_status "Waiting for instances to stop..."
        aws ec2 wait instance-stopped --instance-ids $EC2_INSTANCES || print_warning "Timeout waiting for instances to stop"
    fi
}

# Delete CloudFormation stack
delete_stack() {
    if [ "$STACK_EXISTS" = false ]; then
        print_status "No stack to delete"
        return 0
    fi
    
    print_status "Deleting CloudFormation stack..."
    
    if [ "$DRY_RUN" = true ]; then
        print_status "[DRY RUN] Would delete stack: $STACK_NAME"
        return 0
    fi
    
    # Delete the stack
    if aws cloudformation delete-stack --stack-name "$STACK_NAME"; then
        print_success "Stack deletion initiated: $STACK_NAME"
        
        print_status "Waiting for stack deletion to complete..."
        if aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME"; then
            print_success "Stack deleted successfully: $STACK_NAME"
        else
            print_error "Stack deletion failed or timed out"
            
            # Show recent events
            print_status "Recent CloudFormation events:"
            aws cloudformation describe-stack-events \
                --stack-name "$STACK_NAME" \
                --max-items 10 \
                --query 'StackEvents[*].[Timestamp,ResourceStatus,ResourceType,LogicalResourceId,ResourceStatusReason]' \
                --output table 2>/dev/null || print_warning "Could not retrieve stack events"
            
            return 1
        fi
    else
        print_error "Failed to initiate stack deletion"
        return 1
    fi
}

# Cleanup CloudWatch resources
cleanup_cloudwatch() {
    if [ "$CLEANUP_ALL" != true ]; then
        return 0
    fi
    
    print_status "Cleaning up CloudWatch resources..."
    
    # Delete dashboard
    DASHBOARD_NAME="TechHealth-${ENVIRONMENT}-Infrastructure"
    if [ "$DRY_RUN" = true ]; then
        print_status "[DRY RUN] Would delete dashboard: $DASHBOARD_NAME"
    else
        if aws cloudwatch delete-dashboards --dashboard-names "$DASHBOARD_NAME" > /dev/null 2>&1; then
            print_success "Deleted dashboard: $DASHBOARD_NAME"
        else
            print_warning "Dashboard not found or already deleted: $DASHBOARD_NAME"
        fi
    fi
    
    # Delete alarms
    ALARMS=$(aws cloudwatch describe-alarms \
        --alarm-name-prefix "TechHealth-${ENVIRONMENT}-" \
        --query 'MetricAlarms[*].AlarmName' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$ALARMS" ]; then
        if [ "$DRY_RUN" = true ]; then
            echo "$ALARMS" | tr '\t' '\n' | while read alarm; do
                print_status "[DRY RUN] Would delete alarm: $alarm"
            done
        else
            print_status "Deleting CloudWatch alarms..."
            aws cloudwatch delete-alarms --alarm-names $ALARMS
            print_success "Deleted $(echo $ALARMS | wc -w) alarms"
        fi
    fi
    
    # Delete log groups (be careful with this)
    LOG_GROUPS=$(aws logs describe-log-groups \
        --log-group-name-prefix "/aws/ec2" \
        --query 'logGroups[*].logGroupName' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$LOG_GROUPS" ] && [ "$ENVIRONMENT" = "dev" ]; then
        if [ "$DRY_RUN" = true ]; then
            echo "$LOG_GROUPS" | tr '\t' '\n' | while read log_group; do
                print_status "[DRY RUN] Would delete log group: $log_group"
            done
        else
            print_warning "Deleting log groups (development only)..."
            echo "$LOG_GROUPS" | tr '\t' '\n' | while read log_group; do
                aws logs delete-log-group --log-group-name "$log_group" 2>/dev/null || true
            done
            print_success "Deleted development log groups"
        fi
    fi
}

# Cleanup budgets
cleanup_budgets() {
    if [ "$CLEANUP_ALL" != true ]; then
        return 0
    fi
    
    print_status "Cleaning up AWS Budgets..."
    
    BUDGET_NAME="TechHealth-${ENVIRONMENT}-Monthly-Budget"
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    if [ "$DRY_RUN" = true ]; then
        print_status "[DRY RUN] Would delete budget: $BUDGET_NAME"
    else
        if aws budgets delete-budget \
            --account-id "$ACCOUNT_ID" \
            --budget-name "$BUDGET_NAME" > /dev/null 2>&1; then
            print_success "Deleted budget: $BUDGET_NAME"
        else
            print_warning "Budget not found or already deleted: $BUDGET_NAME"
        fi
    fi
}

# Cleanup SNS topics
cleanup_sns() {
    if [ "$CLEANUP_ALL" != true ]; then
        return 0
    fi
    
    print_status "Cleaning up SNS topics..."
    
    TOPIC_NAME="techhealth-${ENVIRONMENT}-alerts"
    TOPIC_ARN="arn:aws:sns:${CDK_DEFAULT_REGION}:$(aws sts get-caller-identity --query Account --output text):${TOPIC_NAME}"
    
    if [ "$DRY_RUN" = true ]; then
        print_status "[DRY RUN] Would delete SNS topic: $TOPIC_NAME"
    else
        if aws sns delete-topic --topic-arn "$TOPIC_ARN" > /dev/null 2>&1; then
            print_success "Deleted SNS topic: $TOPIC_NAME"
        else
            print_warning "SNS topic not found or already deleted: $TOPIC_NAME"
        fi
    fi
}

# Verify cleanup completion
verify_cleanup() {
    print_status "Verifying cleanup completion..."
    
    # Check if stack still exists
    if aws cloudformation describe-stacks --stack-name "$STACK_NAME" &>/dev/null; then
        print_error "Stack still exists: $STACK_NAME"
        return 1
    else
        print_success "Stack successfully deleted: $STACK_NAME"
    fi
    
    # Check for remaining EC2 instances
    REMAINING_EC2=$(aws ec2 describe-instances \
        --filters "Name=tag:aws:cloudformation:stack-name,Values=$STACK_NAME" \
        --query 'Reservations[*].Instances[*].InstanceId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$REMAINING_EC2" ]; then
        print_warning "Some EC2 instances may still exist: $REMAINING_EC2"
    else
        print_success "No remaining EC2 instances found"
    fi
    
    # Check for remaining RDS instances
    REMAINING_RDS=$(aws rds describe-db-instances \
        --query "DBInstances[?contains(DBInstanceIdentifier, '$(echo $STACK_NAME | tr '[:upper:]' '[:lower:]')') || contains(DBInstanceIdentifier, 'techhealth')].DBInstanceIdentifier" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$REMAINING_RDS" ]; then
        print_warning "Some RDS instances may still exist: $REMAINING_RDS"
    else
        print_success "No remaining RDS instances found"
    fi
}

# Generate cleanup report
generate_cleanup_report() {
    print_status "Generating cleanup report..."
    
    REPORT_FILE="cleanup-report-${ENVIRONMENT}-$(date +%Y%m%d-%H%M%S).md"
    
    cat > "$REPORT_FILE" << EOF
# TechHealth Resource Cleanup Report

**Environment:** $ENVIRONMENT
**Cleanup Date:** $(date)
**Dry Run:** $DRY_RUN
**Keep Data:** $KEEP_DATA
**Cleanup All:** $CLEANUP_ALL

## Resources Cleaned Up

### CloudFormation Stack
- **Stack Name:** $STACK_NAME
- **Status:** $(if [ "$DRY_RUN" = true ]; then echo "Would be deleted"; else echo "Deleted"; fi)

### Infrastructure Resources
- **EC2 Instances:** ${EC2_INSTANCES:-None}
- **RDS Instances:** ${RDS_INSTANCES:-None}
- **VPC:** ${VPC_ID:-None}
- **Security Groups:** $(echo $SECURITY_GROUPS | wc -w) groups

### Monitoring Resources
$(if [ "$CLEANUP_ALL" = true ]; then
cat << 'MONEOF'
- **CloudWatch Dashboard:** TechHealth-ENVIRONMENT-Infrastructure
- **CloudWatch Alarms:** All TechHealth-ENVIRONMENT-* alarms
- **SNS Topic:** techhealth-ENVIRONMENT-alerts
- **Budget:** TechHealth-ENVIRONMENT-Monthly-Budget
MONEOF
else
echo "- **Monitoring Resources:** Preserved (use --cleanup-all to remove)"
fi)

### Data Preservation
$(if [ "$KEEP_DATA" = true ]; then
echo "- **RDS Snapshots:** Created before cleanup"
echo "- **Data Status:** Preserved for recovery"
else
echo "- **RDS Snapshots:** Not created"
echo "- **Data Status:** Deleted with resources"
fi)

## Cost Impact

### Immediate Savings
- **EC2 Instances:** Stopped/terminated - no ongoing compute charges
- **RDS Instances:** Deleted - no ongoing database charges
- **Storage:** $(if [ "$KEEP_DATA" = true ]; then echo "Snapshot storage charges apply"; else echo "All storage deleted"; fi)
- **Network:** No ongoing data transfer charges

### Estimated Monthly Savings
- **Development:** ~\$30-50/month
- **Staging:** ~\$75-125/month

## Recovery Instructions

### To Restore Environment
1. **Redeploy Infrastructure:**
   \`\`\`bash
   ./scripts/deploy-${ENVIRONMENT}.sh
   \`\`\`

2. **Restore Data (if snapshots exist):**
   - Use AWS Console to restore RDS from snapshot
   - Update connection strings in application

3. **Reconfigure Monitoring:**
   \`\`\`bash
   ./scripts/setup-monitoring.sh $ENVIRONMENT
   ./scripts/cost-monitoring.sh $ENVIRONMENT
   \`\`\`

## Verification Checklist

- [ ] CloudFormation stack deleted
- [ ] No remaining EC2 instances
- [ ] No remaining RDS instances (or snapshots created)
- [ ] No unexpected charges in next billing cycle
- [ ] Monitoring resources cleaned up (if requested)

## Next Steps

1. **Monitor Billing:** Check AWS billing console for cost reduction
2. **Update Documentation:** Record cleanup in project documentation
3. **Team Notification:** Inform team that $ENVIRONMENT environment is offline
4. **Redeploy When Needed:** Use deployment scripts to recreate environment

---
*Generated by TechHealth Resource Cleanup Suite*
EOF

    # Replace ENVIRONMENT placeholder
    sed -i.bak "s/ENVIRONMENT/$ENVIRONMENT/g" "$REPORT_FILE" 2>/dev/null || true
    rm -f "$REPORT_FILE.bak" 2>/dev/null || true
    
    print_success "Cleanup report generated: $REPORT_FILE"
}

# Main execution
main() {
    get_resource_info
    
    if [ "$DRY_RUN" = true ]; then
        print_status "🔍 DRY RUN MODE - No resources will be deleted"
        echo ""
    fi
    
    create_rds_snapshots
    stop_ec2_instances
    delete_stack
    cleanup_cloudwatch
    cleanup_budgets
    cleanup_sns
    
    if [ "$DRY_RUN" != true ]; then
        verify_cleanup
    fi
    
    generate_cleanup_report
    
    echo ""
    if [ "$DRY_RUN" = true ]; then
        print_success "🔍 Dry run completed - no resources were deleted"
        echo ""
        echo "To actually perform the cleanup, run:"
        echo "  $0 $ENVIRONMENT $(echo "$@" | sed 's/--dry-run//')"
    else
        print_success "✅ Resource cleanup completed for $ENVIRONMENT environment"
        echo ""
        echo "💰 Expected cost savings:"
        case $ENVIRONMENT in
            dev) echo "   - Monthly savings: ~\$30-50" ;;
            staging) echo "   - Monthly savings: ~\$75-125" ;;
        esac
        
        echo ""
        echo "📋 What was cleaned up:"
        echo "   - CloudFormation stack and all resources"
        if [ "$CLEANUP_ALL" = true ]; then
            echo "   - CloudWatch dashboards and alarms"
            echo "   - SNS topics and budgets"
        fi
        if [ "$KEEP_DATA" = true ]; then
            echo "   - RDS snapshots created for data recovery"
        fi
        
        echo ""
        echo "🔄 To restore the environment:"
        echo "   ./scripts/deploy-${ENVIRONMENT}.sh"
    fi
    
    echo ""
    echo "📄 Detailed report: $REPORT_FILE"
}

# Run main function
main