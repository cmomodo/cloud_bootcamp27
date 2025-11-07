# Deployment Guide

## Overview

This guide provides detailed step-by-step instructions for deploying the TechHealth infrastructure modernization project using AWS CDK. The deployment process is designed to be safe, repeatable, and follows infrastructure as code best practices.

## Table of Contents

- [Pre-Deployment Checklist](#pre-deployment-checklist)
- [Environment Setup](#environment-setup)
- [Development Deployment](#development-deployment)
- [Staging Deployment](#staging-deployment)
- [Production Deployment](#production-deployment)
- [Post-Deployment Verification](#post-deployment-verification)
- [Rollback Procedures](#rollback-procedures)
- [Monitoring Setup](#monitoring-setup)

## Pre-Deployment Checklist

### Prerequisites Verification

Before starting any deployment, verify all prerequisites are met:

```bash
#!/bin/bash
# pre-deployment-checklist.sh

echo "=== Pre-Deployment Checklist ==="

# Check Node.js version
echo "1. Checking Node.js version..."
node_version=$(node --version | cut -d'v' -f2)
if [[ $(echo "$node_version >= 18.0" | bc -l) -eq 1 ]]; then
    echo "✅ Node.js version: $node_version (OK)"
else
    echo "❌ Node.js version: $node_version (Requires >= 18.0)"
    exit 1
fi

# Check AWS CLI
echo "2. Checking AWS CLI..."
if command -v aws &> /dev/null; then
    aws_version=$(aws --version | cut -d' ' -f1 | cut -d'/' -f2)
    echo "✅ AWS CLI version: $aws_version"
else
    echo "❌ AWS CLI not installed"
    exit 1
fi

# Check CDK CLI
echo "3. Checking CDK CLI..."
if command -v cdk &> /dev/null; then
    cdk_version=$(cdk --version)
    echo "✅ CDK CLI version: $cdk_version"
else
    echo "❌ CDK CLI not installed"
    exit 1
fi

# Check AWS credentials
echo "4. Checking AWS credentials..."
if aws sts get-caller-identity &> /dev/null; then
    account_id=$(aws sts get-caller-identity --query Account --output text)
    user_arn=$(aws sts get-caller-identity --query Arn --output text)
    echo "✅ AWS credentials configured"
    echo "   Account: $account_id"
    echo "   User: $user_arn"
else
    echo "❌ AWS credentials not configured"
    exit 1
fi

# Check CDK bootstrap
echo "5. Checking CDK bootstrap..."
if aws cloudformation describe-stacks --stack-name CDKToolkit &> /dev/null; then
    bootstrap_status=$(aws cloudformation describe-stacks --stack-name CDKToolkit --query 'Stacks[0].StackStatus' --output text)
    echo "✅ CDK bootstrap status: $bootstrap_status"
else
    echo "❌ CDK not bootstrapped"
    echo "   Run: cdk bootstrap aws://$account_id/$(aws configure get region)"
    exit 1
fi

# Check project dependencies
echo "6. Checking project dependencies..."
if [ -f "package.json" ] && [ -d "node_modules" ]; then
    echo "✅ Project dependencies installed"
else
    echo "❌ Project dependencies not installed"
    echo "   Run: npm install"
    exit 1
fi

echo "✅ All prerequisites met. Ready for deployment!"
```

### Required Information

Gather the following information before deployment:

1. **AWS Account ID**: `aws sts get-caller-identity --query Account --output text`
2. **Target Region**: e.g., `us-east-1`
3. **Environment**: `dev`, `staging`, or `prod`
4. **SSH Key Pair Name**: For EC2 access
5. **Allowed SSH CIDR**: Your IP address for SSH access

## Environment Setup

### 1. Clone and Initialize Project

```bash
# Clone the repository
git clone <repository-url>
cd aws-migration

# Install dependencies
npm install

# Build the project
npm run build

# Run tests to verify setup
npm test
```

### 2. Configure Environment Variables

Create environment-specific configuration:

```bash
# Set environment variables
export CDK_ENVIRONMENT=dev
export AWS_REGION=us-east-1
export AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

# Optional: Set specific stack name
export STACK_NAME=TechHealthInfrastructureStack-dev
```

### 3. Create SSH Key Pair

```bash
# Create key pair for EC2 access
aws ec2 create-key-pair \
  --key-name techhealth-${CDK_ENVIRONMENT}-keypair \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/techhealth-${CDK_ENVIRONMENT}.pem

# Set proper permissions
chmod 400 ~/.ssh/techhealth-${CDK_ENVIRONMENT}.pem

# Verify key pair creation
aws ec2 describe-key-pairs --key-names techhealth-${CDK_ENVIRONMENT}-keypair
```

### 4. Update Configuration Files

Edit the appropriate configuration file in `config/`:

```json
{
  "environment": "dev",
  "region": "us-east-1",
  "availabilityZones": ["us-east-1a", "us-east-1b"],
  "vpc": {
    "cidr": "10.0.0.0/16",
    "enableDnsHostnames": true,
    "enableDnsSupport": true
  },
  "ec2": {
    "instanceType": "t2.micro",
    "keyPairName": "techhealth-dev-keypair",
    "allowedSshCidrs": ["YOUR.IP.ADDRESS/32"]
  },
  "rds": {
    "instanceClass": "db.t3.micro",
    "engine": "mysql",
    "engineVersion": "8.0.35",
    "allocatedStorage": 20,
    "multiAz": false,
    "backupRetentionPeriod": 7
  },
  "security": {
    "enableCloudTrail": true,
    "enableVpcFlowLogs": true,
    "secretsManagerEnabled": true
  }
}
```

## Development Deployment

### Step 1: Pre-Deployment Validation

```bash
# Run pre-deployment validation script
./scripts/pre-deployment-validation.sh

# Validate CDK synthesis
npx cdk synth --context environment=dev

# Review generated CloudFormation template
cat cdk.out/TechHealthInfrastructureStack.template.json | jq '.'
```

### Step 2: Security Scan

```bash
# Run security scan on CDK template
./scripts/security-scan.sh

# Check for common misconfigurations
npx cdk synth --context environment=dev | checkov -f - --framework cloudformation
```

### Step 3: Deploy Infrastructure

```bash
# Deploy with development configuration
npx cdk deploy \
  --context environment=dev \
  --outputs-file outputs-dev.json \
  --require-approval never

# Monitor deployment progress
aws cloudformation describe-stack-events \
  --stack-name TechHealthInfrastructureStack \
  --query 'StackEvents[?ResourceStatus!=`CREATE_COMPLETE`]' \
  --output table
```

### Step 4: Post-Deployment Verification

```bash
# Run post-deployment verification
./scripts/post-deployment-verification.sh

# Test connectivity
npm run test:connectivity

# Verify security configuration
./scripts/validate-infrastructure.sh
```

### Step 5: Setup Monitoring

```bash
# Setup CloudWatch dashboards and alarms
./scripts/setup-monitoring.sh

# Verify monitoring setup
aws cloudwatch describe-alarms --alarm-names "TechHealth-EC2-HighCPU" "TechHealth-RDS-HighCPU"
```

## Staging Deployment

### Step 1: Environment Preparation

```bash
# Set staging environment
export CDK_ENVIRONMENT=staging

# Update configuration for staging
# Edit config/staging.json with appropriate values

# Create staging-specific key pair
aws ec2 create-key-pair \
  --key-name techhealth-staging-keypair \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/techhealth-staging.pem
chmod 400 ~/.ssh/techhealth-staging.pem
```

### Step 2: Enhanced Validation

```bash
# Run comprehensive validation
./scripts/pre-deployment-validation.sh

# Run security scan with stricter rules
./scripts/security-scan.sh --strict

# Validate against staging requirements
npm run test:staging
```

### Step 3: Staged Deployment

```bash
# Deploy with manual approval for changes
npx cdk deploy \
  --context environment=staging \
  --outputs-file outputs-staging.json \
  --require-approval any-change

# Wait for manual approval and continue
echo "Review the changes and approve in the CDK CLI prompt"
```

### Step 4: Integration Testing

```bash
# Run integration tests
npm run test:integration

# Test database connectivity
./scripts/test-database-connectivity.sh

# Validate security groups
./scripts/validate-security-groups.sh
```

### Step 5: Performance Testing

```bash
# Run performance tests
./scripts/performance-test.sh

# Monitor resource utilization
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=$(aws ec2 describe-instances --filters "Name=tag:Environment,Values=staging" --query 'Reservations[0].Instances[0].InstanceId' --output text) \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

## Production Deployment

### Step 1: Production Readiness Review

```bash
# Production readiness checklist
echo "=== Production Readiness Review ==="
echo "1. All tests passing in staging? [y/N]"
read -r staging_tests
echo "2. Security scan completed? [y/N]"
read -r security_scan
echo "3. Performance testing completed? [y/N]"
read -r performance_test
echo "4. Backup procedures tested? [y/N]"
read -r backup_test
echo "5. Rollback procedures tested? [y/N]"
read -r rollback_test

if [[ "$staging_tests" != "y" ]] || [[ "$security_scan" != "y" ]] || [[ "$performance_test" != "y" ]] || [[ "$backup_test" != "y" ]] || [[ "$rollback_test" != "y" ]]; then
    echo "❌ Production readiness requirements not met"
    exit 1
fi

echo "✅ Production readiness requirements met"
```

### Step 2: Production Configuration

```bash
# Set production environment
export CDK_ENVIRONMENT=prod

# Update production configuration
# Edit config/prod.json with production values:
# - Multi-AZ RDS deployment
# - Enhanced monitoring
# - Stricter security settings
# - Production-grade instance sizes (if needed)

# Create production key pair
aws ec2 create-key-pair \
  --key-name techhealth-prod-keypair \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/techhealth-prod.pem
chmod 400 ~/.ssh/techhealth-prod.pem

# Store key securely (consider AWS Systems Manager Parameter Store)
aws ssm put-parameter \
  --name "/techhealth/prod/ssh-key" \
  --value "file://~/.ssh/techhealth-prod.pem" \
  --type "SecureString" \
  --description "TechHealth Production SSH Key"
```

### Step 3: Final Validation

```bash
# Run comprehensive validation suite
./scripts/pre-deployment-validation.sh --environment prod

# Security scan with production rules
./scripts/security-scan.sh --environment prod --strict

# Validate compliance requirements
./scripts/validate-hipaa-compliance.sh

# Cost estimation
aws pricing get-products --service-code AmazonEC2 --filters file://pricing-filters.json
```

### Step 4: Production Deployment

```bash
# Create deployment backup
npx cdk synth --context environment=prod > backup-prod-$(date +%Y%m%d-%H%M%S).json

# Deploy with strict approval requirements
npx cdk deploy \
  --context environment=prod \
  --outputs-file outputs-prod.json \
  --require-approval any-change \
  --rollback-configuration RollbackTriggers='[{Arn=arn:aws:cloudwatch:region:account:alarm:TechHealth-Deployment-Failure,Type=AWS::CloudWatch::Alarm}]'

# Monitor deployment closely
watch -n 30 'aws cloudformation describe-stack-events --stack-name TechHealthInfrastructureStack --query "StackEvents[0:5].[Timestamp,ResourceStatus,ResourceType,LogicalResourceId]" --output table'
```

### Step 5: Production Verification

```bash
# Comprehensive production verification
./scripts/post-deployment-verification.sh --environment prod

# Security validation
./scripts/validate-production-security.sh

# Performance baseline
./scripts/establish-performance-baseline.sh

# Backup verification
./scripts/backup-verification.sh
```

## Post-Deployment Verification

### Automated Verification Script

```bash
#!/bin/bash
# post-deployment-verification.sh

ENVIRONMENT=${1:-dev}
echo "=== Post-Deployment Verification for $ENVIRONMENT ==="

# 1. Verify stack deployment
echo "1. Verifying stack deployment..."
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name TechHealthInfrastructureStack --query 'Stacks[0].StackStatus' --output text)
if [ "$STACK_STATUS" = "CREATE_COMPLETE" ] || [ "$STACK_STATUS" = "UPDATE_COMPLETE" ]; then
    echo "✅ Stack deployment successful: $STACK_STATUS"
else
    echo "❌ Stack deployment failed: $STACK_STATUS"
    exit 1
fi

# 2. Verify VPC creation
echo "2. Verifying VPC creation..."
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Project,Values=TechHealth" --query 'Vpcs[0].VpcId' --output text)
if [ "$VPC_ID" != "None" ] && [ "$VPC_ID" != "" ]; then
    echo "✅ VPC created: $VPC_ID"
else
    echo "❌ VPC not found"
    exit 1
fi

# 3. Verify subnets
echo "3. Verifying subnets..."
SUBNET_COUNT=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'length(Subnets)')
if [ "$SUBNET_COUNT" -eq 4 ]; then
    echo "✅ All 4 subnets created"
else
    echo "❌ Expected 4 subnets, found $SUBNET_COUNT"
    exit 1
fi

# 4. Verify EC2 instances
echo "4. Verifying EC2 instances..."
EC2_COUNT=$(aws ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" "Name=instance-state-name,Values=running" --query 'length(Reservations[*].Instances[*])')
if [ "$EC2_COUNT" -ge 1 ]; then
    echo "✅ EC2 instances running: $EC2_COUNT"

    # Get EC2 public IP
    EC2_IP=$(aws ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
    echo "   Public IP: $EC2_IP"
else
    echo "❌ No running EC2 instances found"
    exit 1
fi

# 5. Verify RDS instance
echo "5. Verifying RDS instance..."
RDS_STATUS=$(aws rds describe-db-instances --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null)
if [ "$RDS_STATUS" = "available" ]; then
    echo "✅ RDS instance available"

    # Get RDS endpoint
    RDS_ENDPOINT=$(aws rds describe-db-instances --query 'DBInstances[0].Endpoint.Address' --output text)
    echo "   Endpoint: $RDS_ENDPOINT"
else
    echo "❌ RDS instance not available: $RDS_STATUS"
    exit 1
fi

# 6. Verify security groups
echo "6. Verifying security groups..."
SG_COUNT=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query 'length(SecurityGroups[?GroupName!=`default`])')
if [ "$SG_COUNT" -ge 2 ]; then
    echo "✅ Security groups created: $SG_COUNT"
else
    echo "❌ Expected at least 2 security groups, found $SG_COUNT"
    exit 1
fi

# 7. Test SSH connectivity (if key exists)
echo "7. Testing SSH connectivity..."
if [ -f ~/.ssh/techhealth-${ENVIRONMENT}.pem ]; then
    timeout 10 ssh -i ~/.ssh/techhealth-${ENVIRONMENT}.pem -o ConnectTimeout=5 -o StrictHostKeyChecking=no ec2-user@$EC2_IP "echo 'SSH connection successful'" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "✅ SSH connectivity verified"
    else
        echo "⚠️  SSH connectivity test failed (may need to wait for instance initialization)"
    fi
else
    echo "⚠️  SSH key not found, skipping connectivity test"
fi

# 8. Test database connectivity
echo "8. Testing database connectivity..."
if [ -f ~/.ssh/techhealth-${ENVIRONMENT}.pem ]; then
    DB_TEST=$(timeout 15 ssh -i ~/.ssh/techhealth-${ENVIRONMENT}.pem -o ConnectTimeout=5 -o StrictHostKeyChecking=no ec2-user@$EC2_IP "timeout 10 mysql -h $RDS_ENDPOINT -u admin -p'$(aws secretsmanager get-secret-value --secret-id TechHealth-DB-Credentials --query SecretString --output text | jq -r .password)' -e 'SELECT 1' 2>/dev/null && echo 'success' || echo 'failed'" 2>/dev/null)
    if [ "$DB_TEST" = "success" ]; then
        echo "✅ Database connectivity verified"
    else
        echo "⚠️  Database connectivity test failed (may need to wait for RDS initialization)"
    fi
else
    echo "⚠️  Cannot test database connectivity without SSH key"
fi

# 9. Verify Secrets Manager
echo "9. Verifying Secrets Manager..."
SECRET_ARN=$(aws secretsmanager describe-secret --secret-id TechHealth-DB-Credentials --query 'ARN' --output text 2>/dev/null)
if [ "$SECRET_ARN" != "" ]; then
    echo "✅ Secrets Manager secret created"
else
    echo "❌ Secrets Manager secret not found"
    exit 1
fi

# 10. Verify CloudWatch logs
echo "10. Verifying CloudWatch logs..."
LOG_GROUPS=$(aws logs describe-log-groups --log-group-name-prefix "/aws/ec2" --query 'length(logGroups)')
if [ "$LOG_GROUPS" -gt 0 ]; then
    echo "✅ CloudWatch log groups created: $LOG_GROUPS"
else
    echo "⚠️  No CloudWatch log groups found yet"
fi

echo "✅ Post-deployment verification completed successfully!"
echo ""
echo "=== Deployment Summary ==="
echo "Environment: $ENVIRONMENT"
echo "VPC ID: $VPC_ID"
echo "EC2 Public IP: $EC2_IP"
echo "RDS Endpoint: $RDS_ENDPOINT"
echo "Stack Status: $STACK_STATUS"
echo ""
echo "Next steps:"
echo "1. Configure application on EC2 instances"
echo "2. Setup monitoring dashboards"
echo "3. Configure backup procedures"
echo "4. Update DNS records (if applicable)"
```

## Rollback Procedures

### Automatic Rollback

CDK supports automatic rollback on deployment failure:

```bash
# Deploy with automatic rollback on failure
npx cdk deploy \
  --context environment=dev \
  --rollback-configuration RollbackTriggers='[{Arn=arn:aws:cloudwatch:region:account:alarm:TechHealth-Deployment-Failure,Type=AWS::CloudWatch::Alarm}]'
```

### Manual Rollback

```bash
#!/bin/bash
# rollback-deployment.sh

ENVIRONMENT=${1:-dev}
echo "=== Rolling back deployment for $ENVIRONMENT ==="

# 1. Get current stack status
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name TechHealthInfrastructureStack --query 'Stacks[0].StackStatus' --output text)
echo "Current stack status: $STACK_STATUS"

# 2. If update failed, continue rollback
if [[ "$STACK_STATUS" == *"ROLLBACK_IN_PROGRESS"* ]]; then
    echo "Rollback already in progress, continuing..."
    aws cloudformation continue-update-rollback --stack-name TechHealthInfrastructureStack
elif [[ "$STACK_STATUS" == *"UPDATE_ROLLBACK_FAILED"* ]]; then
    echo "Rollback failed, attempting to continue..."
    aws cloudformation continue-update-rollback --stack-name TechHealthInfrastructureStack
elif [[ "$STACK_STATUS" == *"UPDATE_FAILED"* ]]; then
    echo "Update failed, initiating rollback..."
    aws cloudformation cancel-update-stack --stack-name TechHealthInfrastructureStack
else
    echo "Stack is in stable state: $STACK_STATUS"
    echo "Do you want to rollback to previous version? [y/N]"
    read -r confirm
    if [ "$confirm" = "y" ]; then
        # Deploy previous version from backup
        if [ -f "backup-prod-*.json" ]; then
            BACKUP_FILE=$(ls -t backup-prod-*.json | head -1)
            echo "Rolling back to: $BACKUP_FILE"
            # This would require custom rollback logic
            echo "Manual rollback required - restore from backup: $BACKUP_FILE"
        else
            echo "No backup file found for rollback"
        fi
    fi
fi

# 3. Monitor rollback progress
echo "Monitoring rollback progress..."
while true; do
    STATUS=$(aws cloudformation describe-stacks --stack-name TechHealthInfrastructureStack --query 'Stacks[0].StackStatus' --output text)
    echo "$(date): Stack status: $STATUS"

    if [[ "$STATUS" == *"COMPLETE"* ]] || [[ "$STATUS" == *"FAILED"* ]]; then
        break
    fi

    sleep 30
done

echo "Rollback completed with status: $STATUS"
```

### Emergency Procedures

```bash
#!/bin/bash
# emergency-rollback.sh - Complete infrastructure destruction and rebuild

echo "⚠️  EMERGENCY ROLLBACK PROCEDURE ⚠️"
echo "This will destroy ALL infrastructure and rebuild from scratch"
echo "Type 'CONFIRM' to proceed:"
read -r confirmation

if [ "$confirmation" != "CONFIRM" ]; then
    echo "Emergency rollback cancelled"
    exit 1
fi

ENVIRONMENT=${1:-dev}

# 1. Create emergency backup
echo "Creating emergency backup..."
npx cdk synth --context environment=$ENVIRONMENT > emergency-backup-$(date +%Y%m%d-%H%M%S).json

# 2. Destroy all infrastructure
echo "Destroying infrastructure..."
npx cdk destroy --context environment=$ENVIRONMENT --force

# 3. Wait for complete destruction
echo "Waiting for destruction to complete..."
sleep 120

# 4. Rebuild infrastructure
echo "Rebuilding infrastructure..."
npx cdk deploy --context environment=$ENVIRONMENT --require-approval never

# 5. Verify rebuild
echo "Verifying rebuild..."
./scripts/post-deployment-verification.sh $ENVIRONMENT

echo "Emergency rollback completed"
```

## Monitoring Setup

### CloudWatch Dashboard Creation

```bash
#!/bin/bash
# setup-monitoring.sh

ENVIRONMENT=${1:-dev}
echo "Setting up monitoring for $ENVIRONMENT environment..."

# Get resource IDs
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Project,Values=TechHealth" --query 'Vpcs[0].VpcId' --output text)
EC2_ID=$(aws ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].InstanceId' --output text)
RDS_ID=$(aws rds describe-db-instances --query 'DBInstances[0].DBInstanceIdentifier' --output text)

# Create CloudWatch dashboard
cat > dashboard.json << EOF
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
          [ "AWS/EC2", "CPUUtilization", "InstanceId", "$EC2_ID" ],
          [ ".", "NetworkIn", ".", "." ],
          [ ".", "NetworkOut", ".", "." ]
        ],
        "period": 300,
        "stat": "Average",
        "region": "us-east-1",
        "title": "EC2 Metrics"
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
          [ "AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "$RDS_ID" ],
          [ ".", "DatabaseConnections", ".", "." ],
          [ ".", "FreeableMemory", ".", "." ]
        ],
        "period": 300,
        "stat": "Average",
        "region": "us-east-1",
        "title": "RDS Metrics"
      }
    }
  ]
}
EOF

# Create dashboard
aws cloudwatch put-dashboard \
  --dashboard-name "TechHealth-$ENVIRONMENT" \
  --dashboard-body file://dashboard.json

# Create alarms
aws cloudwatch put-metric-alarm \
  --alarm-name "TechHealth-EC2-HighCPU-$ENVIRONMENT" \
  --alarm-description "EC2 High CPU Utilization" \
  --metric-name CPUUtilization \
  --namespace AWS/EC2 \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=InstanceId,Value=$EC2_ID \
  --evaluation-periods 2

aws cloudwatch put-metric-alarm \
  --alarm-name "TechHealth-RDS-HighCPU-$ENVIRONMENT" \
  --alarm-description "RDS High CPU Utilization" \
  --metric-name CPUUtilization \
  --namespace AWS/RDS \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=DBInstanceIdentifier,Value=$RDS_ID \
  --evaluation-periods 2

echo "✅ Monitoring setup completed"
echo "Dashboard: https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=TechHealth-$ENVIRONMENT"

# Cleanup
rm dashboard.json
```

## Best Practices

### Deployment Best Practices

1. **Always test in development first**
2. **Use version control for all configuration changes**
3. **Run security scans before production deployment**
4. **Monitor deployments in real-time**
5. **Have rollback procedures ready**
6. **Document all changes and decisions**

### Security Best Practices

1. **Use least privilege IAM policies**
2. **Enable CloudTrail for all environments**
3. **Rotate secrets regularly**
4. **Monitor for security events**
5. **Keep software updated**
6. **Regular security assessments**

### Cost Optimization

1. **Use appropriate instance sizes**
2. **Clean up test environments**
3. **Monitor costs regularly**
4. **Use reserved instances for production**
5. **Implement auto-scaling where appropriate**
6. **Regular cost reviews**

This deployment guide provides comprehensive instructions for safely deploying the TechHealth infrastructure across all environments while maintaining security, reliability, and cost-effectiveness.
