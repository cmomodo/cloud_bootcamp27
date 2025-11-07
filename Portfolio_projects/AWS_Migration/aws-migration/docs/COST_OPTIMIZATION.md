# Cost Optimization Guide

## Overview

This document provides comprehensive cost optimization strategies and recommendations for the TechHealth infrastructure modernization project. The goal is to minimize operational expenses while maintaining security, performance, and HIPAA compliance requirements.

## Table of Contents

- [Current Cost Analysis](#current-cost-analysis)
- [Cost Optimization Strategies](#cost-optimization-strategies)
- [Resource Right-Sizing](#resource-right-sizing)
- [Reserved Instances and Savings Plans](#reserved-instances-and-savings-plans)
- [Storage Optimization](#storage-optimization)
- [Network Cost Optimization](#network-cost-optimization)
- [Monitoring and Alerting](#monitoring-and-alerting)
- [Automated Cost Management](#automated-cost-management)

## Current Cost Analysis

### Monthly Cost Breakdown (Development Environment)

**Compute Resources**:

- EC2 t2.micro instances (2x): $16.56/month
- EBS GP3 storage (40GB total): $4.00/month
- EBS snapshots (estimated): $2.00/month

**Database**:

- RDS db.t3.micro: $15.84/month
- RDS storage (20GB): $2.30/month
- RDS backup storage: $0.50/month

**Networking**:

- Data transfer out: $0.09/GB (variable)
- Inter-AZ data transfer: $0.01/GB (variable)

**Security & Management**:

- Secrets Manager: $0.40/month per secret
- CloudTrail: $2.00/month (first trail free)
- CloudWatch Logs: $0.50/GB ingested

**Total Estimated Monthly Cost**: ~$44.19 (excluding variable data transfer)

### Cost Analysis Script

```bash
#!/bin/bash
# cost-analysis.sh - Analyze current AWS costs

echo "=== TechHealth Cost Analysis ==="

# Get current month costs
CURRENT_MONTH=$(date +%Y-%m-01)
NEXT_MONTH=$(date -d "next month" +%Y-%m-01)

echo "Analyzing costs from $CURRENT_MONTH to $NEXT_MONTH"

# Overall cost and usage
aws ce get-cost-and-usage \
  --time-period Start=$CURRENT_MONTH,End=$NEXT_MONTH \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --query 'ResultsByTime[0].Groups[*].[Keys[0],Metrics.BlendedCost.Amount]' \
  --output table

# EC2 instance costs
echo -e "\n=== EC2 Instance Costs ==="
aws ce get-cost-and-usage \
  --time-period Start=$CURRENT_MONTH,End=$NEXT_MONTH \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=INSTANCE_TYPE \
  --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Elastic Compute Cloud - Compute"]}}' \
  --query 'ResultsByTime[0].Groups[*].[Keys[0],Metrics.BlendedCost.Amount]' \
  --output table

# RDS costs
echo -e "\n=== RDS Costs ==="
aws ce get-cost-and-usage \
  --time-period Start=$CURRENT_MONTH,End=$NEXT_MONTH \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Relational Database Service"]}}' \
  --query 'ResultsByTime[0].Total.BlendedCost.Amount' \
  --output text

# Data transfer costs
echo -e "\n=== Data Transfer Costs ==="
aws ce get-cost-and-usage \
  --time-period Start=$CURRENT_MONTH,End=$NEXT_MONTH \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Elastic Compute Cloud - Data Transfer"]}}' \
  --query 'ResultsByTime[0].Total.BlendedCost.Amount' \
  --output text

echo "=== Cost Analysis Complete ==="
```

## Cost Optimization Strategies

### 1. Free Tier Utilization

**Current Free Tier Usage**:

```bash
# Check free tier usage
aws support describe-trusted-advisor-checks \
  --language en \
  --query 'checks[?name==`Service Limits`]'

# Monitor free tier usage with CloudWatch
aws cloudwatch put-metric-alarm \
  --alarm-name "Free-Tier-EC2-Hours" \
  --alarm-description "Monitor EC2 free tier usage" \
  --metric-name "InstanceHours" \
  --namespace "AWS/Billing" \
  --statistic Sum \
  --period 86400 \
  --threshold 700 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=InstanceType,Value=t2.micro
```

**Free Tier Eligible Resources**:

- EC2: 750 hours/month of t2.micro instances
- RDS: 750 hours/month of db.t2.micro instances
- EBS: 30GB of General Purpose SSD storage
- Data Transfer: 1GB/month outbound

### 2. Instance Right-Sizing

**Current vs. Optimized Sizing**:

```bash
#!/bin/bash
# rightsizing-analysis.sh

echo "=== Right-Sizing Analysis ==="

# Get current instance utilization
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=TechHealth" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

# CPU utilization over last 30 days
echo "CPU Utilization (30 days average):"
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=$INSTANCE_ID \
  --start-time $(date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 86400 \
  --statistics Average \
  --query 'Datapoints[*].Average' \
  --output text | awk '{sum+=$1; count++} END {print sum/count "%"}'

# Memory utilization (if CloudWatch agent is installed)
echo "Memory Utilization (30 days average):"
aws cloudwatch get-metric-statistics \
  --namespace CWAgent \
  --metric-name mem_used_percent \
  --dimensions Name=InstanceId,Value=$INSTANCE_ID \
  --start-time $(date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 86400 \
  --statistics Average \
  --query 'Datapoints[*].Average' \
  --output text | awk '{sum+=$1; count++} END {print sum/count "%"}'

# Network utilization
echo "Network In (30 days average):"
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name NetworkIn \
  --dimensions Name=InstanceId,Value=$INSTANCE_ID \
  --start-time $(date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 86400 \
  --statistics Average \
  --query 'Datapoints[*].Average' \
  --output text | awk '{sum+=$1; count++} END {print sum/count " bytes"}'

echo "=== Right-Sizing Recommendations ==="
echo "If CPU < 20%: Consider t2.nano or t3.nano"
echo "If CPU 20-40%: Current t2.micro is appropriate"
echo "If CPU > 60%: Consider t3.small or t3.medium"
```

**Right-Sizing Recommendations**:

| Current Instance | Average CPU | Recommended Instance | Monthly Savings                                     |
| ---------------- | ----------- | -------------------- | --------------------------------------------------- |
| t2.micro         | <10%        | t2.nano              | $4.18/month                                         |
| t2.micro         | 10-40%      | t2.micro             | $0 (optimal)                                        |
| t2.micro         | >60%        | t3.small             | -$8.35/month (cost increase but better performance) |

### 3. Scheduled Scaling

**Development Environment Scheduling**:

```bash
#!/bin/bash
# scheduled-scaling.sh - Implement scheduled start/stop for dev environment

# Create Lambda function for instance scheduling
cat > instance-scheduler.py << 'EOF'
import boto3
import json

def lambda_handler(event, context):
    ec2 = boto3.client('ec2')
    rds = boto3.client('rds')

    action = event.get('action', 'stop')
    environment = event.get('environment', 'dev')

    # Get instances by environment tag
    instances = ec2.describe_instances(
        Filters=[
            {'Name': 'tag:Environment', 'Values': [environment]},
            {'Name': 'instance-state-name', 'Values': ['running', 'stopped']}
        ]
    )

    instance_ids = []
    for reservation in instances['Reservations']:
        for instance in reservation['Instances']:
            instance_ids.append(instance['InstanceId'])

    if action == 'stop':
        if instance_ids:
            ec2.stop_instances(InstanceIds=instance_ids)
            print(f"Stopped instances: {instance_ids}")

        # Stop RDS instances
        db_instances = rds.describe_db_instances()
        for db in db_instances['DBInstances']:
            if db['DBInstanceStatus'] == 'available':
                rds.stop_db_instance(DBInstanceIdentifier=db['DBInstanceIdentifier'])
                print(f"Stopped RDS: {db['DBInstanceIdentifier']}")

    elif action == 'start':
        if instance_ids:
            ec2.start_instances(InstanceIds=instance_ids)
            print(f"Started instances: {instance_ids}")

        # Start RDS instances
        db_instances = rds.describe_db_instances()
        for db in db_instances['DBInstances']:
            if db['DBInstanceStatus'] == 'stopped':
                rds.start_db_instance(DBInstanceIdentifier=db['DBInstanceIdentifier'])
                print(f"Started RDS: {db['DBInstanceIdentifier']}")

    return {
        'statusCode': 200,
        'body': json.dumps(f'Successfully {action}ped {environment} environment')
    }
EOF

# Create EventBridge rules for scheduling
# Stop instances at 6 PM weekdays
aws events put-rule \
  --name "TechHealth-Stop-Dev" \
  --schedule-expression "cron(0 18 ? * MON-FRI *)" \
  --description "Stop development environment at 6 PM weekdays"

# Start instances at 8 AM weekdays
aws events put-rule \
  --name "TechHealth-Start-Dev" \
  --schedule-expression "cron(0 8 ? * MON-FRI *)" \
  --description "Start development environment at 8 AM weekdays"
```

**Potential Savings with Scheduling**:

- Development environment running 10 hours/day, 5 days/week
- Savings: ~58% of compute costs
- Monthly savings: ~$18.50 for EC2 + RDS

### 4. Storage Optimization

**EBS Volume Optimization**:

```bash
#!/bin/bash
# storage-optimization.sh

echo "=== Storage Optimization Analysis ==="

# Analyze EBS volume utilization
for volume in $(aws ec2 describe-volumes --query 'Volumes[*].VolumeId' --output text); do
    echo "Volume: $volume"

    # Get volume details
    aws ec2 describe-volumes --volume-ids $volume \
      --query 'Volumes[0].[VolumeType,Size,Iops]' \
      --output text

    # Check if volume is attached
    INSTANCE_ID=$(aws ec2 describe-volumes --volume-ids $volume \
      --query 'Volumes[0].Attachments[0].InstanceId' \
      --output text)

    if [ "$INSTANCE_ID" != "None" ]; then
        echo "  Attached to: $INSTANCE_ID"

        # Get disk usage (requires CloudWatch agent)
        aws cloudwatch get-metric-statistics \
          --namespace CWAgent \
          --metric-name disk_used_percent \
          --dimensions Name=InstanceId,Value=$INSTANCE_ID Name=device,Value=/dev/xvda1 \
          --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
          --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
          --period 86400 \
          --statistics Average \
          --query 'Datapoints[*].Average' \
          --output text | awk '{sum+=$1; count++} END {print "  Disk usage: " sum/count "%"}'
    fi
    echo ""
done

echo "=== Storage Recommendations ==="
echo "- Volumes with <50% usage: Consider reducing size"
echo "- GP2 volumes: Consider migrating to GP3 for cost savings"
echo "- Unused snapshots: Delete old snapshots"
```

**GP2 to GP3 Migration**:

```bash
# Migrate EBS volumes from GP2 to GP3 for cost savings
for volume in $(aws ec2 describe-volumes --filters "Name=volume-type,Values=gp2" --query 'Volumes[*].VolumeId' --output text); do
    echo "Migrating volume $volume from GP2 to GP3"

    aws ec2 modify-volume \
      --volume-id $volume \
      --volume-type gp3 \
      --iops 3000 \
      --throughput 125
done
```

**Snapshot Lifecycle Management**:

```bash
# Create lifecycle policy for automated snapshot management
aws dlm create-lifecycle-policy \
  --execution-role-arn arn:aws:iam::ACCOUNT:role/AWSDataLifecycleManagerDefaultRole \
  --description "TechHealth snapshot lifecycle policy" \
  --state ENABLED \
  --policy-details '{
    "PolicyType": "EBS_SNAPSHOT_MANAGEMENT",
    "ResourceTypes": ["VOLUME"],
    "TargetTags": [{"Key": "Project", "Value": "TechHealth"}],
    "Schedules": [{
      "Name": "DailySnapshots",
      "CreateRule": {
        "Interval": 24,
        "IntervalUnit": "HOURS",
        "Times": ["03:00"]
      },
      "RetainRule": {
        "Count": 7
      },
      "TagsToAdd": [{"Key": "CreatedBy", "Value": "DLM"}],
      "CopyTags": true
    }]
  }'
```

## Reserved Instances and Savings Plans

### Reserved Instance Analysis

```bash
#!/bin/bash
# ri-analysis.sh - Analyze Reserved Instance opportunities

echo "=== Reserved Instance Analysis ==="

# Get current instance usage
aws ce get-usage-and-cost-with-resources \
  --time-period Start=$(date -d '30 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics BlendedCost,UsageQuantity \
  --group-by Type=DIMENSION,Key=INSTANCE_TYPE \
  --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Elastic Compute Cloud - Compute"]}}' \
  --query 'ResultsByTime[0].Groups[*].[Keys[0],Metrics.UsageQuantity.Amount,Metrics.BlendedCost.Amount]' \
  --output table

# Calculate RI savings potential
echo -e "\n=== RI Savings Calculation ==="
echo "t2.micro On-Demand: $0.0116/hour = $8.41/month"
echo "t2.micro RI (1-year, no upfront): $0.0058/hour = $4.20/month"
echo "Potential monthly savings per instance: $4.21 (50%)"

# RDS RI analysis
echo -e "\n=== RDS Reserved Instance Analysis ==="
echo "db.t3.micro On-Demand: $0.022/hour = $15.84/month"
echo "db.t3.micro RI (1-year, no upfront): $0.013/hour = $9.36/month"
echo "Potential monthly savings: $6.48 (41%)"
```

### Savings Plans Recommendations

**Compute Savings Plans**:

- **1-Year Term, No Upfront**: 17% savings on EC2 and Fargate
- **1-Year Term, Partial Upfront**: 20% savings
- **3-Year Term, All Upfront**: 54% savings

**EC2 Instance Savings Plans**:

- **1-Year Term, No Upfront**: 10% savings on specific instance families
- **3-Year Term, All Upfront**: 43% savings

```bash
# Purchase Savings Plan (example)
aws savingsplans create-savings-plan \
  --savings-plan-type "ComputeSavingsPlans" \
  --commitment "10.00" \
  --upfront-payment-amount "0.00" \
  --purchase-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --client-token $(uuidgen)
```

## Network Cost Optimization

### Data Transfer Optimization

**Current Data Transfer Patterns**:

```bash
#!/bin/bash
# data-transfer-analysis.sh

echo "=== Data Transfer Cost Analysis ==="

# Analyze VPC Flow Logs for data transfer patterns
aws logs filter-log-events \
  --log-group-name VPCFlowLogs \
  --start-time $(date -d '7 days ago' +%s)000 \
  --filter-pattern "[timestamp, account, eni, source, destination, srcport, destport, protocol, packets, bytes>1000000, windowstart, windowend, action]" \
  --query 'events[*].[eventTimestamp,message]' \
  --output table

# Check CloudFront usage (if applicable)
aws cloudfront list-distributions \
  --query 'DistributionList.Items[*].[Id,DomainName,Status]' \
  --output table

echo "=== Data Transfer Optimization Recommendations ==="
echo "1. Use CloudFront for static content delivery"
echo "2. Compress data before transfer"
echo "3. Minimize cross-AZ data transfer"
echo "4. Use VPC endpoints for AWS services"
```

**CloudFront Implementation for Cost Savings**:

```bash
# Create CloudFront distribution for static content
aws cloudfront create-distribution \
  --distribution-config '{
    "CallerReference": "techhealth-'$(date +%s)'",
    "Comment": "TechHealth static content distribution",
    "DefaultCacheBehavior": {
      "TargetOriginId": "techhealth-s3-origin",
      "ViewerProtocolPolicy": "redirect-to-https",
      "MinTTL": 0,
      "ForwardedValues": {
        "QueryString": false,
        "Cookies": {"Forward": "none"}
      }
    },
    "Origins": {
      "Quantity": 1,
      "Items": [{
        "Id": "techhealth-s3-origin",
        "DomainName": "techhealth-static-content.s3.amazonaws.com",
        "S3OriginConfig": {
          "OriginAccessIdentity": ""
        }
      }]
    },
    "Enabled": true,
    "PriceClass": "PriceClass_100"
  }'
```

### VPC Endpoint Implementation

```bash
# Create VPC endpoints to reduce NAT Gateway costs
# S3 VPC Endpoint
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-xxxxxxxxx \
  --service-name com.amazonaws.us-east-1.s3 \
  --vpc-endpoint-type Gateway \
  --route-table-ids rtb-xxxxxxxxx

# Secrets Manager VPC Endpoint
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-xxxxxxxxx \
  --service-name com.amazonaws.us-east-1.secretsmanager \
  --vpc-endpoint-type Interface \
  --subnet-ids subnet-xxxxxxxxx subnet-yyyyyyyyy \
  --security-group-ids sg-xxxxxxxxx
```

## Monitoring and Alerting

### Cost Monitoring Setup

```bash
#!/bin/bash
# cost-monitoring-setup.sh

echo "=== Setting up Cost Monitoring ==="

# Create budget for overall AWS spending
aws budgets create-budget \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --budget '{
    "BudgetName": "TechHealth-Monthly-Budget",
    "BudgetLimit": {
      "Amount": "100.00",
      "Unit": "USD"
    },
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST",
    "CostFilters": {
      "TagKey": ["Project"],
      "TagValue": ["TechHealth"]
    }
  }' \
  --notifications-with-subscribers '[{
    "Notification": {
      "NotificationType": "ACTUAL",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": 80
    },
    "Subscribers": [{
      "SubscriptionType": "EMAIL",
      "Address": "admin@techhealth.com"
    }]
  }]'

# Create CloudWatch billing alarms
aws cloudwatch put-metric-alarm \
  --alarm-name "TechHealth-Billing-Alarm" \
  --alarm-description "Alert when monthly bill exceeds $75" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 86400 \
  --threshold 75 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=Currency,Value=USD \
  --evaluation-periods 1 \
  --alarm-actions arn:aws:sns:us-east-1:ACCOUNT:billing-alerts

# Create service-specific alarms
aws cloudwatch put-metric-alarm \
  --alarm-name "TechHealth-EC2-Cost-Alarm" \
  --alarm-description "Alert when EC2 costs exceed $30/month" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 86400 \
  --threshold 30 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=Currency,Value=USD Name=ServiceName,Value=AmazonEC2 \
  --evaluation-periods 1

echo "=== Cost Monitoring Setup Complete ==="
```

### Cost Anomaly Detection

```bash
# Enable AWS Cost Anomaly Detection
aws ce create-anomaly-detector \
  --anomaly-detector '{
    "DetectorName": "TechHealth-Cost-Anomaly-Detector",
    "MonitorType": "DIMENSIONAL",
    "DimensionKey": "SERVICE",
    "MatchOptions": ["EQUALS"],
    "MonitorSpecification": "{\\"Dimension\\": \\"SERVICE\\", \\"MatchOptions\\": [\\"EQUALS\\"], \\"Values\\": [\\"Amazon Elastic Compute Cloud - Compute\\", \\"Amazon Relational Database Service\\"]}"
  }'

# Create anomaly subscription
aws ce create-anomaly-subscription \
  --anomaly-subscription '{
    "SubscriptionName": "TechHealth-Anomaly-Alerts",
    "MonitorArnList": ["arn:aws:ce::ACCOUNT:anomalydetector/DETECTOR-ID"],
    "Subscribers": [{
      "Address": "admin@techhealth.com",
      "Type": "EMAIL"
    }],
    "Threshold": 100,
    "Frequency": "DAILY"
  }'
```

## Automated Cost Management

### Cost Optimization Lambda Functions

```python
# cost-optimizer.py - Automated cost optimization
import boto3
import json
from datetime import datetime, timedelta

def lambda_handler(event, context):
    ec2 = boto3.client('ec2')
    rds = boto3.client('rds')
    cloudwatch = boto3.client('cloudwatch')

    # 1. Identify underutilized instances
    instances = ec2.describe_instances(
        Filters=[
            {'Name': 'tag:Project', 'Values': ['TechHealth']},
            {'Name': 'instance-state-name', 'Values': ['running']}
        ]
    )

    recommendations = []

    for reservation in instances['Reservations']:
        for instance in reservation['Instances']:
            instance_id = instance['InstanceId']
            instance_type = instance['InstanceType']

            # Get CPU utilization for last 7 days
            end_time = datetime.utcnow()
            start_time = end_time - timedelta(days=7)

            cpu_stats = cloudwatch.get_metric_statistics(
                Namespace='AWS/EC2',
                MetricName='CPUUtilization',
                Dimensions=[{'Name': 'InstanceId', 'Value': instance_id}],
                StartTime=start_time,
                EndTime=end_time,
                Period=86400,
                Statistics=['Average']
            )

            if cpu_stats['Datapoints']:
                avg_cpu = sum(dp['Average'] for dp in cpu_stats['Datapoints']) / len(cpu_stats['Datapoints'])

                if avg_cpu < 10:
                    recommendations.append({
                        'InstanceId': instance_id,
                        'CurrentType': instance_type,
                        'Recommendation': 'Consider stopping or downsizing',
                        'AvgCPU': avg_cpu,
                        'PotentialSavings': calculate_savings(instance_type, 'stop')
                    })
                elif avg_cpu < 20 and instance_type == 't2.micro':
                    recommendations.append({
                        'InstanceId': instance_id,
                        'CurrentType': instance_type,
                        'Recommendation': 'Consider t2.nano',
                        'AvgCPU': avg_cpu,
                        'PotentialSavings': calculate_savings('t2.micro', 't2.nano')
                    })

    # 2. Identify unused EBS volumes
    volumes = ec2.describe_volumes(
        Filters=[{'Name': 'status', 'Values': ['available']}]
    )

    for volume in volumes['Volumes']:
        recommendations.append({
            'VolumeId': volume['VolumeId'],
            'Size': volume['Size'],
            'Recommendation': 'Delete unused volume',
            'PotentialSavings': volume['Size'] * 0.10  # $0.10/GB/month for GP3
        })

    # 3. Identify old snapshots
    snapshots = ec2.describe_snapshots(OwnerIds=['self'])
    old_snapshots = []

    for snapshot in snapshots['Snapshots']:
        snapshot_date = snapshot['StartTime'].replace(tzinfo=None)
        if (datetime.utcnow() - snapshot_date).days > 30:
            old_snapshots.append({
                'SnapshotId': snapshot['SnapshotId'],
                'Age': (datetime.utcnow() - snapshot_date).days,
                'Size': snapshot['VolumeSize'],
                'Recommendation': 'Consider deleting old snapshot',
                'PotentialSavings': snapshot['VolumeSize'] * 0.05  # $0.05/GB/month
            })

    # Send recommendations via SNS
    sns = boto3.client('sns')
    message = {
        'InstanceRecommendations': recommendations,
        'VolumeRecommendations': [r for r in recommendations if 'VolumeId' in r],
        'SnapshotRecommendations': old_snapshots,
        'TotalPotentialSavings': sum(r.get('PotentialSavings', 0) for r in recommendations + old_snapshots)
    }

    sns.publish(
        TopicArn='arn:aws:sns:us-east-1:ACCOUNT:cost-optimization',
        Message=json.dumps(message, indent=2),
        Subject='TechHealth Cost Optimization Recommendations'
    )

    return {
        'statusCode': 200,
        'body': json.dumps(f'Generated {len(recommendations + old_snapshots)} recommendations')
    }

def calculate_savings(current_type, new_type):
    # Simplified pricing calculation
    pricing = {
        't2.nano': 0.0058,
        't2.micro': 0.0116,
        't2.small': 0.023,
        'stop': 0
    }

    current_cost = pricing.get(current_type, 0) * 24 * 30  # Monthly cost
    new_cost = pricing.get(new_type, 0) * 24 * 30

    return current_cost - new_cost
```

### Automated Resource Cleanup

```bash
#!/bin/bash
# automated-cleanup.sh - Clean up unused resources

echo "=== Automated Resource Cleanup ==="

# 1. Delete old snapshots (older than 30 days)
echo "1. Cleaning up old snapshots..."
aws ec2 describe-snapshots --owner-ids self \
  --query "Snapshots[?StartTime<='$(date -d '30 days ago' -u +%Y-%m-%dT%H:%M:%S.000Z)'].SnapshotId" \
  --output text | xargs -n1 -I {} aws ec2 delete-snapshot --snapshot-id {}

# 2. Delete unattached EBS volumes (after confirmation)
echo "2. Identifying unattached EBS volumes..."
UNATTACHED_VOLUMES=$(aws ec2 describe-volumes \
  --filters "Name=status,Values=available" \
  --query 'Volumes[*].VolumeId' \
  --output text)

if [ -n "$UNATTACHED_VOLUMES" ]; then
    echo "Found unattached volumes: $UNATTACHED_VOLUMES"
    echo "Manual review required before deletion"
    # Uncomment to auto-delete (use with caution)
    # echo $UNATTACHED_VOLUMES | xargs -n1 aws ec2 delete-volume --volume-id
fi

# 3. Clean up old AMIs
echo "3. Cleaning up old AMIs..."
aws ec2 describe-images --owners self \
  --query "Images[?CreationDate<='$(date -d '90 days ago' -u +%Y-%m-%dT%H:%M:%S.000Z)'].ImageId" \
  --output text | xargs -n1 -I {} aws ec2 deregister-image --image-id {}

# 4. Clean up unused security groups
echo "4. Identifying unused security groups..."
aws ec2 describe-security-groups \
  --query 'SecurityGroups[?GroupName!=`default`].[GroupId,GroupName]' \
  --output text | while read sg_id sg_name; do

    # Check if security group is used by any instance
    INSTANCES=$(aws ec2 describe-instances \
      --filters "Name=instance.group-id,Values=$sg_id" \
      --query 'Reservations[*].Instances[*].InstanceId' \
      --output text)

    if [ -z "$INSTANCES" ]; then
        echo "Unused security group: $sg_id ($sg_name)"
        # Uncomment to auto-delete (use with caution)
        # aws ec2 delete-security-group --group-id $sg_id
    fi
done

echo "=== Cleanup Complete ==="
```

### Cost Reporting Dashboard

```bash
#!/bin/bash
# create-cost-dashboard.sh

# Create CloudWatch dashboard for cost monitoring
cat > cost-dashboard.json << 'EOF'
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
          [ "AWS/Billing", "EstimatedCharges", "Currency", "USD" ],
          [ ".", ".", "Currency", "USD", "ServiceName", "AmazonEC2" ],
          [ ".", ".", "Currency", "USD", "ServiceName", "AmazonRDS" ]
        ],
        "period": 86400,
        "stat": "Maximum",
        "region": "us-east-1",
        "title": "Estimated Monthly Charges"
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
          [ "AWS/EC2", "CPUUtilization", "InstanceId", "INSTANCE_ID_1" ],
          [ ".", ".", "InstanceId", "INSTANCE_ID_2" ]
        ],
        "period": 300,
        "stat": "Average",
        "region": "us-east-1",
        "title": "EC2 CPU Utilization"
      }
    }
  ]
}
EOF

# Replace placeholder instance IDs
INSTANCE_IDS=($(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=TechHealth" \
  --query 'Reservations[*].Instances[*].InstanceId' \
  --output text))

sed -i "s/INSTANCE_ID_1/${INSTANCE_IDS[0]}/g" cost-dashboard.json
sed -i "s/INSTANCE_ID_2/${INSTANCE_IDS[1]}/g" cost-dashboard.json

# Create dashboard
aws cloudwatch put-dashboard \
  --dashboard-name "TechHealth-Cost-Monitoring" \
  --dashboard-body file://cost-dashboard.json

echo "Cost monitoring dashboard created"
rm cost-dashboard.json
```

## Cost Optimization Recommendations Summary

### Immediate Actions (0-30 days)

1. **Enable detailed billing and cost allocation tags**
2. **Set up billing alerts and budgets**
3. **Implement scheduled start/stop for development environments**
4. **Migrate GP2 volumes to GP3**
5. **Delete unused snapshots and volumes**

### Short-term Actions (1-3 months)

1. **Purchase Reserved Instances for stable workloads**
2. **Implement CloudFront for static content**
3. **Right-size instances based on utilization data**
4. **Set up automated cost optimization Lambda functions**
5. **Implement VPC endpoints to reduce data transfer costs**

### Long-term Actions (3-12 months)

1. **Consider Savings Plans for flexible compute savings**
2. **Implement auto-scaling for variable workloads**
3. **Evaluate containerization with ECS/EKS for better resource utilization**
4. **Consider Spot Instances for non-critical workloads**
5. **Regular cost optimization reviews and adjustments**

### Expected Cost Savings

| Optimization                | Monthly Savings | Implementation Effort |
| --------------------------- | --------------- | --------------------- |
| Scheduled scaling (dev)     | $18.50          | Low                   |
| GP2 to GP3 migration        | $1.20           | Low                   |
| Reserved Instances          | $10.69          | Medium                |
| CloudFront implementation   | $2.00           | Medium                |
| Resource cleanup            | $3.00           | Low                   |
| **Total Potential Savings** | **$35.39**      | **77% reduction**     |

This cost optimization guide provides a comprehensive approach to minimizing AWS costs while maintaining the security, performance, and compliance requirements of the TechHealth infrastructure.
