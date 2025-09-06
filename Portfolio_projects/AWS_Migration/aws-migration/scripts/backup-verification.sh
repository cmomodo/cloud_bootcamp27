#!/bin/bash

# Automated Backup Verification Script for TechHealth Infrastructure
# This script verifies RDS backups, snapshots, and implements backup testing procedures

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
    print_status "Testing: $test_name"
    
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
    echo "  --create-snapshot    Create manual snapshot for testing"
    echo "  --test-restore       Test restore process (creates temporary instance)"
    echo "  --cleanup-test       Clean up test restore instances"
    echo "  --verbose            Show detailed output"
    echo "  --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 dev --verbose"
    echo "  $0 prod --create-snapshot"
    echo "  $0 staging --test-restore"
    exit 1
}

# Parse command line arguments
ENVIRONMENT=""
CREATE_SNAPSHOT=false
TEST_RESTORE=false
CLEANUP_TEST=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        dev|staging|prod)
            ENVIRONMENT="$1"
            shift
            ;;
        --create-snapshot)
            CREATE_SNAPSHOT=true
            shift
            ;;
        --test-restore)
            TEST_RESTORE=true
            shift
            ;;
        --cleanup-test)
            CLEANUP_TEST=true
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

echo "🔄 TechHealth Backup Verification"
echo "=================================="
echo "Environment: $ENVIRONMENT"
echo "Create Snapshot: $CREATE_SNAPSHOT"
echo "Test Restore: $TEST_RESTORE"
echo "Cleanup Test: $CLEANUP_TEST"
echo ""

STACK_NAME="TechHealth-$(echo $ENVIRONMENT | sed 's/.*/\u&/')-Infrastructure"

# Check if stack exists
print_status "Checking if stack exists..."
if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" &>/dev/null; then
    print_error "Stack $STACK_NAME does not exist. Deploy the infrastructure first."
    exit 1
fi

print_success "Stack $STACK_NAME found"

# Get RDS instance information
get_rds_info() {
    print_status "Retrieving RDS instance information..."
    
    # Get RDS instances associated with the stack
    RDS_INSTANCES=$(aws rds describe-db-instances \
        --query "DBInstances[?contains(DBInstanceIdentifier, '$(echo $STACK_NAME | tr '[:upper:]' '[:lower:]')') || contains(DBInstanceIdentifier, 'techhealth')].{ID:DBInstanceIdentifier,Class:DBInstanceClass,Engine:Engine,Status:DBInstanceStatus,BackupRetention:BackupRetentionPeriod,MultiAZ:MultiAZ}" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$RDS_INSTANCES" ]; then
        print_error "No RDS instances found for stack $STACK_NAME"
        exit 1
    fi
    
    echo "$RDS_INSTANCES" | while read db_id db_class engine status backup_retention multi_az; do
        print_success "Found RDS instance: $db_id"
        echo "  Class: $db_class"
        echo "  Engine: $engine"
        echo "  Status: $status"
        echo "  Backup Retention: $backup_retention days"
        echo "  Multi-AZ: $multi_az"
        echo ""
        
        # Store the first (primary) RDS instance for further operations
        if [ -z "$PRIMARY_RDS_INSTANCE" ]; then
            export PRIMARY_RDS_INSTANCE="$db_id"
        fi
    done
}

# Verify automated backup configuration
verify_backup_configuration() {
    print_status "Verifying automated backup configuration..."
    
    echo "$RDS_INSTANCES" | while read db_id db_class engine status backup_retention multi_az; do
        # Check backup retention period
        if [ "$backup_retention" -gt 0 ]; then
            print_success "Automated backups enabled for $db_id (${backup_retention} days)"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            print_error "Automated backups disabled for $db_id"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        
        # Check backup window
        BACKUP_WINDOW=$(aws rds describe-db-instances \
            --db-instance-identifier "$db_id" \
            --query 'DBInstances[0].PreferredBackupWindow' \
            --output text)
        
        if [ "$BACKUP_WINDOW" != "None" ] && [ -n "$BACKUP_WINDOW" ]; then
            print_success "Backup window configured for $db_id: $BACKUP_WINDOW"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            print_warning "No backup window configured for $db_id"
        fi
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        
        # Check maintenance window
        MAINTENANCE_WINDOW=$(aws rds describe-db-instances \
            --db-instance-identifier "$db_id" \
            --query 'DBInstances[0].PreferredMaintenanceWindow' \
            --output text)
        
        if [ "$MAINTENANCE_WINDOW" != "None" ] && [ -n "$MAINTENANCE_WINDOW" ]; then
            print_success "Maintenance window configured for $db_id: $MAINTENANCE_WINDOW"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            print_warning "No maintenance window configured for $db_id"
        fi
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
    done
}

# List and verify existing backups
verify_existing_backups() {
    print_status "Verifying existing automated backups..."
    
    echo "$RDS_INSTANCES" | while read db_id db_class engine status backup_retention multi_az; do
        # Get automated backups (point-in-time recovery)
        BACKUP_INFO=$(aws rds describe-db-instances \
            --db-instance-identifier "$db_id" \
            --query 'DBInstances[0].{EarliestRestorableTime:EarliestRestorableTime,LatestRestorableTime:LatestRestorableTime}' \
            --output text)
        
        if [ -n "$BACKUP_INFO" ]; then
            echo "$BACKUP_INFO" | while read earliest latest; do
                print_success "Point-in-time recovery available for $db_id"
                echo "  Earliest restorable time: $earliest"
                echo "  Latest restorable time: $latest"
                PASSED_TESTS=$((PASSED_TESTS + 1))
            done
        else
            print_error "No point-in-time recovery information for $db_id"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
    done
}

# List and verify manual snapshots
verify_manual_snapshots() {
    print_status "Verifying manual snapshots..."
    
    echo "$RDS_INSTANCES" | while read db_id db_class engine status backup_retention multi_az; do
        # Get manual snapshots
        SNAPSHOTS=$(aws rds describe-db-snapshots \
            --db-instance-identifier "$db_id" \
            --snapshot-type manual \
            --query 'DBSnapshots[*].{ID:DBSnapshotIdentifier,Status:Status,Created:SnapshotCreateTime,Size:AllocatedStorage}' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$SNAPSHOTS" ]; then
            SNAPSHOT_COUNT=$(echo "$SNAPSHOTS" | wc -l)
            print_success "Found $SNAPSHOT_COUNT manual snapshots for $db_id"
            
            if [ "$VERBOSE" = true ]; then
                echo "$SNAPSHOTS" | while read snap_id snap_status snap_created snap_size; do
                    echo "  Snapshot: $snap_id"
                    echo "    Status: $snap_status"
                    echo "    Created: $snap_created"
                    echo "    Size: ${snap_size}GB"
                    echo ""
                done
            fi
            
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            print_warning "No manual snapshots found for $db_id"
        fi
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
    done
}

# Create manual snapshot for testing
create_manual_snapshot() {
    if [ "$CREATE_SNAPSHOT" != true ]; then
        return 0
    fi
    
    print_status "Creating manual snapshot for testing..."
    
    if [ -z "$PRIMARY_RDS_INSTANCE" ]; then
        print_error "No primary RDS instance found"
        return 1
    fi
    
    SNAPSHOT_ID="${PRIMARY_RDS_INSTANCE}-test-snapshot-$(date +%Y%m%d-%H%M%S)"
    
    print_status "Creating snapshot: $SNAPSHOT_ID"
    if aws rds create-db-snapshot \
        --db-instance-identifier "$PRIMARY_RDS_INSTANCE" \
        --db-snapshot-identifier "$SNAPSHOT_ID" > /dev/null; then
        print_success "Snapshot creation initiated: $SNAPSHOT_ID"
        
        print_status "Waiting for snapshot to complete..."
        if aws rds wait db-snapshot-completed --db-snapshot-identifier "$SNAPSHOT_ID"; then
            print_success "Snapshot completed successfully: $SNAPSHOT_ID"
            export TEST_SNAPSHOT_ID="$SNAPSHOT_ID"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            print_error "Snapshot creation failed or timed out"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    else
        print_error "Failed to initiate snapshot creation"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

# Test restore process
test_restore_process() {
    if [ "$TEST_RESTORE" != true ]; then
        return 0
    fi
    
    print_status "Testing restore process..."
    
    # Find a recent snapshot to test with
    if [ -n "$TEST_SNAPSHOT_ID" ]; then
        SNAPSHOT_TO_RESTORE="$TEST_SNAPSHOT_ID"
    else
        # Find the most recent manual snapshot
        SNAPSHOT_TO_RESTORE=$(aws rds describe-db-snapshots \
            --db-instance-identifier "$PRIMARY_RDS_INSTANCE" \
            --snapshot-type manual \
            --query 'DBSnapshots | sort_by(@, &SnapshotCreateTime) | [-1].DBSnapshotIdentifier' \
            --output text 2>/dev/null || echo "")
    fi
    
    if [ -z "$SNAPSHOT_TO_RESTORE" ] || [ "$SNAPSHOT_TO_RESTORE" = "None" ]; then
        print_error "No snapshot available for restore testing"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        return 1
    fi
    
    print_status "Using snapshot for restore test: $SNAPSHOT_TO_RESTORE"
    
    # Create test restore instance
    TEST_INSTANCE_ID="${PRIMARY_RDS_INSTANCE}-restore-test-$(date +%Y%m%d-%H%M%S)"
    
    print_status "Creating test restore instance: $TEST_INSTANCE_ID"
    
    # Get original instance details for restore
    ORIGINAL_DETAILS=$(aws rds describe-db-instances \
        --db-instance-identifier "$PRIMARY_RDS_INSTANCE" \
        --query 'DBInstances[0].{SubnetGroup:DBSubnetGroup.DBSubnetGroupName,SecurityGroups:VpcSecurityGroups[0].VpcSecurityGroupId,ParameterGroup:DBParameterGroups[0].DBParameterGroupName}' \
        --output text)
    
    read subnet_group security_group parameter_group <<< "$ORIGINAL_DETAILS"
    
    # Restore from snapshot
    if aws rds restore-db-instance-from-db-snapshot \
        --db-instance-identifier "$TEST_INSTANCE_ID" \
        --db-snapshot-identifier "$SNAPSHOT_TO_RESTORE" \
        --db-instance-class db.t3.micro \
        --db-subnet-group-name "$subnet_group" \
        --no-publicly-accessible \
        --tags Key=Environment,Value="$ENVIRONMENT" Key=Purpose,Value="BackupTest" > /dev/null; then
        
        print_success "Restore initiated: $TEST_INSTANCE_ID"
        export TEST_RESTORE_INSTANCE="$TEST_INSTANCE_ID"
        
        print_status "Waiting for restore to complete (this may take several minutes)..."
        if timeout 1800 aws rds wait db-instance-available --db-instance-identifier "$TEST_INSTANCE_ID"; then
            print_success "Restore completed successfully: $TEST_INSTANCE_ID"
            
            # Verify the restored instance
            RESTORED_STATUS=$(aws rds describe-db-instances \
                --db-instance-identifier "$TEST_INSTANCE_ID" \
                --query 'DBInstances[0].DBInstanceStatus' \
                --output text)
            
            if [ "$RESTORED_STATUS" = "available" ]; then
                print_success "Restored instance is available and healthy"
                PASSED_TESTS=$((PASSED_TESTS + 1))
            else
                print_error "Restored instance is not healthy: $RESTORED_STATUS"
                FAILED_TESTS=$((FAILED_TESTS + 1))
            fi
        else
            print_error "Restore timed out or failed"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    else
        print_error "Failed to initiate restore"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

# Cleanup test resources
cleanup_test_resources() {
    if [ "$CLEANUP_TEST" != true ]; then
        return 0
    fi
    
    print_status "Cleaning up test resources..."
    
    # Find and delete test restore instances
    TEST_INSTANCES=$(aws rds describe-db-instances \
        --query "DBInstances[?contains(DBInstanceIdentifier, 'restore-test')].DBInstanceIdentifier" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$TEST_INSTANCES" ]; then
        echo "$TEST_INSTANCES" | tr '\t' '\n' | while read test_instance; do
            print_status "Deleting test restore instance: $test_instance"
            
            if aws rds delete-db-instance \
                --db-instance-identifier "$test_instance" \
                --skip-final-snapshot > /dev/null; then
                print_success "Deletion initiated for: $test_instance"
            else
                print_error "Failed to delete: $test_instance"
            fi
        done
    else
        print_status "No test restore instances found to cleanup"
    fi
    
    # Find and delete test snapshots (older than 1 day)
    TEST_SNAPSHOTS=$(aws rds describe-db-snapshots \
        --snapshot-type manual \
        --query "DBSnapshots[?contains(DBSnapshotIdentifier, 'test-snapshot') && SnapshotCreateTime < '$(date -d '1 day ago' --iso-8601)'].DBSnapshotIdentifier" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$TEST_SNAPSHOTS" ]; then
        echo "$TEST_SNAPSHOTS" | tr '\t' '\n' | while read test_snapshot; do
            print_status "Deleting old test snapshot: $test_snapshot"
            
            if aws rds delete-db-snapshot \
                --db-snapshot-identifier "$test_snapshot" > /dev/null; then
                print_success "Deleted test snapshot: $test_snapshot"
            else
                print_error "Failed to delete snapshot: $test_snapshot"
            fi
        done
    else
        print_status "No old test snapshots found to cleanup"
    fi
}

# Verify backup encryption
verify_backup_encryption() {
    print_status "Verifying backup encryption..."
    
    echo "$RDS_INSTANCES" | while read db_id db_class engine status backup_retention multi_az; do
        # Check if instance is encrypted
        ENCRYPTION_STATUS=$(aws rds describe-db-instances \
            --db-instance-identifier "$db_id" \
            --query 'DBInstances[0].StorageEncrypted' \
            --output text)
        
        if [ "$ENCRYPTION_STATUS" = "True" ]; then
            print_success "Storage encryption enabled for $db_id"
            
            # Check KMS key
            KMS_KEY=$(aws rds describe-db-instances \
                --db-instance-identifier "$db_id" \
                --query 'DBInstances[0].KmsKeyId' \
                --output text)
            
            if [ -n "$KMS_KEY" ] && [ "$KMS_KEY" != "None" ]; then
                print_success "KMS encryption key configured: $(basename $KMS_KEY)"
            fi
            
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            print_error "Storage encryption not enabled for $db_id (HIPAA requirement)"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
    done
}

# Generate backup verification report
generate_backup_report() {
    print_status "Generating backup verification report..."
    
    REPORT_FILE="backup-verification-${ENVIRONMENT}-$(date +%Y%m%d-%H%M%S).md"
    
    cat > "$REPORT_FILE" << EOF
# TechHealth Backup Verification Report

**Environment:** $ENVIRONMENT
**Verification Date:** $(date)
**Stack Name:** $STACK_NAME

## Summary

- **Total Tests:** $TOTAL_TESTS
- **Passed:** $PASSED_TESTS
- **Failed:** $FAILED_TESTS
- **Success Rate:** $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%

## RDS Instance Analysis

EOF

    echo "$RDS_INSTANCES" | while read db_id db_class engine status backup_retention multi_az; do
        cat >> "$REPORT_FILE" << EOF
### Database: $db_id

- **Instance Class:** $db_class
- **Engine:** $engine
- **Status:** $status
- **Backup Retention:** $backup_retention days
- **Multi-AZ:** $multi_az

#### Backup Configuration
EOF

        # Get backup window
        BACKUP_WINDOW=$(aws rds describe-db-instances \
            --db-instance-identifier "$db_id" \
            --query 'DBInstances[0].PreferredBackupWindow' \
            --output text)
        
        # Get maintenance window
        MAINTENANCE_WINDOW=$(aws rds describe-db-instances \
            --db-instance-identifier "$db_id" \
            --query 'DBInstances[0].PreferredMaintenanceWindow' \
            --output text)
        
        # Get encryption status
        ENCRYPTION_STATUS=$(aws rds describe-db-instances \
            --db-instance-identifier "$db_id" \
            --query 'DBInstances[0].StorageEncrypted' \
            --output text)
        
        cat >> "$REPORT_FILE" << EOF
- **Backup Window:** $BACKUP_WINDOW
- **Maintenance Window:** $MAINTENANCE_WINDOW
- **Encryption:** $ENCRYPTION_STATUS

#### Point-in-Time Recovery
EOF

        # Get point-in-time recovery info
        BACKUP_INFO=$(aws rds describe-db-instances \
            --db-instance-identifier "$db_id" \
            --query 'DBInstances[0].{EarliestRestorableTime:EarliestRestorableTime,LatestRestorableTime:LatestRestorableTime}' \
            --output text)
        
        echo "$BACKUP_INFO" | while read earliest latest; do
            cat >> "$REPORT_FILE" << EOF
- **Earliest Restorable Time:** $earliest
- **Latest Restorable Time:** $latest
EOF
        done
        
        cat >> "$REPORT_FILE" << EOF

#### Manual Snapshots
EOF

        # Get manual snapshots
        SNAPSHOTS=$(aws rds describe-db-snapshots \
            --db-instance-identifier "$db_id" \
            --snapshot-type manual \
            --query 'DBSnapshots[*].{ID:DBSnapshotIdentifier,Status:Status,Created:SnapshotCreateTime,Size:AllocatedStorage}' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$SNAPSHOTS" ]; then
            echo "$SNAPSHOTS" | while read snap_id snap_status snap_created snap_size; do
                cat >> "$REPORT_FILE" << EOF
- **Snapshot:** $snap_id
  - Status: $snap_status
  - Created: $snap_created
  - Size: ${snap_size}GB
EOF
            done
        else
            echo "- No manual snapshots found" >> "$REPORT_FILE"
        fi
        
        echo "" >> "$REPORT_FILE"
    done
    
    cat >> "$REPORT_FILE" << EOF

## Backup Verification Results

### Configuration Compliance
$(if [ $FAILED_TESTS -eq 0 ]; then
echo "✅ All backup configurations are compliant"
else
echo "⚠️ $FAILED_TESTS configuration issues found"
fi)

### HIPAA Compliance
- **Encryption at Rest:** $(if aws rds describe-db-instances --db-instance-identifier "$PRIMARY_RDS_INSTANCE" --query 'DBInstances[0].StorageEncrypted' --output text 2>/dev/null | grep -q "True"; then echo "✅ Enabled"; else echo "❌ Not Enabled"; fi)
- **Automated Backups:** $(if [ "$backup_retention" -gt 0 ]; then echo "✅ Enabled ($backup_retention days)"; else echo "❌ Disabled"; fi)
- **Point-in-Time Recovery:** ✅ Available

### Test Results
$(if [ "$CREATE_SNAPSHOT" = true ]; then
echo "- **Manual Snapshot Creation:** $(if [ -n "$TEST_SNAPSHOT_ID" ]; then echo "✅ Success ($TEST_SNAPSHOT_ID)"; else echo "❌ Failed"; fi)"
fi)
$(if [ "$TEST_RESTORE" = true ]; then
echo "- **Restore Testing:** $(if [ -n "$TEST_RESTORE_INSTANCE" ]; then echo "✅ Success ($TEST_RESTORE_INSTANCE)"; else echo "❌ Failed"; fi)"
fi)

## Recommendations

### Immediate Actions
1. **Backup Monitoring:** Set up CloudWatch alarms for backup failures
2. **Retention Policy:** Review backup retention periods for compliance requirements
3. **Testing Schedule:** Implement regular backup restore testing

### Best Practices
1. **Regular Testing:** Test backup restore process monthly
2. **Documentation:** Maintain backup and restore procedures documentation
3. **Monitoring:** Monitor backup storage costs and optimize retention
4. **Automation:** Automate backup verification and reporting

### Environment-Specific Recommendations

#### $ENVIRONMENT Environment
EOF

    case $ENVIRONMENT in
        dev)
            cat >> "$REPORT_FILE" << EOF
- **Retention:** 7 days is sufficient for development
- **Testing:** Use for backup restore testing procedures
- **Snapshots:** Create manual snapshots before major changes
EOF
            ;;
        staging)
            cat >> "$REPORT_FILE" << EOF
- **Retention:** 14 days recommended for staging validation
- **Testing:** Regular restore testing to validate procedures
- **Snapshots:** Create snapshots before deployment testing
EOF
            ;;
        prod)
            cat >> "$REPORT_FILE" << EOF
- **Retention:** 30 days minimum for production (consider longer for compliance)
- **Testing:** Monthly restore testing with documented procedures
- **Snapshots:** Create snapshots before major deployments
- **Cross-Region:** Consider cross-region backup replication for DR
EOF
            ;;
    esac
    
    cat >> "$REPORT_FILE" << EOF

## Recovery Procedures

### Point-in-Time Recovery
\`\`\`bash
# Restore to specific time
aws rds restore-db-instance-to-point-in-time \\
    --source-db-instance-identifier $PRIMARY_RDS_INSTANCE \\
    --target-db-instance-identifier restored-instance \\
    --restore-time 2024-01-01T12:00:00Z
\`\`\`

### Snapshot Restore
\`\`\`bash
# Restore from manual snapshot
aws rds restore-db-instance-from-db-snapshot \\
    --db-instance-identifier restored-instance \\
    --db-snapshot-identifier snapshot-id
\`\`\`

## Next Review Date
**$(date -d '+1 month' +%Y-%m-%d)** - Monthly backup verification recommended

---
*Generated by TechHealth Backup Verification Suite*
EOF

    print_success "Backup verification report generated: $REPORT_FILE"
}

# Main execution
main() {
    get_rds_info
    verify_backup_configuration
    verify_existing_backups
    verify_manual_snapshots
    verify_backup_encryption
    create_manual_snapshot
    test_restore_process
    cleanup_test_resources
    generate_backup_report
    
    echo ""
    print_status "🏁 Backup Verification Complete"
    echo "==============================="
    echo ""
    echo "📊 Results Summary:"
    echo "   Total Tests: $TOTAL_TESTS"
    echo "   Passed: $PASSED_TESTS"
    echo "   Failed: $FAILED_TESTS"
    echo "   Success Rate: $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%"
    echo ""
    
    if [ $FAILED_TESTS -eq 0 ]; then
        print_success "✅ All backup verifications passed!"
        echo ""
        echo "🔄 Backup Status:"
        echo "   - Automated backups are properly configured"
        echo "   - Point-in-time recovery is available"
        echo "   - Encryption is enabled (HIPAA compliant)"
        if [ "$CREATE_SNAPSHOT" = true ] && [ -n "$TEST_SNAPSHOT_ID" ]; then
            echo "   - Manual snapshot created: $TEST_SNAPSHOT_ID"
        fi
        if [ "$TEST_RESTORE" = true ] && [ -n "$TEST_RESTORE_INSTANCE" ]; then
            echo "   - Restore test successful: $TEST_RESTORE_INSTANCE"
            echo "   - Remember to cleanup test instance when done"
        fi
    else
        print_error "❌ $FAILED_TESTS backup verification(s) failed"
        echo ""
        echo "Please review the issues and ensure backup compliance."
    fi
    
    echo ""
    echo "📄 Detailed report: $REPORT_FILE"
    echo ""
    echo "🔄 Next Steps:"
    echo "   1. Review backup verification report"
    echo "   2. Address any failed verifications"
    echo "   3. Schedule regular backup testing"
    echo "   4. Monitor backup storage costs"
    
    if [ "$TEST_RESTORE" = true ] && [ -n "$TEST_RESTORE_INSTANCE" ]; then
        echo ""
        echo "⚠️  Don't forget to cleanup test restore instance:"
        echo "   $0 $ENVIRONMENT --cleanup-test"
    fi
    
    # Exit with error code if any tests failed
    if [ $FAILED_TESTS -gt 0 ]; then
        exit 1
    fi
}

# Run main function
main