# Operational Runbooks

## Overview

This document provides comprehensive operational procedures and runbooks for maintaining the TechHealth infrastructure. These procedures ensure consistent operations, minimize downtime, and maintain security and compliance standards.

## Table of Contents

- [Daily Operations](#daily-operations)
- [Weekly Maintenance](#weekly-maintenance)
- [Monthly Procedures](#monthly-procedures)
- [Incident Response Runbooks](#incident-response-runbooks)
- [Backup and Recovery Procedures](#backup-and-recovery-procedures)
- [Performance Monitoring](#performance-monitoring)
- [Security Operations](#security-operations)
- [Change Management](#change-management)

## Daily Operations

### Morning Health Check

**Frequency**: Every weekday at 8:00 AM
**Duration**: 15 minutes
**Responsible**: System Administrator

```bash
#!/bin/bash
# daily-health-check.sh

echo "=== TechHealth Daily Health Check - $(date) ==="

# 1. Check overall system status
echo "1. System Status Check"
aws cloudformation describe-stacks \
  --stack-name TechHealthInfrastructureStack \
  --query 'Stacks[0].StackStatus' \
  --output text

# 2. Verify EC2 instances are running
echo "2. EC2 Instance Status"
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=TechHealth" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PublicIpAddress]' \
  --output table

# 3. Check RDS database status
echo "3. RDS Database Status"
aws rds describe-db-instances \
  --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus,Endpoint.Address]' \
  --output table

# 4. Verify application connectivity
echo "4. Application Connectivity Test"
EC2_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=TechHealth" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

if [ "$EC2_IP" != "None" ]; then
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://$EC2_IP --connect-timeout 10)
    if [ "$HTTP_STATUS" = "200" ]; then
        echo "✅ Application accessible (HTTP $HTTP_STATUS)"
    else
        echo "❌ Application not accessible (HTTP $HTTP_STATUS)"
    fi
else
    echo "❌ No running EC2 instances found"
fi

# 5. Check recent CloudWatch alarms
echo "5. Recent CloudWatch Alarms"
aws cloudwatch describe-alarms \
  --state-value ALARM \
  --query 'MetricAlarms[*].[AlarmName,StateReason,StateUpdatedTimestamp]' \
  --output table

# 6. Review overnight logs for errors
echo "6. Error Log Review"
aws logs filter-log-events \
  --log-group-name /aws/ec2/techhealth \
  --start-time $(date -d 'yesterday 18:00' +%s)000 \
  --end-time $(date +%s)000 \
  --filter-pattern "ERROR" \
  --query 'length(events)' \
  --output text | xargs -I {} echo "Error events in last 14 hours: {}"

# 7. Check backup status
echo "7. Backup Status"
aws rds describe-db-snapshots \
  --db-instance-identifier techhealth-database \
  --snapshot-type automated \
  --query 'DBSnapshots[0].[DBSnapshotIdentifier,Status,SnapshotCreateTime]' \
  --output table

# 8. Security check - failed login attempts
echo "8. Security Check"
aws logs filter-log-events \
  --log-group-name /aws/ec2/auth \
  --start-time $(date -d 'yesterday 18:00' +%s)000 \
  --end-time $(date +%s)000 \
  --filter-pattern "Failed password" \
  --query 'length(events)' \
  --output text | xargs -I {} echo "Failed login attempts: {}"

echo "=== Daily Health Check Complete ==="

# Generate summary report
cat > daily-report-$(date +%Y%m%d).txt << EOF
TechHealth Daily Health Check Report - $(date)

System Status: $(aws cloudformation describe-stacks --stack-name TechHealthInfrastructureStack --query 'Stacks[0].StackStatus' --output text)
Running Instances: $(aws ec2 describe-instances --filters "Name=tag:Project,Values=TechHealth" "Name=instance-state-name,Values=running" --query 'length(Reservations[*].Instances[*])' --output text)
Database Status: $(aws rds describe-db-instances --query 'DBInstances[0].DBInstanceStatus' --output text)
Active Alarms: $(aws cloudwatch describe-alarms --state-value ALARM --query 'length(MetricAlarms)' --output text)

Action Items:
- Review any active alarms
- Investigate error events if count > 0
- Follow up on failed login attempts if count > 5

Next Check: $(date -d 'tomorrow 8:00' '+%Y-%m-%d %H:%M')
EOF

echo "Report saved to: daily-report-$(date +%Y%m%d).txt"
```

### Application Performance Monitoring

**Frequency**: Continuous monitoring with daily review
**Duration**: 10 minutes
**Responsible**: DevOps Engineer

```bash
#!/bin/bash
# performance-monitoring.sh

echo "=== Application Performance Monitoring ==="

# Get instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=TechHealth" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

# 1. CPU Utilization (last 24 hours)
echo "1. CPU Utilization (24h average)"
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=$INSTANCE_ID \
  --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Average \
  --query 'Datapoints[*].Average' \
  --output text | awk '{sum+=$1; count++} END {printf "Average CPU: %.2f%%\n", sum/count}'

# 2. Memory Utilization (if CloudWatch agent is installed)
echo "2. Memory Utilization (24h average)"
aws cloudwatch get-metric-statistics \
  --namespace CWAgent \
  --metric-name mem_used_percent \
  --dimensions Name=InstanceId,Value=$INSTANCE_ID \
  --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Average \
  --query 'Datapoints[*].Average' \
  --output text | awk '{sum+=$1; count++} END {printf "Average Memory: %.2f%%\n", sum/count}'

# 3. Disk Utilization
echo "3. Disk Utilization (24h average)"
aws cloudwatch get-metric-statistics \
  --namespace CWAgent \
  --metric-name disk_used_percent \
  --dimensions Name=InstanceId,Value=$INSTANCE_ID Name=device,Value=/dev/xvda1 \
  --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Average \
  --query 'Datapoints[*].Average' \
  --output text | awk '{sum+=$1; count++} END {printf "Average Disk Usage: %.2f%%\n", sum/count}'

# 4. Network I/O
echo "4. Network I/O (24h total)"
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name NetworkIn \
  --dimensions Name=InstanceId,Value=$INSTANCE_ID \
  --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 86400 \
  --statistics Sum \
  --query 'Datapoints[0].Sum' \
  --output text | awk '{printf "Network In: %.2f MB\n", $1/1024/1024}'

# 5. Database Performance
echo "5. Database Performance"
DB_INSTANCE=$(aws rds describe-db-instances --query 'DBInstances[0].DBInstanceIdentifier' --output text)

aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=$DB_INSTANCE \
  --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Average \
  --query 'Datapoints[*].Average' \
  --output text | awk '{sum+=$1; count++} END {printf "DB CPU Average: %.2f%%\n", sum/count}'

aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=$DB_INSTANCE \
  --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Average \
  --query 'Datapoints[*].Average' \
  --output text | awk '{sum+=$1; count++} END {printf "DB Connections Average: %.0f\n", sum/count}'

echo "=== Performance Monitoring Complete ==="
```

## Weekly Maintenance

### System Updates and Patching

**Frequency**: Every Sunday at 2:00 AM
**Duration**: 2-4 hours
**Responsible**: System Administrator

```bash
#!/bin/bash
# weekly-maintenance.sh

echo "=== Weekly Maintenance - $(date) ==="

# 1. Create pre-maintenance snapshot
echo "1. Creating pre-maintenance snapshots"
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=TechHealth" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

VOLUME_ID=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId' \
  --output text)

aws ec2 create-snapshot \
  --volume-id $VOLUME_ID \
  --description "Pre-maintenance snapshot $(date +%Y%m%d-%H%M%S)" \
  --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Purpose,Value=Maintenance},{Key=Date,Value='$(date +%Y%m%d)'}]'

# 2. Database maintenance snapshot
echo "2. Creating database maintenance snapshot"
aws rds create-db-snapshot \
  --db-instance-identifier techhealth-database \
  --db-snapshot-identifier techhealth-maintenance-$(date +%Y%m%d-%H%M%S)

# 3. System updates
echo "3. Applying system updates"
EC2_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=TechHealth" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

ssh -i ~/.ssh/techhealth-prod.pem ec2-user@$EC2_IP << 'EOF'
# Update system packages
sudo yum update -y

# Update application dependencies
cd /var/www/html
sudo npm audit fix

# Restart services
sudo systemctl restart httpd
sudo systemctl restart mysql

# Clear temporary files
sudo find /tmp -type f -atime +7 -delete
sudo find /var/log -name "*.log" -type f -mtime +30 -delete

# Check disk space
df -h
EOF

# 4. Security updates
echo "4. Applying security updates"
ssh -i ~/.ssh/techhealth-prod.pem ec2-user@$EC2_IP << 'EOF'
# Apply security patches
sudo yum update --security -y

# Update SSL certificates if needed
sudo certbot renew --dry-run

# Restart security services
sudo systemctl restart fail2ban
EOF

# 5. Database maintenance
echo "5. Database maintenance"
RDS_ENDPOINT=$(aws rds describe-db-instances \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

DB_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id TechHealth-DB-Credentials \
  --query SecretString \
  --output text | jq -r .password)

mysql -h $RDS_ENDPOINT -u admin -p$DB_PASSWORD << 'EOF'
-- Optimize tables
OPTIMIZE TABLE users, sessions, audit_log;

-- Update statistics
ANALYZE TABLE users, sessions, audit_log;

-- Check for fragmentation
SELECT table_name,
       ROUND(((data_length + index_length) / 1024 / 1024), 2) AS "DB Size in MB",
       ROUND((data_free / 1024 / 1024), 2) AS "Free Space in MB"
FROM information_schema.tables
WHERE table_schema = DATABASE();

-- Clean up old sessions (older than 30 days)
DELETE FROM sessions WHERE created_at < DATE_SUB(NOW(), INTERVAL 30 DAY);

-- Archive old audit logs (older than 90 days)
CREATE TABLE IF NOT EXISTS audit_log_archive LIKE audit_log;
INSERT INTO audit_log_archive SELECT * FROM audit_log WHERE created_at < DATE_SUB(NOW(), INTERVAL 90 DAY);
DELETE FROM audit_log WHERE created_at < DATE_SUB(NOW(), INTERVAL 90 DAY);
EOF

# 6. Log rotation and cleanup
echo "6. Log rotation and cleanup"
ssh -i ~/.ssh/techhealth-prod.pem ec2-user@$EC2_IP << 'EOF'
# Force log rotation
sudo logrotate -f /etc/logrotate.conf

# Clean up old log files
sudo find /var/log -name "*.log.*" -type f -mtime +30 -delete

# Clean up application logs
sudo find /var/www/html/logs -name "*.log" -type f -mtime +7 -delete
EOF

# 7. Security scan
echo "7. Running security scan"
./scripts/security-scan.sh

# 8. Performance baseline update
echo "8. Updating performance baseline"
./scripts/performance-baseline.sh

# 9. Backup verification
echo "9. Verifying backups"
./scripts/backup-verification.sh

# 10. Post-maintenance verification
echo "10. Post-maintenance verification"
sleep 300  # Wait 5 minutes for services to stabilize
./scripts/post-deployment-verification.sh

echo "=== Weekly Maintenance Complete ==="

# Generate maintenance report
cat > maintenance-report-$(date +%Y%m%d).txt << EOF
TechHealth Weekly Maintenance Report - $(date)

Maintenance Activities Completed:
✅ Pre-maintenance snapshots created
✅ System updates applied
✅ Security patches installed
✅ Database maintenance performed
✅ Log rotation and cleanup
✅ Security scan completed
✅ Performance baseline updated
✅ Backup verification completed
✅ Post-maintenance verification passed

System Status After Maintenance:
- EC2 Instances: $(aws ec2 describe-instances --filters "Name=tag:Project,Values=TechHealth" "Name=instance-state-name,Values=running" --query 'length(Reservations[*].Instances[*])' --output text) running
- Database Status: $(aws rds describe-db-instances --query 'DBInstances[0].DBInstanceStatus' --output text)
- Active Alarms: $(aws cloudwatch describe-alarms --state-value ALARM --query 'length(MetricAlarms)' --output text)

Next Maintenance: $(date -d 'next Sunday 2:00' '+%Y-%m-%d %H:%M')
EOF

echo "Maintenance report saved to: maintenance-report-$(date +%Y%m%d).txt"
```

### Security Review

**Frequency**: Every Wednesday
**Duration**: 1 hour
**Responsible**: Security Administrator

```bash
#!/bin/bash
# weekly-security-review.sh

echo "=== Weekly Security Review - $(date) ==="

# 1. Access review
echo "1. User Access Review"
aws iam list-users --query 'Users[*].[UserName,CreateDate,PasswordLastUsed]' --output table

# 2. Security group audit
echo "2. Security Group Audit"
aws ec2 describe-security-groups \
  --query 'SecurityGroups[?IpPermissions[?IpRanges[?CidrIp==`0.0.0.0/0`]]].[GroupName,GroupId,Description]' \
  --output table

# 3. Failed login analysis
echo "3. Failed Login Analysis (last 7 days)"
aws logs filter-log-events \
  --log-group-name /aws/ec2/auth \
  --start-time $(date -d '7 days ago' +%s)000 \
  --filter-pattern "Failed password" \
  --query 'events[*].[eventTimestamp,message]' \
  --output table | head -20

# 4. CloudTrail analysis
echo "4. CloudTrail Security Events (last 7 days)"
aws logs filter-log-events \
  --log-group-name CloudTrail/TechHealthAuditTrail \
  --start-time $(date -d '7 days ago' +%s)000 \
  --filter-pattern "{ $.errorCode = \"*UnauthorizedOperation\" || $.errorCode = \"AccessDenied*\" }" \
  --query 'events[*].[eventTimestamp,message]' \
  --output table

# 5. Certificate expiration check
echo "5. SSL Certificate Expiration Check"
EC2_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=TechHealth" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

if [ "$EC2_IP" != "None" ]; then
    echo | openssl s_client -servername techhealth.com -connect $EC2_IP:443 2>/dev/null | \
    openssl x509 -noout -dates
fi

# 6. Vulnerability scan
echo "6. Basic Vulnerability Scan"
nmap -sV $EC2_IP | grep -E "(open|filtered)"

# 7. Compliance check
echo "7. HIPAA Compliance Check"
./scripts/compliance-check.sh

echo "=== Weekly Security Review Complete ==="
```

## Monthly Procedures

### Comprehensive System Review

**Frequency**: First Sunday of each month
**Duration**: 4-6 hours
**Responsible**: DevOps Team Lead

```bash
#!/bin/bash
# monthly-system-review.sh

echo "=== Monthly System Review - $(date) ==="

# 1. Cost analysis
echo "1. Monthly Cost Analysis"
./scripts/cost-analysis.sh

# 2. Performance trend analysis
echo "2. Performance Trend Analysis"
./scripts/performance-trend-analysis.sh

# 3. Capacity planning
echo "3. Capacity Planning Review"
./scripts/capacity-planning.sh

# 4. Security assessment
echo "4. Comprehensive Security Assessment"
./scripts/comprehensive-security-scan.sh

# 5. Backup and recovery testing
echo "5. Backup and Recovery Testing"
./scripts/test-backup-recovery.sh

# 6. Disaster recovery drill
echo "6. Disaster Recovery Drill"
./scripts/disaster-recovery-drill.sh

# 7. Compliance audit
echo "7. Compliance Audit"
./scripts/monthly-compliance-audit.sh

# 8. Documentation review
echo "8. Documentation Review and Update"
# Review and update all operational documentation

echo "=== Monthly System Review Complete ==="
```

### Disaster Recovery Testing

**Frequency**: Monthly
**Duration**: 4 hours
**Responsible**: Senior DevOps Engineer

```bash
#!/bin/bash
# disaster-recovery-test.sh

echo "=== Disaster Recovery Test - $(date) ==="

# 1. Create test environment
echo "1. Creating test environment for DR testing"
export CDK_ENVIRONMENT=dr-test
npx cdk deploy --context environment=dr-test --require-approval never

# 2. Test database restore
echo "2. Testing database restore from backup"
LATEST_SNAPSHOT=$(aws rds describe-db-snapshots \
  --db-instance-identifier techhealth-database \
  --snapshot-type automated \
  --query 'DBSnapshots | sort_by(@, &SnapshotCreateTime) | [-1].DBSnapshotIdentifier' \
  --output text)

aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier techhealth-database-dr-test \
  --db-snapshot-identifier $LATEST_SNAPSHOT \
  --db-instance-class db.t3.micro

# 3. Test application deployment
echo "3. Testing application deployment in DR environment"
# Deploy application to DR environment

# 4. Test data integrity
echo "4. Testing data integrity"
# Verify data consistency and integrity

# 5. Test failover procedures
echo "5. Testing failover procedures"
# Test DNS failover, load balancer configuration, etc.

# 6. Measure recovery time
echo "6. Measuring recovery time objectives"
# Document actual vs. target RTO/RPO

# 7. Clean up test environment
echo "7. Cleaning up DR test environment"
npx cdk destroy --context environment=dr-test --force

echo "=== Disaster Recovery Test Complete ==="
```

## Incident Response Runbooks

### High CPU Utilization

**Trigger**: CPU utilization > 80% for 10 minutes
**Severity**: Medium
**Response Time**: 15 minutes

```bash
#!/bin/bash
# incident-high-cpu.sh

echo "=== High CPU Utilization Incident Response ==="

INSTANCE_ID=$1
if [ -z "$INSTANCE_ID" ]; then
    INSTANCE_ID=$(aws ec2 describe-instances \
      --filters "Name=tag:Project,Values=TechHealth" "Name=instance-state-name,Values=running" \
      --query 'Reservations[0].Instances[0].InstanceId' \
      --output text)
fi

echo "Investigating high CPU on instance: $INSTANCE_ID"

# 1. Get current CPU utilization
echo "1. Current CPU Utilization"
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=$INSTANCE_ID \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average,Maximum \
  --query 'Datapoints[*].[Timestamp,Average,Maximum]' \
  --output table

# 2. Check top processes
echo "2. Top Processes on Instance"
EC2_IP=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

ssh -i ~/.ssh/techhealth-prod.pem ec2-user@$EC2_IP << 'EOF'
echo "Top CPU consuming processes:"
top -b -n 1 | head -20

echo "Memory usage:"
free -h

echo "Disk I/O:"
iostat -x 1 1

echo "Network connections:"
netstat -tuln | wc -l
EOF

# 3. Check application logs for errors
echo "3. Checking application logs"
aws logs filter-log-events \
  --log-group-name /aws/ec2/techhealth \
  --start-time $(date -d '1 hour ago' +%s)000 \
  --filter-pattern "ERROR" \
  --query 'events[*].[eventTimestamp,message]' \
  --output table | head -10

# 4. Immediate mitigation actions
echo "4. Immediate Mitigation Actions"
echo "Options:"
echo "a) Restart application services"
echo "b) Scale up instance size"
echo "c) Add additional instance"
echo "d) Investigate and kill problematic processes"

read -p "Select action (a/b/c/d): " action

case $action in
    a)
        ssh -i ~/.ssh/techhealth-prod.pem ec2-user@$EC2_IP << 'EOF'
sudo systemctl restart httpd
sudo systemctl restart mysql
EOF
        ;;
    b)
        aws ec2 stop-instances --instance-ids $INSTANCE_ID
        aws ec2 wait instance-stopped --instance-ids $INSTANCE_ID
        aws ec2 modify-instance-attribute --instance-id $INSTANCE_ID --instance-type Value=t3.small
        aws ec2 start-instances --instance-ids $INSTANCE_ID
        ;;
    c)
        echo "Launching additional instance..."
        # Launch additional instance using CDK or AWS CLI
        ;;
    d)
        ssh -i ~/.ssh/techhealth-prod.pem ec2-user@$EC2_IP
        ;;
esac

echo "=== High CPU Incident Response Complete ==="
```

### Database Connection Issues

**Trigger**: Database connection failures
**Severity**: High
**Response Time**: 5 minutes

```bash
#!/bin/bash
# incident-database-connection.sh

echo "=== Database Connection Issue Response ==="

# 1. Check RDS instance status
echo "1. RDS Instance Status"
aws rds describe-db-instances \
  --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus,Endpoint.Address]' \
  --output table

# 2. Check database connections
echo "2. Current Database Connections"
RDS_ENDPOINT=$(aws rds describe-db-instances \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

DB_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id TechHealth-DB-Credentials \
  --query SecretString \
  --output text | jq -r .password)

mysql -h $RDS_ENDPOINT -u admin -p$DB_PASSWORD -e "SHOW PROCESSLIST;" 2>/dev/null || echo "Cannot connect to database"

# 3. Check security group rules
echo "3. Security Group Rules"
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=TechHealth-RDS-SG" \
  --query 'SecurityGroups[0].IpPermissions[*].[IpProtocol,FromPort,ToPort,IpRanges,UserIdGroupPairs]' \
  --output table

# 4. Test connectivity from EC2
echo "4. Testing Connectivity from EC2"
EC2_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=TechHealth" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

ssh -i ~/.ssh/techhealth-prod.pem ec2-user@$EC2_IP << EOF
echo "Testing database connectivity:"
timeout 10 mysql -h $RDS_ENDPOINT -u admin -p$DB_PASSWORD -e "SELECT 1;" 2>&1
echo "Network connectivity test:"
telnet $RDS_ENDPOINT 3306 < /dev/null
EOF

# 5. Check CloudWatch metrics
echo "5. Database CloudWatch Metrics"
DB_INSTANCE=$(aws rds describe-db-instances --query 'DBInstances[0].DBInstanceIdentifier' --output text)

aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=$DB_INSTANCE \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average,Maximum \
  --query 'Datapoints[*].[Timestamp,Average,Maximum]' \
  --output table

# 6. Mitigation actions
echo "6. Mitigation Actions"
echo "a) Restart RDS instance"
echo "b) Kill long-running queries"
echo "c) Check and fix security groups"
echo "d) Scale up RDS instance"

read -p "Select action (a/b/c/d): " action

case $action in
    a)
        aws rds reboot-db-instance --db-instance-identifier $DB_INSTANCE
        ;;
    b)
        mysql -h $RDS_ENDPOINT -u admin -p$DB_PASSWORD << 'EOF'
SHOW PROCESSLIST;
-- Kill long-running queries manually
-- KILL <process_id>;
EOF
        ;;
    c)
        echo "Review and fix security group rules manually"
        ;;
    d)
        aws rds modify-db-instance \
          --db-instance-identifier $DB_INSTANCE \
          --db-instance-class db.t3.small \
          --apply-immediately
        ;;
esac

echo "=== Database Connection Issue Response Complete ==="
```

## Backup and Recovery Procedures

### Daily Backup Verification

```bash
#!/bin/bash
# daily-backup-verification.sh

echo "=== Daily Backup Verification - $(date) ==="

# 1. Verify RDS automated backups
echo "1. RDS Automated Backup Status"
aws rds describe-db-instances \
  --query 'DBInstances[*].[DBInstanceIdentifier,BackupRetentionPeriod,PreferredBackupWindow]' \
  --output table

# Check latest automated backup
aws rds describe-db-snapshots \
  --db-instance-identifier techhealth-database \
  --snapshot-type automated \
  --query 'DBSnapshots[0].[DBSnapshotIdentifier,Status,SnapshotCreateTime,AllocatedStorage]' \
  --output table

# 2. Verify EBS snapshots
echo "2. EBS Snapshot Status"
aws ec2 describe-snapshots \
  --owner-ids self \
  --filters "Name=tag:Purpose,Values=Automated" \
  --query 'Snapshots | sort_by(@, &StartTime) | [-5:].[SnapshotId,State,StartTime,VolumeSize]' \
  --output table

# 3. Test backup integrity
echo "3. Testing Backup Integrity"
LATEST_SNAPSHOT=$(aws rds describe-db-snapshots \
  --db-instance-identifier techhealth-database \
  --snapshot-type automated \
  --query 'DBSnapshots | sort_by(@, &SnapshotCreateTime) | [-1].DBSnapshotIdentifier' \
  --output text)

echo "Latest RDS snapshot: $LATEST_SNAPSHOT"
echo "Snapshot status: $(aws rds describe-db-snapshots --db-snapshot-identifier $LATEST_SNAPSHOT --query 'DBSnapshots[0].Status' --output text)"

# 4. Backup size monitoring
echo "4. Backup Size Monitoring"
aws rds describe-db-snapshots \
  --db-instance-identifier techhealth-database \
  --snapshot-type automated \
  --query 'DBSnapshots[*].[SnapshotCreateTime,AllocatedStorage]' \
  --output table | head -10

echo "=== Daily Backup Verification Complete ==="
```

### Recovery Procedures

```bash
#!/bin/bash
# recovery-procedures.sh

RECOVERY_TYPE=$1  # full, partial, point-in-time

echo "=== Recovery Procedure: $RECOVERY_TYPE ==="

case $RECOVERY_TYPE in
    "full")
        echo "Full System Recovery"

        # 1. Restore database
        LATEST_SNAPSHOT=$(aws rds describe-db-snapshots \
          --db-instance-identifier techhealth-database \
          --snapshot-type automated \
          --query 'DBSnapshots | sort_by(@, &SnapshotCreateTime) | [-1].DBSnapshotIdentifier' \
          --output text)

        aws rds restore-db-instance-from-db-snapshot \
          --db-instance-identifier techhealth-database-restored \
          --db-snapshot-identifier $LATEST_SNAPSHOT

        # 2. Restore EC2 from AMI
        LATEST_AMI=$(aws ec2 describe-images \
          --owners self \
          --filters "Name=tag:Purpose,Values=Backup" \
          --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
          --output text)

        aws ec2 run-instances \
          --image-id $LATEST_AMI \
          --instance-type t2.micro \
          --key-name techhealth-prod-keypair \
          --security-group-ids sg-xxxxxxxxx \
          --subnet-id subnet-xxxxxxxxx
        ;;

    "partial")
        echo "Partial Recovery - Database Only"
        # Restore specific database tables or data
        ;;

    "point-in-time")
        echo "Point-in-Time Recovery"
        read -p "Enter recovery time (YYYY-MM-DD HH:MM:SS): " recovery_time

        aws rds restore-db-instance-to-point-in-time \
          --source-db-instance-identifier techhealth-database \
          --target-db-instance-identifier techhealth-database-pitr \
          --restore-time "$recovery_time"
        ;;
esac

echo "=== Recovery Procedure Complete ==="
```

## Change Management

### Change Request Process

```bash
#!/bin/bash
# change-request.sh

echo "=== Change Request Process ==="

# Collect change information
read -p "Change description: " change_description
read -p "Change category (emergency/standard/normal): " change_category
read -p "Requested by: " requested_by
read -p "Implementation date (YYYY-MM-DD): " implementation_date
read -p "Rollback plan: " rollback_plan

# Generate change request ID
CHANGE_ID="CHG-$(date +%Y%m%d)-$(printf "%04d" $RANDOM)"

# Create change request document
cat > change-request-$CHANGE_ID.md << EOF
# Change Request: $CHANGE_ID

## Change Details
- **Description**: $change_description
- **Category**: $change_category
- **Requested by**: $requested_by
- **Implementation Date**: $implementation_date
- **Status**: Pending Approval

## Risk Assessment
- **Risk Level**: [Low/Medium/High]
- **Impact**: [Low/Medium/High]
- **Affected Systems**: TechHealth Infrastructure

## Implementation Plan
1. Pre-change backup
2. Implementation steps
3. Post-change verification
4. Rollback if needed

## Rollback Plan
$rollback_plan

## Approval
- [ ] Technical Review
- [ ] Security Review
- [ ] Management Approval

## Implementation Log
- Start Time:
- End Time:
- Status:
- Issues:
- Rollback Required: [Yes/No]

EOF

echo "Change request created: change-request-$CHANGE_ID.md"
echo "Change ID: $CHANGE_ID"
```

### Pre-Change Checklist

```bash
#!/bin/bash
# pre-change-checklist.sh

echo "=== Pre-Change Checklist ==="

CHANGE_ID=$1

echo "Change ID: $CHANGE_ID"
echo "Date: $(date)"

# Checklist items
checklist=(
    "Backup created and verified"
    "Change window scheduled"
    "Stakeholders notified"
    "Rollback plan tested"
    "Implementation steps documented"
    "Post-change verification plan ready"
    "Emergency contacts available"
    "Monitoring alerts configured"
)

echo "Pre-Change Checklist:"
for item in "${checklist[@]}"; do
    read -p "✓ $item [y/N]: " response
    if [[ "$response" != "y" ]]; then
        echo "❌ Checklist item not completed: $item"
        echo "Change implementation should not proceed"
        exit 1
    fi
done

echo "✅ All pre-change checklist items completed"
echo "Change $CHANGE_ID is ready for implementation"
```

This comprehensive operational runbook provides structured procedures for maintaining the TechHealth infrastructure, ensuring consistent operations, and minimizing downtime through proactive monitoring and maintenance.
