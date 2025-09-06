# AWS Security Implementation Guide

## Overview

This guide provides step-by-step instructions for implementing StartupCorp's AWS security infrastructure using the CDK stack. It covers deployment, validation, and post-deployment configuration.

## Prerequisites

### Required Tools

- AWS CLI v2 configured with appropriate credentials
- Node.js 18+ and npm
- AWS CDK CLI v2 (`npm install -g aws-cdk`)
- Git for version control

### Required Permissions

The deploying user/role needs:

- IAM full access (for creating users, groups, policies)
- CloudFormation full access (for CDK deployment)
- Lambda basic execution role (for custom resources)
- CloudWatch Logs access (for monitoring)

## 🚀 Deployment Process

### Step 1: Environment Setup

```bash
# Clone the repository
git clone [repository-url]
cd aws-iam-stack

# Install dependencies
npm install

# Verify CDK installation
cdk --version
```

### Step 2: Configure AWS Environment

```bash
# Configure AWS CLI (if not already done)
aws configure

# Verify AWS credentials
aws sts get-caller-identity

# Bootstrap CDK (one-time per account/region)
cdk bootstrap
```

### Step 3: Review Configuration

Before deployment, review the team structure in `lib/aws-iam-stack-stack.ts`:

```typescript
const teamStructure: TeamStructure = {
  developers: [
    {
      username: "dev1",
      email: "dev1@startupcorp.com",
      role: TeamRole.DEVELOPER,
      requiresMFA: true,
    },
    // Add/modify users as needed
  ],
  // ... other teams
};
```

### Step 4: Validate Stack

```bash
# Compile TypeScript
npm run build

# Run unit tests
npm test

# Generate CloudFormation template
npm run synth

# Review the generated template in cdk.out/
```

### Step 5: Deploy Stack

```bash
# Deploy to AWS
npm run deploy

# Or use CDK directly with confirmation
cdk deploy --require-approval never
```

### Step 6: Verify Deployment

```bash
# Check stack status
aws cloudformation describe-stacks --stack-name AwsSecurityStack

# List created IAM resources
aws iam list-groups
aws iam list-users
aws iam list-policies --scope Local
```

## 🔧 Post-Deployment Configuration

### Step 1: Root Account Security

**CRITICAL: Complete immediately after deployment**

1. **Enable MFA on root account** (see root-account-security-guide.md)
2. **Store root credentials securely**
3. **Test emergency access procedures**

### Step 2: User Onboarding Process

For each team member:

1. **Generate initial password**:

   ```bash
   aws iam create-login-profile --user-name [username] --password [temp-password] --password-reset-required
   ```

2. **Send secure credentials** to user via encrypted email/secure channel

3. **User first login process**:
   - Login with temporary password
   - Set new password (must meet policy requirements)
   - Set up MFA device
   - Test permissions

### Step 3: MFA Device Setup

Each user must configure MFA:

1. **Login to AWS Console**
2. **Navigate to IAM → Security Credentials**
3. **Assign MFA device** (virtual or hardware)
4. **Test MFA authentication**

### Step 4: Permission Validation

Test each role's permissions:

#### Developer Testing

```bash
# Test EC2 permissions
aws ec2 describe-instances --profile dev-user
aws ec2 start-instances --instance-ids i-xxx --profile dev-user

# Test S3 permissions
aws s3 ls s3://app-bucket --profile dev-user
aws s3 cp test.txt s3://app-bucket/ --profile dev-user
```

#### Operations Testing

```bash
# Test full EC2 access
aws ec2 describe-instances --profile ops-user
aws ec2 create-security-group --group-name test --description "test" --profile ops-user

# Test RDS access
aws rds describe-db-instances --profile ops-user
```

#### Finance Testing

```bash
# Test Cost Explorer access
aws ce get-cost-and-usage --time-period Start=2024-01-01,End=2024-01-31 --granularity MONTHLY --metrics BlendedCost --profile finance-user

# Test Budgets access
aws budgets describe-budgets --account-id [account-id] --profile finance-user
```

#### Analyst Testing

```bash
# Test read-only S3 access
aws s3 ls s3://data-bucket --profile analyst-user
aws s3 cp s3://data-bucket/file.csv . --profile analyst-user

# Test CloudWatch metrics
aws cloudwatch list-metrics --profile analyst-user
```

## 📊 Monitoring and Validation

### CloudTrail Setup

Ensure CloudTrail is logging all IAM activities:

```bash
# Check CloudTrail status
aws cloudtrail describe-trails

# Create trail if needed
aws cloudtrail create-trail --name security-audit-trail --s3-bucket-name [bucket-name]
```

### Security Monitoring

Set up CloudWatch alarms for:

```bash
# Root account usage
aws logs put-metric-filter \
  --log-group-name CloudTrail/SecurityAudit \
  --filter-name RootAccountUsage \
  --filter-pattern '{ $.userIdentity.type = "Root" }' \
  --metric-transformations \
    metricName=RootAccountUsage,metricNamespace=Security,metricValue=1
```

### Regular Audits

Monthly security checklist:

- [ ] Review IAM users and their last activity
- [ ] Check for unused access keys
- [ ] Validate MFA device status for all users
- [ ] Review CloudTrail logs for suspicious activity
- [ ] Test emergency access procedures
- [ ] Update team structure if needed

## 🔄 Updates and Maintenance

### Adding New Users

1. **Update team structure** in `lib/aws-iam-stack-stack.ts`
2. **Run tests**: `npm test`
3. **Deploy changes**: `npm run deploy`
4. **Complete user onboarding** process

### Modifying Permissions

1. **Update policy definitions** in `lib/constructs/iam-policies.ts`
2. **Test changes**: `npm test`
3. **Review policy simulation**:
   ```bash
   aws iam simulate-principal-policy \
     --policy-source-arn arn:aws:iam::account:user/username \
     --action-names s3:GetObject \
     --resource-arns arn:aws:s3:::bucket/*
   ```
4. **Deploy changes**: `npm run deploy`

### Stack Updates

```bash
# Check for drift
cdk diff

# Update dependencies
npm update

# Deploy updates
npm run deploy
```

## 🚨 Troubleshooting

### Common Issues

#### Deployment Failures

**Issue**: Stack deployment fails with permission errors
**Solution**:

- Verify deploying user has required permissions
- Check CloudFormation events for specific error details
- Ensure no resource naming conflicts

#### MFA Policy Issues

**Issue**: Users can't access resources after MFA policy deployment
**Solution**:

- Verify users have MFA devices configured
- Check policy conditions in `security-policies.ts`
- Test with MFA-enabled session

#### Permission Denied Errors

**Issue**: Users getting access denied for expected permissions
**Solution**:

- Check user group membership
- Verify policy attachments
- Use IAM policy simulator for testing
- Review CloudTrail logs for detailed error information

### Emergency Procedures

#### Stack Rollback

```bash
# Rollback to previous version
aws cloudformation cancel-update-stack --stack-name AwsSecurityStack
aws cloudformation continue-update-rollback --stack-name AwsSecurityStack
```

#### Emergency User Access

If IAM users are locked out:

1. Use root account (following emergency procedures)
2. Temporarily modify MFA policy
3. Fix user access issues
4. Restore MFA policy
5. Document incident

## 📞 Support and Contacts

### Internal Support

- **DevOps Team**: devops@startupcorp.com
- **Security Team**: security@startupcorp.com
- **Emergency Contact**: [24/7 phone number]

### AWS Support

- **Support Level**: Business/Enterprise
- **Case Priority**: High for security issues
- **Account ID**: [AWS Account ID]

## 📚 Additional Resources

- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [AWS Security Best Practices](https://aws.amazon.com/architecture/security-identity-compliance/)
- [StartupCorp Security Policies] - Internal documentation

---

**Document Version**: 1.0  
**Last Updated**: [Current Date]  
**Next Review**: [Date + 90 days]  
**Owner**: DevOps Team
