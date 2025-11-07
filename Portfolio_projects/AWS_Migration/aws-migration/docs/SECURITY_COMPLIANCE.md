# Security and Compliance Documentation

## Overview

This document outlines the security implementation and HIPAA compliance procedures for the TechHealth infrastructure modernization project. The infrastructure is designed to meet healthcare industry security standards while maintaining operational efficiency and cost-effectiveness.

## Table of Contents

- [HIPAA Compliance Framework](#hipaa-compliance-framework)
- [Security Architecture](#security-architecture)
- [Access Controls](#access-controls)
- [Data Protection](#data-protection)
- [Monitoring and Auditing](#monitoring-and-auditing)
- [Incident Response](#incident-response)
- [Compliance Validation](#compliance-validation)
- [Security Procedures](#security-procedures)

## HIPAA Compliance Framework

### Administrative Safeguards

#### Security Officer and Workforce Training

**Implementation**:

- Designated Security Officer responsible for HIPAA compliance
- Regular security awareness training for all personnel
- Access management procedures and documentation
- Incident response procedures and contact information

**AWS Services Used**:

- AWS CloudTrail for audit logging
- AWS Config for compliance monitoring
- AWS Systems Manager for secure configuration management

**Compliance Checklist**:

```bash
# Verify CloudTrail is enabled
aws cloudtrail describe-trails --query 'trailList[?IsMultiRegionTrail==`true`]'

# Check Config rules for compliance
aws configservice describe-compliance-by-config-rule --config-rule-names encrypted-volumes

# Verify IAM policies follow least privilege
aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::ACCOUNT:role/TechHealth-EC2-Role --action-names s3:GetObject --resource-arns arn:aws:s3:::bucket/*
```

#### Information System Activity Review

**Implementation**:

- Automated log collection and analysis
- Regular review of access logs and system activities
- Automated alerting for suspicious activities
- Quarterly access reviews and audits

**Monitoring Setup**:

```bash
# Enable VPC Flow Logs
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids vpc-xxxxxxxxx \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name VPCFlowLogs

# Create CloudWatch alarm for failed login attempts
aws cloudwatch put-metric-alarm \
  --alarm-name "HIPAA-Failed-Logins" \
  --alarm-description "Monitor failed login attempts" \
  --metric-name FailedLoginAttempts \
  --namespace Custom/Security \
  --statistic Sum \
  --period 300 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold
```

#### Assigned Security Responsibilities

**Role-Based Access Control**:

- **Security Administrator**: Full access to security configurations
- **Database Administrator**: Limited access to RDS and data management
- **System Administrator**: Infrastructure management with restricted data access
- **Developer**: Development environment access only

**IAM Policy Example**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DatabaseAdminAccess",
      "Effect": "Allow",
      "Action": [
        "rds:Describe*",
        "rds:ModifyDBInstance",
        "rds:CreateDBSnapshot",
        "rds:RestoreDBInstanceFromDBSnapshot"
      ],
      "Resource": "arn:aws:rds:*:*:db:techhealth-*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "us-east-1"
        }
      }
    }
  ]
}
```

#### Information Access Management

**Implementation**:

- Unique user identification for each individual
- Automatic logoff after 15 minutes of inactivity
- Encryption of data in motion and at rest
- Regular access reviews and deprovisioning procedures

### Physical Safeguards

#### Facility Access Controls

**AWS Responsibility**:

- Physical security of AWS data centers
- Environmental controls and monitoring
- Hardware security and disposal
- Biometric access controls

**Customer Responsibility**:

- Secure workstation configuration
- VPN access for remote workers
- Physical security of development environments

#### Workstation Use

**Security Configuration**:

```bash
# Configure secure SSH access
cat > ~/.ssh/config << EOF
Host techhealth-*
    StrictHostKeyChecking yes
    UserKnownHostsFile ~/.ssh/known_hosts
    IdentitiesOnly yes
    ServerAliveInterval 300
    ServerAliveCountMax 2
EOF

# Set proper permissions
chmod 600 ~/.ssh/config
```

#### Device and Media Controls

**Implementation**:

- Encrypted storage for all development devices
- Secure disposal procedures for hardware
- Media sanitization before disposal
- Inventory tracking for all devices

### Technical Safeguards

#### Access Control

**Unique User Identification**:

```bash
# Create individual IAM users (not shared accounts)
aws iam create-user --user-name john.doe@techhealth.com
aws iam create-access-key --user-name john.doe@techhealth.com

# Attach appropriate policies
aws iam attach-user-policy \
  --user-name john.doe@techhealth.com \
  --policy-arn arn:aws:iam::ACCOUNT:policy/TechHealth-Developer-Policy
```

**Automatic Logoff**:

```bash
# Configure session timeout in EC2 user data
#!/bin/bash
echo "TMOUT=900" >> /etc/profile
echo "export TMOUT" >> /etc/profile

# Configure MySQL timeout
mysql -e "SET GLOBAL interactive_timeout=900;"
mysql -e "SET GLOBAL wait_timeout=900;"
```

#### Audit Controls

**Comprehensive Logging**:

```bash
# Enable CloudTrail for all API calls
aws cloudtrail create-trail \
  --name TechHealth-Audit-Trail \
  --s3-bucket-name techhealth-audit-logs \
  --include-global-service-events \
  --is-multi-region-trail \
  --enable-log-file-validation

# Enable VPC Flow Logs
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids vpc-xxxxxxxxx \
  --traffic-type ALL \
  --log-destination-type s3 \
  --log-destination arn:aws:s3:::techhealth-vpc-logs
```

#### Integrity

**Data Integrity Controls**:

```bash
# Enable RDS backup with point-in-time recovery
aws rds modify-db-instance \
  --db-instance-identifier techhealth-database \
  --backup-retention-period 30 \
  --delete-automated-backups false

# Enable EBS encryption
aws ec2 modify-ebs-default-kms-key-id --kms-key-id alias/aws/ebs
aws ec2 enable-ebs-encryption-by-default
```

#### Transmission Security

**Encryption in Transit**:

```bash
# Configure SSL/TLS for RDS
aws rds modify-db-instance \
  --db-instance-identifier techhealth-database \
  --ca-certificate-identifier rds-ca-2019

# Force SSL connections
mysql -e "GRANT USAGE ON *.* TO 'app_user'@'%' REQUIRE SSL;"
```

## Security Architecture

### Network Security

#### VPC Security Design

```mermaid
graph TB
    subgraph "Internet"
        Internet[Internet Traffic]
    end

    subgraph "AWS VPC (10.0.0.0/16)"
        subgraph "Public Subnets"
            IGW[Internet Gateway]
            NACL1[Network ACL<br/>Public Subnets]
            PubSub1[Public Subnet A<br/>10.0.1.0/24]
            PubSub2[Public Subnet B<br/>10.0.2.0/24]
            EC2_1[EC2 Instance A]
            EC2_2[EC2 Instance B]
        end

        subgraph "Private Subnets"
            NACL2[Network ACL<br/>Private Subnets]
            PrivSub1[Private Subnet A<br/>10.0.3.0/24]
            PrivSub2[Private Subnet B<br/>10.0.4.0/24]
            RDS[(RDS MySQL<br/>Encrypted)]
        end

        subgraph "Security Groups"
            SG_EC2[EC2 Security Group<br/>Port 22, 80, 443]
            SG_RDS[RDS Security Group<br/>Port 3306]
        end
    end

    Internet --> IGW
    IGW --> NACL1
    NACL1 --> PubSub1
    NACL1 --> PubSub2
    PubSub1 --> EC2_1
    PubSub2 --> EC2_2

    EC2_1 --> SG_EC2
    EC2_2 --> SG_EC2

    EC2_1 -.->|Encrypted Connection| NACL2
    EC2_2 -.->|Encrypted Connection| NACL2
    NACL2 --> PrivSub1
    NACL2 --> PrivSub2
    PrivSub1 --> RDS
    PrivSub2 --> RDS
    RDS --> SG_RDS
```

#### Security Group Configuration

**EC2 Security Group Rules**:

```bash
# Create EC2 security group
aws ec2 create-security-group \
  --group-name TechHealth-EC2-SG \
  --description "TechHealth EC2 Security Group" \
  --vpc-id vpc-xxxxxxxxx

# Allow SSH from specific IP ranges only
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxxxxxx \
  --protocol tcp \
  --port 22 \
  --cidr 203.0.113.0/24  # Replace with actual admin IP range

# Allow HTTP/HTTPS from internet
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxxxxxx \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxxxxxx \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0
```

**RDS Security Group Rules**:

```bash
# Create RDS security group
aws ec2 create-security-group \
  --group-name TechHealth-RDS-SG \
  --description "TechHealth RDS Security Group" \
  --vpc-id vpc-xxxxxxxxx

# Allow MySQL access only from EC2 security group
aws ec2 authorize-security-group-ingress \
  --group-id sg-yyyyyyyyy \
  --protocol tcp \
  --port 3306 \
  --source-group sg-xxxxxxxxx
```

#### Network Access Control Lists (NACLs)

**Public Subnet NACL**:

```bash
# Create custom NACL for public subnets
NACL_ID=$(aws ec2 create-network-acl --vpc-id vpc-xxxxxxxxx --query 'NetworkAcl.NetworkAclId' --output text)

# Allow inbound HTTP/HTTPS
aws ec2 create-network-acl-entry \
  --network-acl-id $NACL_ID \
  --rule-number 100 \
  --protocol tcp \
  --port-range From=80,To=80 \
  --cidr-block 0.0.0.0/0 \
  --rule-action allow

aws ec2 create-network-acl-entry \
  --network-acl-id $NACL_ID \
  --rule-number 110 \
  --protocol tcp \
  --port-range From=443,To=443 \
  --cidr-block 0.0.0.0/0 \
  --rule-action allow

# Allow SSH from specific ranges
aws ec2 create-network-acl-entry \
  --network-acl-id $NACL_ID \
  --rule-number 120 \
  --protocol tcp \
  --port-range From=22,To=22 \
  --cidr-block 203.0.113.0/24 \
  --rule-action allow
```

### Identity and Access Management

#### IAM Roles and Policies

**EC2 Instance Role**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SecretsManagerAccess",
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue"],
      "Resource": "arn:aws:secretsmanager:*:*:secret:TechHealth-DB-Credentials-*"
    },
    {
      "Sid": "CloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ],
      "Resource": "arn:aws:logs:*:*:log-group:/aws/ec2/techhealth*"
    },
    {
      "Sid": "CloudWatchMetrics",
      "Effect": "Allow",
      "Action": ["cloudwatch:PutMetricData"],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "cloudwatch:namespace": "TechHealth/Application"
        }
      }
    }
  ]
}
```

#### Multi-Factor Authentication

**MFA Enforcement Policy**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowViewAccountInfo",
      "Effect": "Allow",
      "Action": ["iam:GetAccountPasswordPolicy", "iam:ListVirtualMFADevices"],
      "Resource": "*"
    },
    {
      "Sid": "AllowManageOwnPasswords",
      "Effect": "Allow",
      "Action": ["iam:ChangePassword", "iam:GetUser"],
      "Resource": "arn:aws:iam::*:user/${aws:username}"
    },
    {
      "Sid": "AllowManageOwnMFA",
      "Effect": "Allow",
      "Action": [
        "iam:CreateVirtualMFADevice",
        "iam:DeleteVirtualMFADevice",
        "iam:EnableMFADevice",
        "iam:ListMFADevices",
        "iam:ResyncMFADevice"
      ],
      "Resource": [
        "arn:aws:iam::*:mfa/${aws:username}",
        "arn:aws:iam::*:user/${aws:username}"
      ]
    },
    {
      "Sid": "DenyAllExceptUnlessSignedInWithMFA",
      "Effect": "Deny",
      "NotAction": [
        "iam:CreateVirtualMFADevice",
        "iam:EnableMFADevice",
        "iam:GetUser",
        "iam:ListMFADevices",
        "iam:ListVirtualMFADevices",
        "iam:ResyncMFADevice",
        "sts:GetSessionToken"
      ],
      "Resource": "*",
      "Condition": {
        "BoolIfExists": {
          "aws:MultiFactorAuthPresent": "false"
        }
      }
    }
  ]
}
```

## Data Protection

### Encryption at Rest

#### RDS Encryption

```bash
# Enable encryption for new RDS instance
aws rds create-db-instance \
  --db-instance-identifier techhealth-database \
  --db-instance-class db.t3.micro \
  --engine mysql \
  --master-username admin \
  --master-user-password $(aws secretsmanager get-secret-value --secret-id TechHealth-DB-Credentials --query SecretString --output text | jq -r .password) \
  --allocated-storage 20 \
  --storage-encrypted \
  --kms-key-id alias/aws/rds \
  --vpc-security-group-ids sg-xxxxxxxxx \
  --db-subnet-group-name techhealth-db-subnet-group

# Verify encryption status
aws rds describe-db-instances \
  --db-instance-identifier techhealth-database \
  --query 'DBInstances[0].StorageEncrypted'
```

#### EBS Encryption

```bash
# Enable EBS encryption by default
aws ec2 enable-ebs-encryption-by-default

# Create encrypted EBS volume
aws ec2 create-volume \
  --size 20 \
  --volume-type gp3 \
  --availability-zone us-east-1a \
  --encrypted \
  --kms-key-id alias/aws/ebs
```

#### Secrets Manager

```bash
# Create encrypted secret for database credentials
aws secretsmanager create-secret \
  --name TechHealth-DB-Credentials \
  --description "Database credentials for TechHealth application" \
  --secret-string '{"username":"admin","password":"'$(openssl rand -base64 32)'"}' \
  --kms-key-id alias/aws/secretsmanager

# Enable automatic rotation
aws secretsmanager rotate-secret \
  --secret-id TechHealth-DB-Credentials \
  --rotation-lambda-arn arn:aws:lambda:us-east-1:ACCOUNT:function:SecretsManagerRDSMySQLRotationSingleUser \
  --rotation-rules AutomaticallyAfterDays=30
```

### Encryption in Transit

#### SSL/TLS Configuration

**RDS SSL Configuration**:

```sql
-- Force SSL connections
ALTER USER 'app_user'@'%' REQUIRE SSL;

-- Verify SSL status
SHOW STATUS LIKE 'Ssl_cipher';
SHOW VARIABLES LIKE '%ssl%';
```

**Application SSL Configuration**:

```bash
# Configure Apache/Nginx with SSL
# Generate SSL certificate (use AWS Certificate Manager in production)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/techhealth.key \
  -out /etc/ssl/certs/techhealth.crt \
  -subj "/C=US/ST=State/L=City/O=TechHealth/CN=techhealth.com"

# Configure Apache SSL
cat > /etc/httpd/conf.d/ssl.conf << EOF
<VirtualHost *:443>
    ServerName techhealth.com
    DocumentRoot /var/www/html

    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/techhealth.crt
    SSLCertificateKeyFile /etc/ssl/private/techhealth.key

    # Security headers
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
    Header always set X-Content-Type-Options nosniff
    Header always set X-Frame-Options DENY
    Header always set X-XSS-Protection "1; mode=block"
</VirtualHost>
EOF
```

### Data Backup and Recovery

#### Automated Backup Strategy

```bash
# Configure RDS automated backups
aws rds modify-db-instance \
  --db-instance-identifier techhealth-database \
  --backup-retention-period 30 \
  --preferred-backup-window "03:00-04:00" \
  --preferred-maintenance-window "sun:04:00-sun:05:00" \
  --delete-automated-backups false

# Create manual snapshot
aws rds create-db-snapshot \
  --db-instance-identifier techhealth-database \
  --db-snapshot-identifier techhealth-manual-$(date +%Y%m%d-%H%M%S)

# Cross-region backup replication
aws rds copy-db-snapshot \
  --source-db-snapshot-identifier arn:aws:rds:us-east-1:ACCOUNT:snapshot:techhealth-manual-20231201-120000 \
  --target-db-snapshot-identifier techhealth-backup-west \
  --source-region us-east-1 \
  --target-region us-west-2 \
  --kms-key-id alias/aws/rds
```

#### Recovery Procedures

```bash
#!/bin/bash
# disaster-recovery.sh - Disaster recovery procedures

echo "=== TechHealth Disaster Recovery ==="

# 1. Assess damage
echo "1. Assessing current infrastructure status..."
aws cloudformation describe-stacks --stack-name TechHealthInfrastructureStack

# 2. Identify latest backup
echo "2. Identifying latest backup..."
LATEST_SNAPSHOT=$(aws rds describe-db-snapshots \
  --db-instance-identifier techhealth-database \
  --snapshot-type automated \
  --query 'DBSnapshots | sort_by(@, &SnapshotCreateTime) | [-1].DBSnapshotIdentifier' \
  --output text)

echo "Latest snapshot: $LATEST_SNAPSHOT"

# 3. Restore database
echo "3. Restoring database from backup..."
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier techhealth-database-restored \
  --db-snapshot-identifier $LATEST_SNAPSHOT \
  --db-instance-class db.t3.micro \
  --vpc-security-group-ids sg-xxxxxxxxx \
  --db-subnet-group-name techhealth-db-subnet-group

# 4. Update application configuration
echo "4. Updating application configuration..."
NEW_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier techhealth-database-restored \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

echo "New database endpoint: $NEW_ENDPOINT"

# 5. Verify recovery
echo "5. Verifying recovery..."
mysql -h $NEW_ENDPOINT -u admin -p -e "SELECT COUNT(*) FROM information_schema.tables;"

echo "Disaster recovery completed"
```

## Monitoring and Auditing

### CloudTrail Configuration

```bash
# Create CloudTrail for comprehensive auditing
aws cloudtrail create-trail \
  --name TechHealth-Audit-Trail \
  --s3-bucket-name techhealth-audit-logs-$(aws sts get-caller-identity --query Account --output text) \
  --include-global-service-events \
  --is-multi-region-trail \
  --enable-log-file-validation \
  --event-selectors '[
    {
      "ReadWriteType": "All",
      "IncludeManagementEvents": true,
      "DataResources": [
        {
          "Type": "AWS::S3::Object",
          "Values": ["arn:aws:s3:::techhealth-*/*"]
        }
      ]
    }
  ]'

# Start logging
aws cloudtrail start-logging --name TechHealth-Audit-Trail
```

### Security Monitoring

#### CloudWatch Security Alarms

```bash
# Failed login attempts
aws cloudwatch put-metric-alarm \
  --alarm-name "TechHealth-Failed-Logins" \
  --alarm-description "Multiple failed login attempts detected" \
  --metric-name FailedLoginAttempts \
  --namespace AWS/CloudTrailMetrics \
  --statistic Sum \
  --period 300 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1 \
  --alarm-actions arn:aws:sns:us-east-1:ACCOUNT:security-alerts

# Root account usage
aws cloudwatch put-metric-alarm \
  --alarm-name "TechHealth-Root-Usage" \
  --alarm-description "Root account usage detected" \
  --metric-name RootUsage \
  --namespace AWS/CloudTrailMetrics \
  --statistic Sum \
  --period 60 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --evaluation-periods 1 \
  --alarm-actions arn:aws:sns:us-east-1:ACCOUNT:security-alerts

# Unauthorized API calls
aws cloudwatch put-metric-alarm \
  --alarm-name "TechHealth-Unauthorized-API" \
  --alarm-description "Unauthorized API calls detected" \
  --metric-name UnauthorizedAPICalls \
  --namespace AWS/CloudTrailMetrics \
  --statistic Sum \
  --period 300 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1 \
  --alarm-actions arn:aws:sns:us-east-1:ACCOUNT:security-alerts
```

#### VPC Flow Logs Analysis

```bash
# Create VPC Flow Logs
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids vpc-xxxxxxxxx \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name VPCFlowLogs \
  --deliver-logs-permission-arn arn:aws:iam::ACCOUNT:role/flowlogsRole

# Query suspicious traffic patterns
aws logs filter-log-events \
  --log-group-name VPCFlowLogs \
  --filter-pattern "[timestamp, account, eni, source, destination, srcport, destport=\"22\", protocol=\"6\", packets, bytes, windowstart, windowend, action=\"REJECT\"]" \
  --start-time $(date -d '1 hour ago' +%s)000
```

### Compliance Reporting

#### Automated Compliance Checks

```bash
#!/bin/bash
# compliance-check.sh - Automated HIPAA compliance validation

echo "=== HIPAA Compliance Check ==="

# Check encryption at rest
echo "1. Checking encryption at rest..."
RDS_ENCRYPTED=$(aws rds describe-db-instances --query 'DBInstances[0].StorageEncrypted')
EBS_ENCRYPTED=$(aws ec2 get-ebs-encryption-by-default --query 'EbsEncryptionByDefault')

if [ "$RDS_ENCRYPTED" = "true" ] && [ "$EBS_ENCRYPTED" = "true" ]; then
    echo "✅ Encryption at rest: COMPLIANT"
else
    echo "❌ Encryption at rest: NON-COMPLIANT"
fi

# Check CloudTrail logging
echo "2. Checking audit logging..."
CLOUDTRAIL_STATUS=$(aws cloudtrail get-trail-status --name TechHealth-Audit-Trail --query 'IsLogging')
if [ "$CLOUDTRAIL_STATUS" = "true" ]; then
    echo "✅ Audit logging: COMPLIANT"
else
    echo "❌ Audit logging: NON-COMPLIANT"
fi

# Check access controls
echo "3. Checking access controls..."
SECURITY_GROUPS=$(aws ec2 describe-security-groups --query 'SecurityGroups[?IpPermissions[?IpRanges[?CidrIp==`0.0.0.0/0`] && FromPort==`22`]]')
if [ "$SECURITY_GROUPS" = "[]" ]; then
    echo "✅ SSH access controls: COMPLIANT"
else
    echo "❌ SSH access controls: NON-COMPLIANT (SSH open to 0.0.0.0/0)"
fi

# Check backup retention
echo "4. Checking backup retention..."
BACKUP_RETENTION=$(aws rds describe-db-instances --query 'DBInstances[0].BackupRetentionPeriod')
if [ "$BACKUP_RETENTION" -ge 30 ]; then
    echo "✅ Backup retention: COMPLIANT ($BACKUP_RETENTION days)"
else
    echo "❌ Backup retention: NON-COMPLIANT ($BACKUP_RETENTION days, minimum 30 required)"
fi

# Check network isolation
echo "5. Checking network isolation..."
RDS_PUBLIC=$(aws rds describe-db-instances --query 'DBInstances[0].PubliclyAccessible')
if [ "$RDS_PUBLIC" = "false" ]; then
    echo "✅ Database network isolation: COMPLIANT"
else
    echo "❌ Database network isolation: NON-COMPLIANT"
fi

echo "=== Compliance Check Complete ==="
```

## Incident Response

### Security Incident Response Plan

#### Phase 1: Preparation

**Incident Response Team**:

- **Incident Commander**: Overall response coordination
- **Security Analyst**: Technical investigation and analysis
- **System Administrator**: Infrastructure remediation
- **Communications Lead**: Internal and external communications

**Contact Information**:

```bash
# Emergency contact list
cat > incident-contacts.txt << EOF
Incident Commander: +1-555-0101 (john.doe@techhealth.com)
Security Analyst: +1-555-0102 (jane.smith@techhealth.com)
System Administrator: +1-555-0103 (admin@techhealth.com)
AWS Support: Create case in AWS Console
Legal/Compliance: +1-555-0104 (legal@techhealth.com)
EOF
```

#### Phase 2: Identification

**Automated Detection**:

```bash
# Security event detection script
#!/bin/bash
# security-monitor.sh

# Check for suspicious CloudTrail events
aws logs filter-log-events \
  --log-group-name CloudTrail/TechHealthAuditTrail \
  --filter-pattern "{ $.errorCode = \"*UnauthorizedOperation\" || $.errorCode = \"AccessDenied*\" }" \
  --start-time $(date -d '1 hour ago' +%s)000

# Check for failed login attempts
aws logs filter-log-events \
  --log-group-name /aws/ec2/auth \
  --filter-pattern "Failed password" \
  --start-time $(date -d '1 hour ago' +%s)000

# Check for unusual network traffic
aws logs filter-log-events \
  --log-group-name VPCFlowLogs \
  --filter-pattern "[timestamp, account, eni, source, destination, srcport, destport, protocol, packets>1000, bytes, windowstart, windowend, action]" \
  --start-time $(date -d '1 hour ago' +%s)000
```

#### Phase 3: Containment

**Immediate Response Actions**:

```bash
#!/bin/bash
# incident-containment.sh

echo "=== SECURITY INCIDENT CONTAINMENT ==="
echo "Incident ID: $(date +%Y%m%d-%H%M%S)"

# 1. Isolate affected instances
echo "1. Isolating affected instances..."
AFFECTED_INSTANCE="i-xxxxxxxxx"  # Replace with actual instance ID

# Create isolation security group
ISOLATION_SG=$(aws ec2 create-security-group \
  --group-name Emergency-Isolation-$(date +%Y%m%d-%H%M%S) \
  --description "Emergency isolation security group" \
  --vpc-id vpc-xxxxxxxxx \
  --query 'GroupId' --output text)

# Apply isolation security group
aws ec2 modify-instance-attribute \
  --instance-id $AFFECTED_INSTANCE \
  --groups $ISOLATION_SG

# 2. Preserve evidence
echo "2. Preserving evidence..."
# Create EBS snapshot for forensics
aws ec2 create-snapshot \
  --volume-id vol-xxxxxxxxx \
  --description "Forensic snapshot - Incident $(date +%Y%m%d-%H%M%S)"

# Export CloudTrail logs
aws logs create-export-task \
  --log-group-name CloudTrail/TechHealthAuditTrail \
  --from $(date -d '24 hours ago' +%s)000 \
  --to $(date +%s)000 \
  --destination s3://techhealth-incident-evidence \
  --destination-prefix incident-$(date +%Y%m%d-%H%M%S)/

# 3. Notify stakeholders
echo "3. Notifying stakeholders..."
aws sns publish \
  --topic-arn arn:aws:sns:us-east-1:ACCOUNT:security-incidents \
  --message "Security incident detected. Containment procedures initiated. Incident ID: $(date +%Y%m%d-%H%M%S)"

echo "Containment procedures completed"
```

#### Phase 4: Eradication

**Threat Removal**:

```bash
#!/bin/bash
# incident-eradication.sh

# 1. Remove malicious software/configurations
echo "1. Removing threats..."

# Update all packages
yum update -y

# Scan for malware
clamscan -r /var/www/html/

# Check for unauthorized users
awk -F: '$3 >= 1000 {print $1}' /etc/passwd

# 2. Patch vulnerabilities
echo "2. Patching vulnerabilities..."

# Apply security patches
yum update --security -y

# Update application dependencies
npm audit fix

# 3. Reset compromised credentials
echo "3. Resetting credentials..."

# Rotate database password
aws secretsmanager rotate-secret \
  --secret-id TechHealth-DB-Credentials \
  --force-rotate-immediately

# Rotate access keys
aws iam create-access-key --user-name app-user
# Deactivate old keys after verification
```

#### Phase 5: Recovery

**System Restoration**:

```bash
#!/bin/bash
# incident-recovery.sh

# 1. Restore from clean backups
echo "1. Restoring from clean backups..."

# Identify clean backup point
CLEAN_SNAPSHOT=$(aws rds describe-db-snapshots \
  --db-instance-identifier techhealth-database \
  --snapshot-type automated \
  --query 'DBSnapshots[?SnapshotCreateTime<=`2023-12-01T00:00:00.000Z`] | sort_by(@, &SnapshotCreateTime) | [-1].DBSnapshotIdentifier' \
  --output text)

# Restore database
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier techhealth-database-clean \
  --db-snapshot-identifier $CLEAN_SNAPSHOT

# 2. Implement additional security measures
echo "2. Implementing additional security measures..."

# Enable GuardDuty
aws guardduty create-detector --enable

# Enable Security Hub
aws securityhub enable-security-hub

# 3. Gradual service restoration
echo "3. Restoring services..."

# Update security groups to allow normal traffic
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxxxxxx \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0

# Monitor for 24 hours before full restoration
```

#### Phase 6: Lessons Learned

**Post-Incident Review**:

```bash
# Create incident report template
cat > incident-report-template.md << EOF
# Security Incident Report

## Incident Summary
- **Incident ID**:
- **Date/Time**:
- **Severity**:
- **Status**:

## Timeline
- **Detection**:
- **Containment**:
- **Eradication**:
- **Recovery**:

## Impact Assessment
- **Systems Affected**:
- **Data Compromised**:
- **Downtime**:
- **Cost Impact**:

## Root Cause Analysis
- **Initial Vector**:
- **Vulnerabilities Exploited**:
- **Contributing Factors**:

## Response Effectiveness
- **What Worked Well**:
- **Areas for Improvement**:
- **Response Time**:

## Recommendations
- **Immediate Actions**:
- **Long-term Improvements**:
- **Policy Updates**:

## Lessons Learned
- **Technical Lessons**:
- **Process Lessons**:
- **Communication Lessons**:
EOF
```

### Breach Notification Procedures

#### HIPAA Breach Notification Requirements

**Risk Assessment**:

```bash
#!/bin/bash
# breach-risk-assessment.sh

echo "=== HIPAA Breach Risk Assessment ==="

# Factors to consider:
echo "1. Nature and extent of PHI involved:"
echo "   - Types of identifiers"
echo "   - Number of individuals affected"
echo "   - Likelihood of re-identification"

echo "2. Unauthorized person who used/disclosed PHI:"
echo "   - Relationship to covered entity"
echo "   - Level of access to PHI"

echo "3. Whether PHI was actually acquired or viewed:"
echo "   - Evidence of access"
echo "   - Duration of exposure"

echo "4. Extent to which risk has been mitigated:"
echo "   - Encryption status"
echo "   - Recovery of PHI"
echo "   - Assurances from recipient"

# Automated checks
echo "5. Automated risk factors:"

# Check if data was encrypted
RDS_ENCRYPTED=$(aws rds describe-db-instances --query 'DBInstances[0].StorageEncrypted')
echo "   - Database encryption: $RDS_ENCRYPTED"

# Check access logs
UNAUTHORIZED_ACCESS=$(aws logs filter-log-events \
  --log-group-name CloudTrail/TechHealthAuditTrail \
  --filter-pattern "{ $.errorCode = \"*UnauthorizedOperation\" }" \
  --start-time $(date -d '24 hours ago' +%s)000 \
  --query 'length(events)')
echo "   - Unauthorized access attempts: $UNAUTHORIZED_ACCESS"

echo "=== Assessment Complete ==="
```

**Notification Timeline**:

- **Immediate (within 1 hour)**: Internal incident response team
- **Within 24 hours**: Senior management and legal counsel
- **Within 60 days**: HHS Office for Civil Rights (if breach affects 500+ individuals)
- **Within 60 days**: Affected individuals
- **Annually**: HHS (for breaches affecting <500 individuals)

## Security Procedures

### Regular Security Tasks

#### Daily Security Checks

```bash
#!/bin/bash
# daily-security-check.sh

echo "=== Daily Security Check - $(date) ==="

# 1. Check for security updates
echo "1. Checking for security updates..."
yum check-update --security | grep -i security

# 2. Review failed login attempts
echo "2. Reviewing failed login attempts..."
aws logs filter-log-events \
  --log-group-name /aws/ec2/auth \
  --filter-pattern "Failed password" \
  --start-time $(date -d '24 hours ago' +%s)000 \
  --query 'length(events)'

# 3. Check CloudTrail for anomalies
echo "3. Checking CloudTrail for anomalies..."
aws logs filter-log-events \
  --log-group-name CloudTrail/TechHealthAuditTrail \
  --filter-pattern "{ $.errorCode = \"*\" }" \
  --start-time $(date -d '24 hours ago' +%s)000 \
  --query 'length(events)'

# 4. Verify backup completion
echo "4. Verifying backup completion..."
aws rds describe-db-snapshots \
  --db-instance-identifier techhealth-database \
  --snapshot-type automated \
  --query 'DBSnapshots[0].Status'

# 5. Check resource utilization
echo "5. Checking resource utilization..."
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=$(aws ec2 describe-instances --filters "Name=tag:Project,Values=TechHealth" --query 'Reservations[0].Instances[0].InstanceId' --output text) \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Average \
  --query 'Datapoints[0].Average'

echo "=== Daily Security Check Complete ==="
```

#### Weekly Security Tasks

```bash
#!/bin/bash
# weekly-security-tasks.sh

echo "=== Weekly Security Tasks - $(date) ==="

# 1. Security patch review and installation
echo "1. Installing security patches..."
yum update --security -y

# 2. Access review
echo "2. Reviewing user access..."
aws iam list-users --query 'Users[*].[UserName,CreateDate]' --output table

# 3. Security group audit
echo "3. Auditing security groups..."
aws ec2 describe-security-groups \
  --query 'SecurityGroups[?IpPermissions[?IpRanges[?CidrIp==`0.0.0.0/0`]]].[GroupName,GroupId]' \
  --output table

# 4. Certificate expiration check
echo "4. Checking certificate expiration..."
openssl x509 -in /etc/ssl/certs/techhealth.crt -noout -dates

# 5. Log analysis
echo "5. Analyzing security logs..."
aws logs filter-log-events \
  --log-group-name VPCFlowLogs \
  --filter-pattern "[timestamp, account, eni, source, destination, srcport, destport, protocol, packets, bytes, windowstart, windowend, action=\"REJECT\"]" \
  --start-time $(date -d '7 days ago' +%s)000 \
  --query 'length(events)'

echo "=== Weekly Security Tasks Complete ==="
```

#### Monthly Security Tasks

```bash
#!/bin/bash
# monthly-security-tasks.sh

echo "=== Monthly Security Tasks - $(date) ==="

# 1. Comprehensive vulnerability scan
echo "1. Running vulnerability scan..."
nmap -sV -O localhost

# 2. Access certification
echo "2. Performing access certification..."
aws iam generate-credential-report
aws iam get-credential-report --query 'Content' --output text | base64 -d > credential-report.csv

# 3. Backup testing
echo "3. Testing backup restoration..."
./scripts/test-backup-restore.sh

# 4. Disaster recovery testing
echo "4. Testing disaster recovery procedures..."
./scripts/test-disaster-recovery.sh

# 5. Security awareness training
echo "5. Security awareness training reminder sent to all users"

# 6. Compliance audit
echo "6. Running compliance audit..."
./scripts/compliance-check.sh

echo "=== Monthly Security Tasks Complete ==="
```

### Security Configuration Management

#### Baseline Security Configuration

```bash
#!/bin/bash
# security-baseline.sh - Establish security baseline

echo "=== Establishing Security Baseline ==="

# 1. System hardening
echo "1. Applying system hardening..."

# Disable unnecessary services
systemctl disable telnet
systemctl disable ftp
systemctl disable rsh

# Configure SSH security
cat > /etc/ssh/sshd_config.d/security.conf << EOF
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
Protocol 2
EOF

# 2. File system security
echo "2. Configuring file system security..."

# Set proper permissions
chmod 600 /etc/ssh/ssh_host_*_key
chmod 644 /etc/ssh/ssh_host_*_key.pub
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys

# 3. Network security
echo "3. Configuring network security..."

# Configure iptables rules
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -j DROP

# Save iptables rules
service iptables save

# 4. Logging configuration
echo "4. Configuring logging..."

# Configure rsyslog
cat > /etc/rsyslog.d/security.conf << EOF
# Security-related logs
auth,authpriv.*                 /var/log/auth.log
*.*;auth,authpriv.none          /var/log/syslog
EOF

# 5. Audit configuration
echo "5. Configuring audit..."

# Configure auditd
cat > /etc/audit/rules.d/security.rules << EOF
# Monitor authentication events
-w /var/log/auth.log -p wa -k authentication
-w /etc/passwd -p wa -k passwd_changes
-w /etc/shadow -p wa -k shadow_changes
-w /etc/group -p wa -k group_changes

# Monitor network configuration
-w /etc/network/ -p wa -k network_changes
-w /etc/hosts -p wa -k hosts_changes

# Monitor system calls
-a always,exit -F arch=b64 -S execve -k exec_commands
EOF

systemctl restart auditd

echo "=== Security Baseline Established ==="
```

This comprehensive security and compliance documentation provides the framework for maintaining HIPAA compliance and robust security posture for the TechHealth infrastructure modernization project.
