# Database Monitoring Configuration

## Overview

The TechHealth database construct provides basic CloudWatch monitoring by default. Enhanced monitoring and Performance Insights are disabled by default for cost optimization but can be enabled for production environments.

## Default Monitoring

The database construct includes the following monitoring features out of the box:

### CloudWatch Alarms

- **CPU Utilization**: Alerts when CPU usage exceeds 80%
- **Database Connections**: Alerts when connection count exceeds 80% of maximum
- **Free Storage Space**: Alerts when free storage drops below 2GB
- **Read Latency**: Alerts when read latency exceeds 200ms
- **Write Latency**: Alerts when write latency exceeds 200ms

### CloudWatch Logs

- Error logs
- General logs
- Slow query logs

## Enhanced Monitoring

Enhanced monitoring provides OS-level metrics with up to 1-second granularity.

### Instance Class Requirements

Enhanced monitoring is available for all RDS instance classes but may have different cost implications:

- **db.t3.micro**: Supported (default instance class)
- **db.t3.small**: Supported
- **db.t3.medium and above**: Supported with better performance

### Enabling Enhanced Monitoring

#### Via AWS Console

1. Navigate to RDS in AWS Console
2. Select your database instance
3. Click "Modify"
4. Under "Monitoring", set "Enable enhanced monitoring" to "Yes"
5. Choose monitoring interval (1, 5, 10, 15, 30, or 60 seconds)
6. Apply changes

#### Via AWS CLI

```bash
aws rds modify-db-instance \
    --db-instance-identifier your-db-instance-id \
    --monitoring-interval 60 \
    --monitoring-role-arn arn:aws:iam::account:role/rds-monitoring-role
```

#### Via CDK (Future Enhancement)

```typescript
// Example of how to enable enhanced monitoring in CDK
new DatabaseConstruct(this, "Database", {
  // ... other props
  enableEnhancedMonitoring: true,
  monitoringInterval: 60, // seconds
});
```

## Performance Insights

Performance Insights provides database performance monitoring with query-level insights.

### Instance Class Requirements

Performance Insights has specific instance class requirements:

#### ❌ Not Supported

- db.t2.micro
- db.t2.small
- db.t3.micro (default)
- db.t3.small
- db.t4g.micro
- db.t4g.small

#### ✅ Supported

- db.t3.medium and above
- db.t4g.medium and above
- All other instance classes (m5, r5, etc.)

### Enabling Performance Insights

#### Via AWS Console

1. Navigate to RDS in AWS Console
2. Select your database instance
3. Click "Modify"
4. Under "Performance Insights", set "Enable Performance Insights" to "Yes"
5. Choose retention period (7 days free, longer periods incur charges)
6. Apply changes

#### Via AWS CLI

```bash
aws rds modify-db-instance \
    --db-instance-identifier your-db-instance-id \
    --enable-performance-insights \
    --performance-insights-retention-period 7
```

## Cost Considerations

### Enhanced Monitoring Costs

- Based on data transfer from RDS to CloudWatch Logs
- Approximately $0.50 per million requests
- 1-second granularity generates more data than 60-second granularity

### Performance Insights Costs

- 7 days retention: Free
- Longer retention: $0.02 per vCPU per day
- Additional charges for extended retention periods

## Production Recommendations

### For Development/Testing

- Use default monitoring (current configuration)
- Enable CloudWatch alarms for basic monitoring
- Consider 60-second enhanced monitoring if detailed OS metrics are needed

### For Production

1. **Upgrade Instance Class**: Consider db.t3.medium or larger for Performance Insights
2. **Enable Enhanced Monitoring**: Use 60-second interval for cost balance
3. **Enable Performance Insights**: Use 7-day retention initially
4. **Set Up Alerts**: Configure SNS notifications for CloudWatch alarms
5. **Monitor Costs**: Review CloudWatch and Performance Insights charges regularly

## Getting Monitoring Guidance

The database construct provides a method to check monitoring capabilities:

```typescript
const database = new DatabaseConstruct(this, "Database", {
  /* props */
});
const guidance = database.getEnhancedMonitoringGuidance();

console.log(
  "Can enable Performance Insights:",
  guidance.canEnablePerformanceInsights
);
console.log(
  "Can enable Enhanced Monitoring:",
  guidance.canEnableEnhancedMonitoring
);
console.log("Recommendations:", guidance.recommendations);
```

## Troubleshooting

### Common Issues

1. **Performance Insights Not Available**

   - Check instance class compatibility
   - Upgrade to db.t3.medium or larger

2. **Enhanced Monitoring Not Working**

   - Verify IAM role permissions
   - Check monitoring interval setting
   - Ensure CloudWatch Logs permissions

3. **High Monitoring Costs**
   - Increase monitoring interval (reduce frequency)
   - Review retention periods
   - Consider disabling for non-production environments

### Useful Commands

```bash
# Check current monitoring configuration
aws rds describe-db-instances --db-instance-identifier your-db-instance-id

# View CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name CPUUtilization \
    --dimensions Name=DBInstanceIdentifier,Value=your-db-instance-id \
    --start-time 2023-01-01T00:00:00Z \
    --end-time 2023-01-01T23:59:59Z \
    --period 3600 \
    --statistics Average
```

## References

- [AWS RDS Enhanced Monitoring Documentation](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_Monitoring.OS.html)
- [AWS RDS Performance Insights Documentation](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PerfInsights.html)
- [CloudWatch Pricing](https://aws.amazon.com/cloudwatch/pricing/)
