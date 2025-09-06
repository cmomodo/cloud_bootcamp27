#!/bin/bash

# CloudWatch Monitoring Setup Script for TechHealth Infrastructure
# This script creates CloudWatch dashboards, alarms, and monitoring tools

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
    echo "  --dashboard-only    Create only CloudWatch dashboard"
    echo "  --alarms-only       Create only CloudWatch alarms"
    echo "  --verbose           Show detailed output"
    echo "  --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 dev --verbose"
    echo "  $0 prod --dashboard-only"
    exit 1
}

# Parse command line arguments
ENVIRONMENT=""
DASHBOARD_ONLY=false
ALARMS_ONLY=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        dev|staging|prod)
            ENVIRONMENT="$1"
            shift
            ;;
        --dashboard-only)
            DASHBOARD_ONLY=true
            shift
            ;;
        --alarms-only)
            ALARMS_ONLY=true
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

# Set environment variables
export ENVIRONMENT
export CDK_DEFAULT_REGION=us-east-1

echo "📊 TechHealth CloudWatch Monitoring Setup"
echo "=========================================="
echo "Environment: $ENVIRONMENT"
echo ""

STACK_NAME="TechHealth-$(echo $ENVIRONMENT | sed 's/.*/\u&/')-Infrastructure"

# Check if stack exists
print_status "Checking if stack exists..."
if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" &>/dev/null; then
    print_error "Stack $STACK_NAME does not exist. Deploy the infrastructure first."
    exit 1
fi

print_success "Stack $STACK_NAME found"

# Get resource IDs from stack
print_status "Retrieving resource IDs from stack..."

# Get VPC ID
VPC_ID=$(aws cloudformation describe-stack-resources \
    --stack-name "$STACK_NAME" \
    --query 'StackResources[?ResourceType==`AWS::EC2::VPC`].PhysicalResourceId' \
    --output text 2>/dev/null || echo "")

# Get EC2 Instance IDs
EC2_INSTANCES=$(aws ec2 describe-instances \
    --filters "Name=tag:aws:cloudformation:stack-name,Values=$STACK_NAME" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text)

# Get RDS Instance ID
RDS_INSTANCE=$(aws rds describe-db-instances \
    --query "DBInstances[?contains(DBInstanceIdentifier, '$(echo $STACK_NAME | tr '[:upper:]' '[:lower:]')') || contains(DBInstanceIdentifier, 'techhealth')].DBInstanceIdentifier" \
    --output text 2>/dev/null | head -1)

print_status "Found resources:"
echo "  VPC ID: ${VPC_ID:-Not found}"
echo "  EC2 Instances: ${EC2_INSTANCES:-Not found}"
echo "  RDS Instance: ${RDS_INSTANCE:-Not found}"

# Create CloudWatch Dashboard
create_dashboard() {
    print_status "Creating CloudWatch dashboard..."
    
    DASHBOARD_NAME="TechHealth-${ENVIRONMENT}-Infrastructure"
    
    # Create dashboard JSON
    cat > "/tmp/dashboard-${ENVIRONMENT}.json" << EOF
{
    "widgets": [
        {
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
$(if [ -n "$EC2_INSTANCES" ]; then
    for instance in $EC2_INSTANCES; do
        echo "                    [ \"AWS/EC2\", \"CPUUtilization\", \"InstanceId\", \"$instance\" ],"
    done
fi)
                ],
                "view": "timeSeries",
                "stacked": false,
                "region": "$CDK_DEFAULT_REGION",
                "title": "EC2 CPU Utilization",
                "period": 300,
                "stat": "Average"
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
$(if [ -n "$EC2_INSTANCES" ]; then
    for instance in $EC2_INSTANCES; do
        echo "                    [ \"AWS/EC2\", \"NetworkIn\", \"InstanceId\", \"$instance\" ],"
        echo "                    [ \".\", \"NetworkOut\", \".\", \"$instance\" ],"
    done
fi)
                ],
                "view": "timeSeries",
                "stacked": false,
                "region": "$CDK_DEFAULT_REGION",
                "title": "EC2 Network Traffic",
                "period": 300,
                "stat": "Average"
            }
        },
$(if [ -n "$RDS_INSTANCE" ]; then
cat << 'RDSEOF'
        {
            "type": "metric",
            "x": 0,
            "y": 6,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "RDSINSTANCE" ],
                    [ ".", "DatabaseConnections", ".", "RDSINSTANCE" ],
                    [ ".", "FreeableMemory", ".", "RDSINSTANCE" ]
                ],
                "view": "timeSeries",
                "stacked": false,
                "region": "REGION",
                "title": "RDS Performance Metrics",
                "period": 300,
                "stat": "Average"
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 6,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/RDS", "ReadLatency", "DBInstanceIdentifier", "RDSINSTANCE" ],
                    [ ".", "WriteLatency", ".", "RDSINSTANCE" ],
                    [ ".", "ReadIOPS", ".", "RDSINSTANCE" ],
                    [ ".", "WriteIOPS", ".", "RDSINSTANCE" ]
                ],
                "view": "timeSeries",
                "stacked": false,
                "region": "REGION",
                "title": "RDS I/O Performance",
                "period": 300,
                "stat": "Average"
            }
        },
RDSEOF
fi)
        {
            "type": "log",
            "x": 0,
            "y": 12,
            "width": 24,
            "height": 6,
            "properties": {
                "query": "SOURCE '/aws/ec2/console' | fields @timestamp, @message\n| filter @message like /ERROR/\n| sort @timestamp desc\n| limit 100",
                "region": "$CDK_DEFAULT_REGION",
                "title": "Recent EC2 Errors",
                "view": "table"
            }
        }
    ]
}
EOF

    # Replace placeholders in RDS section
    if [ -n "$RDS_INSTANCE" ]; then
        sed -i.bak "s/RDSINSTANCE/$RDS_INSTANCE/g" "/tmp/dashboard-${ENVIRONMENT}.json"
        sed -i.bak "s/REGION/$CDK_DEFAULT_REGION/g" "/tmp/dashboard-${ENVIRONMENT}.json"
        rm "/tmp/dashboard-${ENVIRONMENT}.json.bak"
    fi
    
    # Create the dashboard
    if aws cloudwatch put-dashboard \
        --dashboard-name "$DASHBOARD_NAME" \
        --dashboard-body "file:///tmp/dashboard-${ENVIRONMENT}.json" > /dev/null; then
        print_success "CloudWatch dashboard created: $DASHBOARD_NAME"
        echo "  Dashboard URL: https://${CDK_DEFAULT_REGION}.console.aws.amazon.com/cloudwatch/home?region=${CDK_DEFAULT_REGION}#dashboards:name=${DASHBOARD_NAME}"
    else
        print_error "Failed to create CloudWatch dashboard"
        return 1
    fi
    
    # Clean up temp file
    rm -f "/tmp/dashboard-${ENVIRONMENT}.json"
}

# Create CloudWatch Alarms
create_alarms() {
    print_status "Creating CloudWatch alarms..."
    
    # EC2 CPU Utilization Alarms
    if [ -n "$EC2_INSTANCES" ]; then
        for instance in $EC2_INSTANCES; do
            # High CPU alarm
            aws cloudwatch put-metric-alarm \
                --alarm-name "TechHealth-${ENVIRONMENT}-EC2-HighCPU-${instance}" \
                --alarm-description "High CPU utilization on EC2 instance ${instance}" \
                --metric-name CPUUtilization \
                --namespace AWS/EC2 \
                --statistic Average \
                --period 300 \
                --threshold 80 \
                --comparison-operator GreaterThanThreshold \
                --evaluation-periods 2 \
                --alarm-actions "arn:aws:sns:${CDK_DEFAULT_REGION}:$(aws sts get-caller-identity --query Account --output text):techhealth-${ENVIRONMENT}-alerts" \
                --dimensions Name=InstanceId,Value=${instance} \
                --treat-missing-data notBreaching > /dev/null || print_warning "Failed to create CPU alarm for $instance"
            
            # Instance status check alarm
            aws cloudwatch put-metric-alarm \
                --alarm-name "TechHealth-${ENVIRONMENT}-EC2-StatusCheck-${instance}" \
                --alarm-description "Instance status check failed for ${instance}" \
                --metric-name StatusCheckFailed_Instance \
                --namespace AWS/EC2 \
                --statistic Maximum \
                --period 60 \
                --threshold 0 \
                --comparison-operator GreaterThanThreshold \
                --evaluation-periods 2 \
                --alarm-actions "arn:aws:sns:${CDK_DEFAULT_REGION}:$(aws sts get-caller-identity --query Account --output text):techhealth-${ENVIRONMENT}-alerts" \
                --dimensions Name=InstanceId,Value=${instance} \
                --treat-missing-data breaching > /dev/null || print_warning "Failed to create status check alarm for $instance"
        done
        
        print_success "Created EC2 alarms for $(echo $EC2_INSTANCES | wc -w) instances"
    fi
    
    # RDS Alarms
    if [ -n "$RDS_INSTANCE" ]; then
        # High CPU alarm
        aws cloudwatch put-metric-alarm \
            --alarm-name "TechHealth-${ENVIRONMENT}-RDS-HighCPU" \
            --alarm-description "High CPU utilization on RDS instance ${RDS_INSTANCE}" \
            --metric-name CPUUtilization \
            --namespace AWS/RDS \
            --statistic Average \
            --period 300 \
            --threshold 80 \
            --comparison-operator GreaterThanThreshold \
            --evaluation-periods 2 \
            --alarm-actions "arn:aws:sns:${CDK_DEFAULT_REGION}:$(aws sts get-caller-identity --query Account --output text):techhealth-${ENVIRONMENT}-alerts" \
            --dimensions Name=DBInstanceIdentifier,Value=${RDS_INSTANCE} \
            --treat-missing-data notBreaching > /dev/null || print_warning "Failed to create RDS CPU alarm"
        
        # Low free memory alarm
        aws cloudwatch put-metric-alarm \
            --alarm-name "TechHealth-${ENVIRONMENT}-RDS-LowMemory" \
            --alarm-description "Low free memory on RDS instance ${RDS_INSTANCE}" \
            --metric-name FreeableMemory \
            --namespace AWS/RDS \
            --statistic Average \
            --period 300 \
            --threshold 100000000 \
            --comparison-operator LessThanThreshold \
            --evaluation-periods 2 \
            --alarm-actions "arn:aws:sns:${CDK_DEFAULT_REGION}:$(aws sts get-caller-identity --query Account --output text):techhealth-${ENVIRONMENT}-alerts" \
            --dimensions Name=DBInstanceIdentifier,Value=${RDS_INSTANCE} \
            --treat-missing-data notBreaching > /dev/null || print_warning "Failed to create RDS memory alarm"
        
        # High database connections alarm
        aws cloudwatch put-metric-alarm \
            --alarm-name "TechHealth-${ENVIRONMENT}-RDS-HighConnections" \
            --alarm-description "High database connections on RDS instance ${RDS_INSTANCE}" \
            --metric-name DatabaseConnections \
            --namespace AWS/RDS \
            --statistic Average \
            --period 300 \
            --threshold 40 \
            --comparison-operator GreaterThanThreshold \
            --evaluation-periods 2 \
            --alarm-actions "arn:aws:sns:${CDK_DEFAULT_REGION}:$(aws sts get-caller-identity --query Account --output text):techhealth-${ENVIRONMENT}-alerts" \
            --dimensions Name=DBInstanceIdentifier,Value=${RDS_INSTANCE} \
            --treat-missing-data notBreaching > /dev/null || print_warning "Failed to create RDS connections alarm"
        
        print_success "Created RDS alarms for $RDS_INSTANCE"
    fi
}

# Create SNS topic for alerts (if it doesn't exist)
create_sns_topic() {
    print_status "Setting up SNS topic for alerts..."
    
    TOPIC_NAME="techhealth-${ENVIRONMENT}-alerts"
    TOPIC_ARN="arn:aws:sns:${CDK_DEFAULT_REGION}:$(aws sts get-caller-identity --query Account --output text):${TOPIC_NAME}"
    
    # Check if topic exists
    if aws sns get-topic-attributes --topic-arn "$TOPIC_ARN" &>/dev/null; then
        print_success "SNS topic already exists: $TOPIC_NAME"
    else
        # Create topic
        if aws sns create-topic --name "$TOPIC_NAME" > /dev/null; then
            print_success "Created SNS topic: $TOPIC_NAME"
        else
            print_error "Failed to create SNS topic"
            return 1
        fi
    fi
    
    echo "  Topic ARN: $TOPIC_ARN"
    echo "  To receive alerts, subscribe to this topic:"
    echo "    aws sns subscribe --topic-arn $TOPIC_ARN --protocol email --notification-endpoint your-email@example.com"
}

# Main execution
main() {
    create_sns_topic
    
    if [ "$ALARMS_ONLY" != true ]; then
        create_dashboard
    fi
    
    if [ "$DASHBOARD_ONLY" != true ]; then
        create_alarms
    fi
    
    echo ""
    print_success "✅ Monitoring setup completed for $ENVIRONMENT environment"
    echo ""
    echo "📊 What was created:"
    echo "   - CloudWatch Dashboard: TechHealth-${ENVIRONMENT}-Infrastructure"
    echo "   - CloudWatch Alarms for EC2 and RDS resources"
    echo "   - SNS Topic for alert notifications"
    echo ""
    echo "🔔 Next Steps:"
    echo "   1. Subscribe to SNS topic for email alerts"
    echo "   2. Review dashboard and customize as needed"
    echo "   3. Test alarms by triggering threshold conditions"
    echo "   4. Set up additional custom metrics if required"
    echo ""
    echo "📱 Access your dashboard:"
    echo "   https://${CDK_DEFAULT_REGION}.console.aws.amazon.com/cloudwatch/home?region=${CDK_DEFAULT_REGION}#dashboards:name=TechHealth-${ENVIRONMENT}-Infrastructure"
}

# Run main function
main