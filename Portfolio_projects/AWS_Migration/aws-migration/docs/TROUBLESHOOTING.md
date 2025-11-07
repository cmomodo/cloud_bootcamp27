# Troubleshooting Guide

## Common Issues and Solutions

### CDK and Deployment Issues

#### 1. CDK Bootstrap Not Found

**Error Message**:

```
Error: This stack uses assets, so the toolkit stack must be deployed to the environment
```

**Cause**: CDK toolkit stack not deployed to the target account/region.

**Solution**:

```bash
# Bootstrap the account/region
cdk bootstrap aws://ACCOUNT-NUMBER/REGION

# Verify bootstrap
aws cloudformation describe-stacks --stack-name CDKToolkit

# If bootstrap exists but outdated, update it
cdk bootstrap --force
```

**Prevention**:

- Always bootstrap new accounts/regions before first deployment
- Include bootstrap check in deployment scripts

#### 2. Permission Denied During Deployment

**Error Message**:

```
User: arn:aws:iam::123456789012:user/username is not authorized to perform: iam:CreateRole
```

**Cause**: Insufficient IAM permissions for CDK deployment.

**Required Permissions**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudformation:*",
        "iam:*",
        "ec2:*",
        "rds:*",
        "secretsmanager:*",
        "logs:*"
      ],
      "Resource": "*"
    }
  ]
}
```

**Solution**:

```bash
# Attach PowerUserAccess policy (for development)
aws iam attach-user-policy --user-name YOUR-USERNAME --policy-arn arn:aws:iam::aws:policy/PowerUserAccess

# For production, use more restrictive policies
aws iam attach-user-policy --user-name YOUR-USERNAME --policy-arn arn:aws:iam::aws:policy/CloudFormationFullAccess
```

#### 3. Stack Already Exists Error

**Error Message**:

```
Stack [TechHealthInfrastructureStack] already exists
```

**Cause**: Attempting to create a stack that already exists.

**Solutions**:

**Option A: Update existing stack**

```bash
npx cdk deploy --context environment=dev
```

**Option B: Delete and recreate**

```bash
npx cdk destroy --context environment=dev
npx cdk deploy --context environment=dev
```

**Option C: Use different stack name**

```bash
# Modify stack name in code or use context
npx cdk deploy --context environment=dev --context stackName=TechHealthInfrastructureStack-v2
```

#### 4. Resource Limit Exceeded

**Error Message**:

```
The maximum number of VPCs has been reached
```

**Cause**: AWS service limits exceeded.

**Solution**:

```bash
# Check current limits
aws service-quotas get-service-quota --service-code ec2 --quota-code L-F678F1CE

# Request limit increase
aws service-quotas request-service-quota-increase --service-code ec2 --quota-code L-F678F1CE --desired-value 10

# Clean up unused resources
aws ec2 describe-vpcs --query 'Vpcs[?State==`available`]'
```

### Network Connectivity Issues

#### 1. EC2 Cannot Connect to RDS

**Symptoms**:

- Connection timeout when connecting to database
- "Can't connect to MySQL server" error

**Diagnostic Steps**:

```bash
# 1. Check security group rules
aws ec2 describe-security-groups --group-names TechHealth-RDS-SG

# 2. Verify RDS endpoint
aws rds describe-db-instances --db-instance-identifier techhealth-database

# 3. Test network connectivity from EC2
ssh -i keypair.pem ec2-user@EC2-PUBLIC-IP
telnet RDS-ENDPOINT 3306

# 4. Check route tables
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=VPC-ID"
```

**Common Causes and Solutions**:

**Cause A: Security Group Misconfiguration**

```bash
# Check if RDS security group allows EC2 security group
aws ec2 describe-security-groups --group-ids sg-rds-id --query 'SecurityGroups[0].IpPermissions'

# Fix: Update RDS security group
aws ec2 authorize-security-group-ingress \
  --group-id sg-rds-id \
  --protocol tcp \
  --port 3306 \
  --source-group sg-ec2-id
```

**Cause B: RDS in Wrong Subnet**

```bash
# Check RDS subnet group
aws rds describe-db-subnet-groups --db-subnet-group-name techhealth-db-subnet-group

# Verify subnets are private
aws ec2 describe-subnets --subnet-ids subnet-xxx subnet-yyy
```

**Cause C: Network ACL Blocking Traffic**

```bash
# Check Network ACLs
aws ec2 describe-network-acls --filters "Name=vpc-id,Values=VPC-ID"

# Default NACLs should allow all traffic
# Custom NACLs may need specific rules
```

#### 2. Cannot SSH to EC2 Instance

**Symptoms**:

- Connection timeout on SSH
- "Permission denied (publickey)" error

**Diagnostic Steps**:

```bash
# 1. Check instance status
aws ec2 describe-instances --instance-ids i-1234567890abcdef0

# 2. Verify security group
aws ec2 describe-security-groups --group-ids sg-ec2-id

# 3. Check key pair
aws ec2 describe-key-pairs --key-names techhealth-keypair

# 4. Test connectivity
telnet EC2-PUBLIC-IP 22
```

**Solutions**:

**Issue A: Security Group Not Allowing SSH**

```bash
# Add SSH rule to security group
aws ec2 authorize-security-group-ingress \
  --group-id sg-ec2-id \
  --protocol tcp \
  --port 22 \
  --cidr YOUR-IP/32
```

**Issue B: Wrong Key Pair**

```bash
# Verify key pair name matches
aws ec2 describe-instances --instance-ids i-xxx --query 'Reservations[0].Instances[0].KeyName'

# Create new key pair if needed
aws ec2 create-key-pair --key-name techhealth-keypair --query 'KeyMaterial' --output text > keypair.pem
chmod 400 keypair.pem
```

**Issue C: Instance Not in Public Subnet**

```bash
# Check if instance has public IP
aws ec2 describe-instances --instance-ids i-xxx --query 'Reservations[0].Instances[0].PublicIpAddress'

# Check subnet configuration
aws ec2 describe-subnets --subnet-ids subnet-xxx --query 'Subnets[0].MapPublicIpOnLaunch'
```

#### 3. Internet Gateway Issues

**Symptoms**:

- EC2 instances cannot reach internet
- Package installation fails
- Cannot download updates

**Diagnostic Steps**:

```bash
# 1. Check Internet Gateway attachment
aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=VPC-ID"

# 2. Verify route table
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=VPC-ID"

# 3. Test from EC2 instance
ssh -i keypair.pem ec2-user@EC2-IP
ping 8.8.8.8
curl -I http://google.com
```

**Solutions**:

**Issue A: No Internet Gateway**

```bash
# Create and attach Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id VPC-ID
```

**Issue B: Missing Route to Internet Gateway**

```bash
# Add route to Internet Gateway
aws ec2 create-route --route-table-id rtb-xxx --destination-cidr-block 0.0.0.0/0 --gateway-id igw-xxx
```

### Database Issues

#### 1. RDS Instance Creation Failed

**Error Message**:

```
DB subnet group doesn't meet availability zone coverage requirement
```

**Cause**: DB subnet group doesn't span multiple AZs.

**Solution**:

```bash
# Check current subnet group
aws rds describe-db-subnet-groups --db-subnet-group-name techhealth-db-subnet-group

# Verify subnets are in different AZs
aws ec2 describe-subnets --subnet-ids subnet-xxx subnet-yyy --query 'Subnets[*].[SubnetId,AvailabilityZone]'

# Create new subnet group with proper AZ coverage
aws rds create-db-subnet-group \
  --db-subnet-group-name techhealth-db-subnet-group-v2 \
  --db-subnet-group-description "TechHealth DB Subnet Group" \
  --subnet-ids subnet-private-a subnet-private-b
```

#### 2. Database Connection Timeout

**Symptoms**:

- Application cannot connect to database
- Long connection delays

**Diagnostic Steps**:

```bash
# 1. Check RDS status
aws rds describe-db-instances --db-instance-identifier techhealth-database

# 2. Test connection from EC2
ssh -i keypair.pem ec2-user@EC2-IP
mysql -h RDS-ENDPOINT -u admin -p -e "SELECT 1"

# 3. Check connection parameters
mysql -h RDS-ENDPOINT -u admin -p -e "SHOW VARIABLES LIKE 'max_connections'"
```

**Solutions**:

**Issue A: Connection Pool Exhaustion**

```sql
-- Check current connections
SHOW PROCESSLIST;

-- Check max connections
SHOW VARIABLES LIKE 'max_connections';

-- Kill long-running queries
KILL CONNECTION_ID;
```

**Issue B: Parameter Group Issues**

```bash
# Check parameter group
aws rds describe-db-parameters --db-parameter-group-name techhealth-db-params

# Modify parameters if needed
aws rds modify-db-parameter-group \
  --db-parameter-group-name techhealth-db-params \
  --parameters ParameterName=max_connections,ParameterValue=200,ApplyMethod=immediate
```

#### 3. Database Performance Issues

**Symptoms**:

- Slow query response times
- High CPU utilization
- Connection delays

**Diagnostic Steps**:

```bash
# 1. Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=techhealth-database \
  --start-time 2023-01-01T00:00:00Z \
  --end-time 2023-01-01T23:59:59Z \
  --period 3600 \
  --statistics Average

# 2. Enable Performance Insights
aws rds modify-db-instance \
  --db-instance-identifier techhealth-database \
  --enable-performance-insights \
  --performance-insights-retention-period 7
```

**Solutions**:

**Issue A: Insufficient Resources**

```bash
# Scale up instance class
aws rds modify-db-instance \
  --db-instance-identifier techhealth-database \
  --db-instance-class db.t3.small \
  --apply-immediately
```

**Issue B: Query Optimization**

```sql
-- Enable slow query log
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 2;

-- Analyze slow queries
SELECT * FROM mysql.slow_log ORDER BY start_time DESC LIMIT 10;

-- Add indexes for common queries
CREATE INDEX idx_user_email ON users(email);
```

### Security and Access Issues

#### 1. Secrets Manager Access Denied

**Error Message**:

```
User is not authorized to perform: secretsmanager:GetSecretValue
```

**Cause**: EC2 instance role lacks Secrets Manager permissions.

**Solution**:

```bash
# Check current role policies
aws iam list-attached-role-policies --role-name TechHealth-EC2-Role

# Attach Secrets Manager policy
aws iam attach-role-policy \
  --role-name TechHealth-EC2-Role \
  --policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite

# Or create custom policy
cat > secrets-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:*:*:secret:TechHealth-DB-Credentials-*"
    }
  ]
}
EOF

aws iam create-policy --policy-name TechHealth-Secrets-Policy --policy-document file://secrets-policy.json
```

#### 2. CloudWatch Logs Access Issues

**Error Message**:

```
Could not deliver test message to specified Destination
```

**Cause**: Missing CloudWatch Logs permissions.

**Solution**:

```bash
# Create CloudWatch Logs policy
cat > cloudwatch-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    }
  ]
}
EOF

aws iam create-policy --policy-name TechHealth-CloudWatch-Policy --policy-document file://cloudwatch-policy.json
aws iam attach-role-policy --role-name TechHealth-EC2-Role --policy-arn arn:aws:iam::ACCOUNT:policy/TechHealth-CloudWatch-Policy
```

### Cost and Billing Issues

#### 1. Unexpected Charges

**Common Causes**:

- Resources not properly cleaned up
- Data transfer charges
- EBS snapshots accumulating

**Investigation Steps**:

```bash
# Check running resources
aws ec2 describe-instances --query 'Reservations[*].Instances[?State.Name==`running`]'
aws rds describe-db-instances --query 'DBInstances[?DBInstanceStatus==`available`]'

# Check EBS volumes
aws ec2 describe-volumes --query 'Volumes[?State==`available`]'

# Check snapshots
aws ec2 describe-snapshots --owner-ids self --query 'Snapshots[*].[SnapshotId,StartTime,VolumeSize]'

# Review billing
aws ce get-cost-and-usage \
  --time-period Start=2023-01-01,End=2023-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE
```

**Cleanup Commands**:

```bash
# Stop all EC2 instances
aws ec2 stop-instances --instance-ids $(aws ec2 describe-instances --query 'Reservations[*].Instances[?State.Name==`running`].InstanceId' --output text)

# Delete old snapshots (be careful!)
aws ec2 describe-snapshots --owner-ids self --query 'Snapshots[?StartTime<=`2023-01-01`].SnapshotId' --output text | xargs -n1 aws ec2 delete-snapshot --snapshot-id

# Destroy CDK stack
npx cdk destroy --context environment=dev
```

#### 2. Free Tier Exceeded

**Symptoms**:

- Charges for t2.micro instances
- EBS storage charges

**Solutions**:

```bash
# Check free tier usage
aws support describe-trusted-advisor-checks --language en --query 'checks[?name==`Service Limits`]'

# Monitor usage with CloudWatch
aws cloudwatch put-metric-alarm \
  --alarm-name "EC2-Instance-Hours" \
  --alarm-description "Monitor EC2 free tier usage" \
  --metric-name "InstanceHours" \
  --namespace "AWS/EC2" \
  --statistic Sum \
  --period 86400 \
  --threshold 750 \
  --comparison-operator GreaterThanThreshold
```

## Diagnostic Commands

### System Health Checks

```bash
#!/bin/bash
# health-check.sh - Comprehensive system health check

echo "=== CDK Health Check ==="
cdk --version
echo "CDK Bootstrap Status:"
aws cloudformation describe-stacks --stack-name CDKToolkit --query 'Stacks[0].StackStatus' 2>/dev/null || echo "Not bootstrapped"

echo -e "\n=== AWS Credentials ==="
aws sts get-caller-identity

echo -e "\n=== VPC Status ==="
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Project,Values=TechHealth" --query 'Vpcs[0].VpcId' --output text)
echo "VPC ID: $VPC_ID"
aws ec2 describe-vpcs --vpc-ids $VPC_ID --query 'Vpcs[0].State'

echo -e "\n=== Subnet Status ==="
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock,State]' --output table

echo -e "\n=== EC2 Instances ==="
aws ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PublicIpAddress,PrivateIpAddress]' --output table

echo -e "\n=== RDS Status ==="
aws rds describe-db-instances --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus,Endpoint.Address]' --output table

echo -e "\n=== Security Groups ==="
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[*].[GroupId,GroupName,Description]' --output table
```

### Network Connectivity Test

```bash
#!/bin/bash
# connectivity-test.sh - Test network connectivity

EC2_IP=$(aws ec2 describe-instances --filters "Name=tag:Project,Values=TechHealth" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
RDS_ENDPOINT=$(aws rds describe-db-instances --query 'DBInstances[0].Endpoint.Address' --output text)

echo "Testing connectivity to EC2: $EC2_IP"
ping -c 3 $EC2_IP

echo -e "\nTesting SSH connectivity:"
timeout 10 ssh -i keypair.pem -o ConnectTimeout=5 ec2-user@$EC2_IP "echo 'SSH connection successful'"

echo -e "\nTesting database connectivity from EC2:"
ssh -i keypair.pem ec2-user@$EC2_IP "timeout 10 mysql -h $RDS_ENDPOINT -u admin -p'password' -e 'SELECT 1' 2>/dev/null && echo 'Database connection successful' || echo 'Database connection failed'"
```

### Performance Monitoring

```bash
#!/bin/bash
# performance-check.sh - Check system performance

echo "=== EC2 Performance ==="
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=$(aws ec2 describe-instances --filters "Name=tag:Project,Values=TechHealth" --query 'Reservations[0].Instances[0].InstanceId' --output text) \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average \
  --query 'Datapoints[*].[Timestamp,Average]' \
  --output table

echo -e "\n=== RDS Performance ==="
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=$(aws rds describe-db-instances --query 'DBInstances[0].DBInstanceIdentifier' --output text) \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average \
  --query 'Datapoints[*].[Timestamp,Average]' \
  --output table
```

## Emergency Procedures

### Complete Infrastructure Recovery

```bash
#!/bin/bash
# emergency-recovery.sh - Complete infrastructure recovery

echo "Starting emergency recovery procedure..."

# 1. Backup current state
echo "Creating backup of current configuration..."
npx cdk synth > backup-$(date +%Y%m%d-%H%M%S).json

# 2. Destroy corrupted infrastructure
echo "Destroying corrupted infrastructure..."
npx cdk destroy --force --context environment=dev

# 3. Wait for cleanup
echo "Waiting for cleanup to complete..."
sleep 60

# 4. Redeploy infrastructure
echo "Redeploying infrastructure..."
npx cdk deploy --context environment=dev --require-approval never

# 5. Verify deployment
echo "Verifying deployment..."
./scripts/post-deployment-verification.sh

echo "Emergency recovery completed."
```

### Database Emergency Restore

```bash
#!/bin/bash
# db-emergency-restore.sh - Emergency database restore

DB_INSTANCE_ID="techhealth-database"
BACKUP_IDENTIFIER="techhealth-database-$(date +%Y%m%d-%H%M%S)"

echo "Starting database emergency restore..."

# 1. Create final backup
echo "Creating final backup..."
aws rds create-db-snapshot \
  --db-instance-identifier $DB_INSTANCE_ID \
  --db-snapshot-identifier $BACKUP_IDENTIFIER

# 2. Wait for backup completion
echo "Waiting for backup to complete..."
aws rds wait db-snapshot-completed --db-snapshot-identifier $BACKUP_IDENTIFIER

# 3. Get latest automated backup
LATEST_BACKUP=$(aws rds describe-db-snapshots \
  --db-instance-identifier $DB_INSTANCE_ID \
  --snapshot-type automated \
  --query 'DBSnapshots | sort_by(@, &SnapshotCreateTime) | [-1].DBSnapshotIdentifier' \
  --output text)

# 4. Restore from backup
echo "Restoring from backup: $LATEST_BACKUP"
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier "${DB_INSTANCE_ID}-restored" \
  --db-snapshot-identifier $LATEST_BACKUP

echo "Database restore initiated. Monitor progress with:"
echo "aws rds describe-db-instances --db-instance-identifier ${DB_INSTANCE_ID}-restored"
```

## Support Escalation

### When to Escalate

1. **Infrastructure completely down** for more than 30 minutes
2. **Data loss** or corruption detected
3. **Security breach** suspected
4. **AWS service outage** affecting operations
5. **Cost anomalies** exceeding 200% of normal

### Escalation Contacts

1. **AWS Support**: Create support case in AWS Console
2. **Internal DevOps Team**: [Contact information]
3. **Security Team**: [Contact information for security issues]
4. **Management**: [Contact information for business impact]

### Information to Gather

Before escalating, collect:

```bash
# System information
aws sts get-caller-identity > escalation-info.txt
aws cloudformation describe-stacks --stack-name TechHealthInfrastructureStack >> escalation-info.txt
aws ec2 describe-instances --filters "Name=tag:Project,Values=TechHealth" >> escalation-info.txt
aws rds describe-db-instances >> escalation-info.txt

# Recent CloudTrail events
aws logs filter-log-events \
  --log-group-name CloudTrail/TechHealthAuditTrail \
  --start-time $(date -d '1 hour ago' +%s)000 \
  >> escalation-info.txt

# Error logs
aws logs filter-log-events \
  --log-group-name /aws/ec2/techhealth \
  --filter-pattern "ERROR" \
  --start-time $(date -d '1 hour ago' +%s)000 \
  >> escalation-info.txt
```
