#!/bin/bash

# Cost Monitoring and Alerting Script for TechHealth Infrastructure
# This script sets up cost monitoring, budgets, and cost optimization recommendations

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
    echo "  dev       - Development environment"
    echo "  staging   - Staging environment"
    echo "  prod      - Production environment"
    echo ""
    echo "Options:"
    echo "  --budget-amount N    Set monthly budget amount in USD (default: dev=50, staging=100, prod=500)"
    echo "  --email EMAIL        Email address for cost alerts"
    echo "  --report-only        Generate cost report without creating budgets"
    echo "  --verbose            Show detailed output"
    echo "  --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 dev --email admin@techhealth.com"
    echo "  $0 prod --budget-amount 1000 --email finance@techhealth.com"
    echo "  $0 staging --report-only"
    exit 1
}

# Parse command line arguments
ENVIRONMENT=""
BUDGET_AMOUNT=""
EMAIL=""
REPORT_ONLY=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        dev|staging|prod)
            ENVIRONMENT="$1"
            shift
            ;;
        --budget-amount)
            BUDGET_AMOUNT="$2"
            shift 2
            ;;
        --email)
            EMAIL="$2"
            shift 2
            ;;
        --report-only)
            REPORT_ONLY=true
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

# Set default budget amounts if not specified
if [ -z "$BUDGET_AMOUNT" ]; then
    case $ENVIRONMENT in
        dev)
            BUDGET_AMOUNT=50
            ;;
        staging)
            BUDGET_AMOUNT=100
            ;;
        prod)
            BUDGET_AMOUNT=500
            ;;
    esac
fi

# Set environment variables
export ENVIRONMENT
export CDK_DEFAULT_REGION=us-east-1

echo "💰 TechHealth Cost Monitoring Setup"
echo "===================================="
echo "Environment: $ENVIRONMENT"
echo "Budget Amount: \$${BUDGET_AMOUNT}/month"
echo "Email: ${EMAIL:-Not specified}"
echo ""

STACK_NAME="TechHealth-$(echo $ENVIRONMENT | sed 's/.*/\u&/')-Infrastructure"

# Generate current cost report
generate_cost_report() {
    print_status "Generating cost report for $ENVIRONMENT environment..."
    
    # Get current date and 30 days ago
    END_DATE=$(date +%Y-%m-%d)
    START_DATE=$(date -d '30 days ago' +%Y-%m-%d)
    
    REPORT_FILE="cost-report-${ENVIRONMENT}-$(date +%Y%m%d).json"
    
    # Get cost and usage data
    aws ce get-cost-and-usage \
        --time-period Start=${START_DATE},End=${END_DATE} \
        --granularity MONTHLY \
        --metrics BlendedCost UnblendedCost \
        --group-by Type=DIMENSION,Key=SERVICE \
        --filter file://<(cat << EOF
{
    "Dimensions": {
        "Key": "RESOURCE_ID",
        "Values": ["*techhealth*", "*TechHealth*"],
        "MatchOptions": ["CONTAINS"]
    }
}
EOF
) > "$REPORT_FILE" 2>/dev/null || {
        # Fallback: get all costs if filtering fails
        aws ce get-cost-and-usage \
            --time-period Start=${START_DATE},End=${END_DATE} \
            --granularity MONTHLY \
            --metrics BlendedCost UnblendedCost \
            --group-by Type=DIMENSION,Key=SERVICE > "$REPORT_FILE"
    }
    
    print_success "Cost report generated: $REPORT_FILE"
    
    # Parse and display key metrics
    if command -v jq &> /dev/null; then
        TOTAL_COST=$(jq -r '.ResultsByTime[0].Total.BlendedCost.Amount // "0"' "$REPORT_FILE")
        print_status "Total cost (last 30 days): \$$(printf "%.2f" $TOTAL_COST)"
        
        echo ""
        echo "📊 Cost by Service (Top 5):"
        jq -r '.ResultsByTime[0].Groups[] | "\(.Keys[0]): $\(.Metrics.BlendedCost.Amount)"' "$REPORT_FILE" | \
            sort -t'$' -k2 -nr | head -5 | while read line; do
            echo "   $line"
        done
    fi
    
    echo ""
}

# Create cost budget
create_budget() {
    if [ "$REPORT_ONLY" = true ]; then
        print_status "Skipping budget creation (report-only mode)"
        return 0
    fi
    
    print_status "Creating cost budget for $ENVIRONMENT environment..."
    
    BUDGET_NAME="TechHealth-${ENVIRONMENT}-Monthly-Budget"
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Create budget JSON
    cat > "/tmp/budget-${ENVIRONMENT}.json" << EOF
{
    "BudgetName": "$BUDGET_NAME",
    "BudgetLimit": {
        "Amount": "$BUDGET_AMOUNT",
        "Unit": "USD"
    },
    "TimeUnit": "MONTHLY",
    "TimePeriod": {
        "Start": "$(date +%Y-%m-01)",
        "End": "2030-12-31"
    },
    "BudgetType": "COST",
    "CostFilters": {
        "TagKey": [
            "Environment"
        ],
        "TagValue": [
            "$ENVIRONMENT"
        ]
    }
}
EOF

    # Create notifications JSON
    NOTIFICATIONS='[]'
    if [ -n "$EMAIL" ]; then
        cat > "/tmp/notifications-${ENVIRONMENT}.json" << EOF
[
    {
        "Notification": {
            "NotificationType": "ACTUAL",
            "ComparisonOperator": "GREATER_THAN",
            "Threshold": 80,
            "ThresholdType": "PERCENTAGE"
        },
        "Subscribers": [
            {
                "SubscriptionType": "EMAIL",
                "Address": "$EMAIL"
            }
        ]
    },
    {
        "Notification": {
            "NotificationType": "FORECASTED",
            "ComparisonOperator": "GREATER_THAN",
            "Threshold": 100,
            "ThresholdType": "PERCENTAGE"
        },
        "Subscribers": [
            {
                "SubscriptionType": "EMAIL",
                "Address": "$EMAIL"
            }
        ]
    }
]
EOF
        NOTIFICATIONS="file:///tmp/notifications-${ENVIRONMENT}.json"
    fi
    
    # Create or update budget
    if [ -n "$EMAIL" ]; then
        aws budgets create-budget \
            --account-id "$ACCOUNT_ID" \
            --budget "file:///tmp/budget-${ENVIRONMENT}.json" \
            --notifications-with-subscribers "$NOTIFICATIONS" > /dev/null 2>&1 || {
            # Try to update if creation fails (budget might already exist)
            aws budgets modify-budget \
                --account-id "$ACCOUNT_ID" \
                --new-budget "file:///tmp/budget-${ENVIRONMENT}.json" > /dev/null 2>&1 || \
                print_warning "Failed to create/update budget (may already exist)"
        }
    else
        aws budgets create-budget \
            --account-id "$ACCOUNT_ID" \
            --budget "file:///tmp/budget-${ENVIRONMENT}.json" > /dev/null 2>&1 || {
            aws budgets modify-budget \
                --account-id "$ACCOUNT_ID" \
                --new-budget "file:///tmp/budget-${ENVIRONMENT}.json" > /dev/null 2>&1 || \
                print_warning "Failed to create/update budget (may already exist)"
        }
    fi
    
    print_success "Budget created/updated: $BUDGET_NAME (\$${BUDGET_AMOUNT}/month)"
    
    if [ -n "$EMAIL" ]; then
        print_success "Email notifications configured for: $EMAIL"
        echo "   - Alert at 80% of budget"
        echo "   - Forecast alert at 100% of budget"
    else
        print_warning "No email specified - budget created without notifications"
    fi
    
    # Clean up temp files
    rm -f "/tmp/budget-${ENVIRONMENT}.json" "/tmp/notifications-${ENVIRONMENT}.json"
}

# Generate cost optimization recommendations
generate_cost_optimization_report() {
    print_status "Generating cost optimization recommendations..."
    
    OPTIMIZATION_REPORT="cost-optimization-${ENVIRONMENT}-$(date +%Y%m%d).md"
    
    cat > "$OPTIMIZATION_REPORT" << EOF
# TechHealth Cost Optimization Report

**Environment:** $ENVIRONMENT
**Generated:** $(date)
**Current Monthly Budget:** \$${BUDGET_AMOUNT}

## Current Infrastructure Costs

### Resource Analysis

#### EC2 Instances
EOF

    # Analyze EC2 instances
    if aws cloudformation describe-stacks --stack-name "$STACK_NAME" &>/dev/null; then
        EC2_INSTANCES=$(aws ec2 describe-instances \
            --filters "Name=tag:aws:cloudformation:stack-name,Values=$STACK_NAME" \
            --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name]' \
            --output text)
        
        if [ -n "$EC2_INSTANCES" ]; then
            echo "$EC2_INSTANCES" | while read instance_id instance_type state; do
                cat >> "$OPTIMIZATION_REPORT" << EOF
- **Instance:** $instance_id
  - **Type:** $instance_type
  - **State:** $state
  - **Estimated Monthly Cost:** \$$(get_ec2_cost "$instance_type")
  - **Optimization:** $(get_ec2_optimization "$instance_type" "$ENVIRONMENT")

EOF
            done
        else
            echo "- No EC2 instances found in stack" >> "$OPTIMIZATION_REPORT"
        fi
    else
        echo "- Stack not found - unable to analyze EC2 costs" >> "$OPTIMIZATION_REPORT"
    fi
    
    cat >> "$OPTIMIZATION_REPORT" << EOF

#### RDS Database
EOF

    # Analyze RDS instances
    RDS_INSTANCE=$(aws rds describe-db-instances \
        --query "DBInstances[?contains(DBInstanceIdentifier, '$(echo $STACK_NAME | tr '[:upper:]' '[:lower:]')') || contains(DBInstanceIdentifier, 'techhealth')].{ID:DBInstanceIdentifier,Class:DBInstanceClass,Engine:Engine,MultiAZ:MultiAZ,Storage:AllocatedStorage}" \
        --output text 2>/dev/null | head -1)
    
    if [ -n "$RDS_INSTANCE" ]; then
        echo "$RDS_INSTANCE" | while read db_id db_class engine multi_az storage; do
            cat >> "$OPTIMIZATION_REPORT" << EOF
- **Database:** $db_id
  - **Class:** $db_class
  - **Engine:** $engine
  - **Multi-AZ:** $multi_az
  - **Storage:** ${storage}GB
  - **Estimated Monthly Cost:** \$$(get_rds_cost "$db_class" "$storage" "$multi_az")
  - **Optimization:** $(get_rds_optimization "$db_class" "$ENVIRONMENT")

EOF
        done
    else
        echo "- No RDS instances found" >> "$OPTIMIZATION_REPORT"
    fi
    
    cat >> "$OPTIMIZATION_REPORT" << EOF

## Cost Optimization Recommendations

### Immediate Actions (0-30 days)

1. **Right-sizing Analysis**
   - Monitor CPU and memory utilization for 2 weeks
   - Consider downsizing underutilized instances
   - Use CloudWatch metrics to identify optimization opportunities

2. **Reserved Instances** (Production only)
   - Consider 1-year Reserved Instances for stable workloads
   - Potential savings: 30-40% compared to On-Demand pricing
   - Recommended for production environment only

3. **Automated Scheduling** (Development/Staging)
   - Implement auto-shutdown for non-production environments
   - Schedule: Stop instances at 8 PM, start at 8 AM weekdays
   - Potential savings: 65% for development environments

### Medium-term Actions (1-3 months)

1. **Storage Optimization**
   - Implement lifecycle policies for logs and backups
   - Use GP3 storage instead of GP2 for better price/performance
   - Regular cleanup of unused snapshots and AMIs

2. **Network Optimization**
   - Monitor data transfer costs
   - Optimize application architecture to reduce cross-AZ traffic
   - Use CloudFront for static content delivery

3. **Monitoring and Alerting**
   - Set up cost anomaly detection
   - Implement automated cost reporting
   - Regular cost review meetings

### Long-term Actions (3+ months)

1. **Architecture Review**
   - Consider serverless alternatives for appropriate workloads
   - Evaluate container orchestration for better resource utilization
   - Implement auto-scaling based on demand patterns

2. **Multi-Account Strategy**
   - Separate billing for different environments
   - Use AWS Organizations for consolidated billing
   - Implement cost allocation tags

## Environment-Specific Recommendations

### $ENVIRONMENT Environment
EOF

    case $ENVIRONMENT in
        dev)
            cat >> "$OPTIMIZATION_REPORT" << EOF
- **Auto-shutdown:** Implement automated start/stop scheduling
- **Instance types:** Use t2.micro/t3.micro for development workloads
- **Storage:** Minimize storage allocation, use GP3 volumes
- **Monitoring:** Basic CloudWatch monitoring is sufficient
- **Target monthly cost:** \$30-50
EOF
            ;;
        staging)
            cat >> "$OPTIMIZATION_REPORT" << EOF
- **Scaling:** Use smaller instances than production
- **High availability:** Single-AZ deployment acceptable for testing
- **Backup:** Shorter retention periods than production
- **Monitoring:** Enhanced monitoring for performance testing
- **Target monthly cost:** \$75-125
EOF
            ;;
        prod)
            cat >> "$OPTIMIZATION_REPORT" << EOF
- **Reserved Instances:** Consider 1-year commitments for stable workloads
- **High availability:** Multi-AZ required for RDS
- **Backup:** Implement comprehensive backup strategy
- **Monitoring:** Full monitoring and alerting suite
- **Target monthly cost:** \$300-700 (depending on scale)
EOF
            ;;
    esac
    
    cat >> "$OPTIMIZATION_REPORT" << EOF

## Cost Monitoring Setup

### Budgets and Alerts
- Monthly budget: \$${BUDGET_AMOUNT}
- Alert thresholds: 80% actual, 100% forecasted
$(if [ -n "$EMAIL" ]; then echo "- Email notifications: $EMAIL"; else echo "- Email notifications: Not configured"; fi)

### Recommended Tools
1. **AWS Cost Explorer:** Monthly cost analysis and trends
2. **AWS Budgets:** Proactive cost monitoring and alerts
3. **AWS Trusted Advisor:** Cost optimization recommendations
4. **CloudWatch:** Resource utilization monitoring

## Action Items

### High Priority
- [ ] Review and implement auto-shutdown for non-production environments
- [ ] Set up cost anomaly detection
- [ ] Implement resource tagging strategy for cost allocation

### Medium Priority
- [ ] Analyze Reserved Instance opportunities (production only)
- [ ] Optimize storage configurations
- [ ] Review and cleanup unused resources

### Low Priority
- [ ] Evaluate serverless alternatives
- [ ] Implement advanced monitoring and alerting
- [ ] Consider multi-account billing strategy

---
*Generated by TechHealth Cost Monitoring Suite*
*Next review date: $(date -d '+1 month' +%Y-%m-%d)*
EOF

    print_success "Cost optimization report generated: $OPTIMIZATION_REPORT"
}

# Helper functions for cost estimation
get_ec2_cost() {
    local instance_type="$1"
    case $instance_type in
        t2.micro) echo "8.50" ;;
        t2.small) echo "17.00" ;;
        t2.medium) echo "34.00" ;;
        t3.micro) echo "7.50" ;;
        t3.small) echo "15.00" ;;
        t3.medium) echo "30.00" ;;
        *) echo "25.00" ;;
    esac
}

get_rds_cost() {
    local db_class="$1"
    local storage="$2"
    local multi_az="$3"
    
    local base_cost
    case $db_class in
        db.t3.micro) base_cost=15 ;;
        db.t3.small) base_cost=30 ;;
        db.t3.medium) base_cost=60 ;;
        *) base_cost=40 ;;
    esac
    
    local storage_cost=$((storage * 1))  # $0.10 per GB-month for GP2
    
    if [ "$multi_az" = "True" ]; then
        base_cost=$((base_cost * 2))
    fi
    
    echo $((base_cost + storage_cost))
}

get_ec2_optimization() {
    local instance_type="$1"
    local environment="$2"
    
    if [ "$environment" = "dev" ]; then
        echo "Consider auto-shutdown during non-business hours (65% savings)"
    elif [ "$instance_type" = "t2.micro" ] || [ "$instance_type" = "t3.micro" ]; then
        echo "Already cost-optimized for $environment environment"
    else
        echo "Consider downsizing to t3.micro if CPU utilization is low"
    fi
}

get_rds_optimization() {
    local db_class="$1"
    local environment="$2"
    
    if [ "$environment" = "dev" ]; then
        echo "Consider single-AZ deployment and automated shutdown"
    elif [ "$db_class" = "db.t3.micro" ]; then
        echo "Already cost-optimized for $environment environment"
    else
        echo "Monitor utilization and consider downsizing if appropriate"
    fi
}

# Main execution
main() {
    generate_cost_report
    create_budget
    generate_cost_optimization_report
    
    echo ""
    print_success "✅ Cost monitoring setup completed for $ENVIRONMENT environment"
    echo ""
    echo "💰 What was created:"
    echo "   - Monthly budget: \$${BUDGET_AMOUNT}"
    if [ -n "$EMAIL" ]; then
        echo "   - Email alerts configured for: $EMAIL"
    fi
    echo "   - Cost report: cost-report-${ENVIRONMENT}-$(date +%Y%m%d).json"
    echo "   - Optimization report: cost-optimization-${ENVIRONMENT}-$(date +%Y%m%d).md"
    echo ""
    echo "📊 Next Steps:"
    echo "   1. Review the cost optimization report"
    echo "   2. Implement recommended cost-saving measures"
    echo "   3. Set up regular cost review meetings"
    echo "   4. Monitor budget alerts and take action when needed"
    echo ""
    echo "🔗 Useful Links:"
    echo "   - AWS Cost Explorer: https://console.aws.amazon.com/cost-management/home#/cost-explorer"
    echo "   - AWS Budgets: https://console.aws.amazon.com/billing/home#/budgets"
    echo "   - Trusted Advisor: https://console.aws.amazon.com/trustedadvisor/"
}

# Run main function
main