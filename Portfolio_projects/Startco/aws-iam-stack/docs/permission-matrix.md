# AWS Security Implementation - Permission Matrix

## Overview

This document provides a comprehensive matrix of permissions for each team role in the AWS security implementation. It serves as a reference for understanding access controls and ensuring proper least-privilege implementation.

## 📊 Role-Based Access Control Matrix

### Legend

- ✅ **Full Access** - Complete permissions for the service/resource
- 🔍 **Read Only** - View and describe permissions only
- 📝 **Limited Write** - Specific write permissions with restrictions
- ❌ **No Access** - No permissions granted
- 🔒 **Conditional** - Access depends on specific conditions (e.g., MFA)

## 🎯 Permission Matrix by AWS Service

| AWS Service         | Developer      | Operations   | Finance          | Analyst          | Notes                                |
| ------------------- | -------------- | ------------ | ---------------- | ---------------- | ------------------------------------ |
| **EC2**             | 📝 Limited     | ✅ Full      | 🔍 Read Only     | ❌ No Access     | Developers: start/stop/describe only |
| **S3**              | 📝 App Buckets | ✅ Full      | 🔍 List Only     | 🔍 Data Buckets  | Resource-specific access patterns    |
| **IAM**             | ❌ No Access   | ❌ No Access | ❌ No Access     | ❌ No Access     | Managed centrally via this stack     |
| **CloudWatch**      | 🔍 Logs Only   | ✅ Full      | ❌ No Access     | 🔍 Metrics Only  | Role-specific monitoring access      |
| **RDS**             | ❌ No Access   | ✅ Full      | 🔍 Describe Only | 🔍 Describe Only | Operations manages databases         |
| **Cost Explorer**   | ❌ No Access   | ❌ No Access | ✅ Full          | ❌ No Access     | Finance team exclusive               |
| **AWS Budgets**     | ❌ No Access   | ❌ No Access | ✅ Full          | ❌ No Access     | Finance team exclusive               |
| **Systems Manager** | ❌ No Access   | ✅ Full      | ❌ No Access     | ❌ No Access     | Operations team exclusive            |

## 👥 Detailed Role Permissions

### 🔧 Developer Role Permissions

**Purpose**: Enable development team to manage application infrastructure and troubleshoot issues.

#### EC2 Permissions

| Action                       | Permission | Resource Scope | Justification                          |
| ---------------------------- | ---------- | -------------- | -------------------------------------- |
| `ec2:DescribeInstances`      | ✅ Allow   | `*`            | Need to view instance status           |
| `ec2:DescribeInstanceStatus` | ✅ Allow   | `*`            | Monitor instance health                |
| `ec2:StartInstances`         | ✅ Allow   | `*`            | Start stopped development instances    |
| `ec2:StopInstances`          | ✅ Allow   | `*`            | Stop instances to save costs           |
| `ec2:RebootInstances`        | ✅ Allow   | `*`            | Restart unresponsive instances         |
| `ec2:RunInstances`           | ❌ Deny    | `*`            | Prevent unauthorized instance creation |
| `ec2:TerminateInstances`     | ❌ Deny    | `*`            | Prevent accidental data loss           |

#### S3 Permissions

| Action            | Permission | Resource Scope         | Justification              |
| ----------------- | ---------- | ---------------------- | -------------------------- |
| `s3:ListBucket`   | ✅ Allow   | `arn:aws:s3:::app-*`   | List application buckets   |
| `s3:GetObject`    | ✅ Allow   | `arn:aws:s3:::app-*/*` | Read application files     |
| `s3:PutObject`    | ✅ Allow   | `arn:aws:s3:::app-*/*` | Deploy application updates |
| `s3:DeleteObject` | ✅ Allow   | `arn:aws:s3:::app-*/*` | Clean up old files         |
| `s3:*`            | ❌ Deny    | `arn:aws:s3:::data-*`  | No access to data buckets  |

#### CloudWatch Logs Permissions

| Action                    | Permission | Resource Scope | Justification              |
| ------------------------- | ---------- | -------------- | -------------------------- |
| `logs:DescribeLogGroups`  | ✅ Allow   | `*`            | View available log groups  |
| `logs:DescribeLogStreams` | ✅ Allow   | `*`            | View log streams           |
| `logs:GetLogEvents`       | ✅ Allow   | `*`            | Read application logs      |
| `logs:FilterLogEvents`    | ✅ Allow   | `*`            | Search through logs        |
| `logs:CreateLogGroup`     | ❌ Deny    | `*`            | Prevent log group creation |

### ⚙️ Operations Role Permissions

**Purpose**: Enable operations team to manage all infrastructure and maintain system health.

#### EC2 Permissions

| Action  | Permission | Resource Scope | Justification                |
| ------- | ---------- | -------------- | ---------------------------- |
| `ec2:*` | ✅ Allow   | `*`            | Full EC2 management required |

#### CloudWatch Permissions

| Action         | Permission | Resource Scope | Justification                |
| -------------- | ---------- | -------------- | ---------------------------- |
| `cloudwatch:*` | ✅ Allow   | `*`            | Full monitoring capabilities |
| `logs:*`       | ✅ Allow   | `*`            | Complete log management      |

#### Systems Manager Permissions

| Action          | Permission | Resource Scope | Justification                       |
| --------------- | ---------- | -------------- | ----------------------------------- |
| `ssm:*`         | ✅ Allow   | `*`            | Session Manager and parameter store |
| `ssmmessages:*` | ✅ Allow   | `*`            | Session Manager communication       |
| `ec2messages:*` | ✅ Allow   | `*`            | EC2 instance communication          |

#### RDS Permissions

| Action  | Permission | Resource Scope | Justification            |
| ------- | ---------- | -------------- | ------------------------ |
| `rds:*` | ✅ Allow   | `*`            | Full database management |

### 💰 Finance Role Permissions

**Purpose**: Enable finance team to monitor costs, manage budgets, and track resource usage.

#### Cost Management Permissions

| Action      | Permission | Resource Scope | Justification             |
| ----------- | ---------- | -------------- | ------------------------- |
| `ce:*`      | ✅ Allow   | `*`            | Full Cost Explorer access |
| `cur:*`     | ✅ Allow   | `*`            | Cost and Usage Reports    |
| `budgets:*` | ✅ Allow   | `*`            | Budget management         |

#### Resource Visibility Permissions

| Action                 | Permission | Resource Scope | Justification                          |
| ---------------------- | ---------- | -------------- | -------------------------------------- |
| `ec2:Describe*`        | ✅ Allow   | `*`            | View EC2 resources for cost allocation |
| `s3:ListAllMyBuckets`  | ✅ Allow   | `*`            | View S3 buckets for cost tracking      |
| `s3:GetBucketLocation` | ✅ Allow   | `*`            | Determine bucket regions               |
| `rds:Describe*`        | ✅ Allow   | `*`            | View RDS resources for cost allocation |
| `tag:GetResources`     | ✅ Allow   | `*`            | Resource tagging for cost allocation   |
| `tag:GetTagKeys`       | ✅ Allow   | `*`            | Available tag keys                     |
| `tag:GetTagValues`     | ✅ Allow   | `*`            | Available tag values                   |

### 📊 Analyst Role Permissions

**Purpose**: Enable data analysts to access data resources and generate reports without modifying infrastructure.

#### S3 Data Access Permissions

| Action            | Permission | Resource Scope          | Justification             |
| ----------------- | ---------- | ----------------------- | ------------------------- |
| `s3:ListBucket`   | ✅ Allow   | `arn:aws:s3:::data-*`   | List data buckets         |
| `s3:GetObject`    | ✅ Allow   | `arn:aws:s3:::data-*/*` | Read data files           |
| `s3:PutObject`    | ❌ Deny    | `arn:aws:s3:::data-*/*` | Prevent data modification |
| `s3:DeleteObject` | ❌ Deny    | `arn:aws:s3:::data-*/*` | Prevent data deletion     |

#### Database Access Permissions

| Action                    | Permission | Resource Scope | Justification             |
| ------------------------- | ---------- | -------------- | ------------------------- |
| `rds:DescribeDBInstances` | ✅ Allow   | `*`            | View database instances   |
| `rds:DescribeDBClusters`  | ✅ Allow   | `*`            | View database clusters    |
| `rds:CreateDBInstance`    | ❌ Deny    | `*`            | Prevent database creation |

#### CloudWatch Metrics Permissions

| Action                           | Permission | Resource Scope | Justification             |
| -------------------------------- | ---------- | -------------- | ------------------------- |
| `cloudwatch:GetMetricStatistics` | ✅ Allow   | `*`            | Retrieve metrics data     |
| `cloudwatch:ListMetrics`         | ✅ Allow   | `*`            | List available metrics    |
| `cloudwatch:GetMetricData`       | ✅ Allow   | `*`            | Batch metric retrieval    |
| `cloudwatch:PutMetricData`       | ❌ Deny    | `*`            | Prevent metric publishing |

## 🔒 Security Policies Applied to All Roles

### MFA Enforcement Policy

All users are subject to the MFA enforcement policy:

| Condition                            | Effect | Actions Allowed Without MFA                                                                                                                                                     |
| ------------------------------------ | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `aws:MultiFactorAuthPresent = false` | Deny   | `iam:CreateVirtualMFADevice`<br>`iam:EnableMFADevice`<br>`iam:GetUser`<br>`iam:ListMFADevices`<br>`iam:ListVirtualMFADevices`<br>`iam:ResyncMFADevice`<br>`sts:GetSessionToken` |

### Password Policy Requirements

All users must comply with the account password policy:

| Requirement               | Value         | Justification                          |
| ------------------------- | ------------- | -------------------------------------- |
| Minimum Length            | 12 characters | Industry standard for strong passwords |
| Uppercase Required        | Yes           | Complexity requirement                 |
| Lowercase Required        | Yes           | Complexity requirement                 |
| Numbers Required          | Yes           | Complexity requirement                 |
| Symbols Required          | Yes           | Maximum complexity                     |
| Password Age              | 90 days       | Regular rotation requirement           |
| Password Reuse Prevention | 12 passwords  | Prevent password cycling               |
| Allow Users to Change     | Yes           | User autonomy for password management  |

## 🚫 Explicitly Denied Permissions

### All Roles - Prohibited Actions

| Service           | Prohibited Actions              | Reason                               |
| ----------------- | ------------------------------- | ------------------------------------ |
| **IAM**           | All user/role/policy management | Centrally managed via CDK            |
| **Organizations** | All organization management     | Account structure managed centrally  |
| **Billing**       | Payment method changes          | Finance team uses Cost Explorer only |
| **Support**       | Support case creation           | Managed through designated channels  |
| **Root Account**  | Any root account actions        | Emergency use only                   |

### Role-Specific Restrictions

#### Developer Restrictions

- Cannot create/terminate EC2 instances
- Cannot access data S3 buckets
- Cannot modify RDS instances
- Cannot create IAM resources

#### Operations Restrictions

- Cannot access Cost Explorer
- Cannot modify billing settings
- Cannot create IAM users/roles

#### Finance Restrictions

- Cannot modify infrastructure resources
- Cannot access application data
- Cannot perform operational tasks

#### Analyst Restrictions

- Cannot modify any infrastructure
- Cannot write to data buckets
- Cannot access application buckets
- Cannot perform administrative tasks

## 🔍 Permission Testing and Validation

### Automated Testing

Our permission matrix is validated through automated testing:

```bash
# Test all role permissions
npm run test:permissions:all

# Test specific role
npm run test:permissions:developer
npm run test:permissions:operations
npm run test:permissions:finance
npm run test:permissions:analyst
```

### Manual Validation

Each permission can be tested using AWS CLI:

```bash
# Test developer EC2 permissions
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::ACCOUNT:user/dev1 \
  --action-names ec2:DescribeInstances \
  --resource-arns "*"
```

### Permission Boundaries

Future enhancement: Implement permission boundaries for additional security:

```typescript
const permissionBoundary = new iam.ManagedPolicy(this, "PermissionBoundary", {
  statements: [
    new iam.PolicyStatement({
      effect: iam.Effect.DENY,
      actions: ["iam:*"],
      resources: ["*"],
    }),
  ],
});
```

## 📋 Compliance and Audit

### Regular Reviews

| Review Type      | Frequency | Responsible Team | Documentation             |
| ---------------- | --------- | ---------------- | ------------------------- |
| Access Review    | Monthly   | Security Team    | Access review logs        |
| Permission Audit | Quarterly | DevOps Team      | Permission test results   |
| Policy Updates   | As needed | DevOps Team      | Change management records |
| Compliance Check | Annually  | Security Team    | Compliance reports        |

### Audit Trail

All permission changes are tracked through:

- CloudTrail logs for all IAM actions
- CDK deployment logs
- Git commit history for policy changes
- Automated testing results

### Compliance Frameworks

This permission matrix supports compliance with:

- **SOC 2 Type II**: Access controls and monitoring
- **ISO 27001**: Information security management
- **AWS Well-Architected**: Security pillar best practices
- **CIS Controls**: Identity and access management

## 🔄 Permission Matrix Maintenance

### Update Process

1. **Identify Need**: Business requirement or security review
2. **Design Change**: Update permission matrix documentation
3. **Code Update**: Modify CDK constructs
4. **Testing**: Run automated permission tests
5. **Review**: Security team approval
6. **Deploy**: Apply changes through CDK
7. **Validate**: Confirm permissions work as expected
8. **Document**: Update this matrix

### Version Control

| Version | Date       | Changes                   | Author      |
| ------- | ---------- | ------------------------- | ----------- |
| 1.0.0   | 2025-01-08 | Initial permission matrix | DevOps Team |

---

**Document Classification**: Internal Use  
**Last Updated**: January 8, 2025  
**Next Review**: April 8, 2025  
**Owner**: DevOps Team  
**Approved By**: Security Team
