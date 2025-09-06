# AWS Root Account Security Guide

## Overview

This document provides comprehensive guidelines for securing the AWS root account for StartupCorp's AWS environment. The root account is the most privileged account in your AWS organization and requires the highest level of security protection.

## 🚨 Critical Security Principles

### 1. Root Account Usage Restrictions

**NEVER use the root account for day-to-day operations.**

The root account should only be used for:

- Initial AWS account setup
- Billing and account management tasks that require root access
- Emergency access when IAM users are locked out
- Specific AWS services that require root account access (rare cases)

### 2. Emergency Access Only

Root account access should be treated as a "break glass" emergency procedure with proper logging and justification.

## 🔐 Root Account MFA Setup Process

### Step 1: Enable MFA on Root Account

1. **Sign in to AWS Console** using root account credentials
2. **Navigate to IAM Console** → Security Credentials
3. **Click "Assign MFA device"** next to "Multi-factor authentication (MFA)"
4. **Choose MFA device type:**
   - **Recommended**: Hardware MFA device (YubiKey, etc.)
   - **Alternative**: Virtual MFA device (Google Authenticator, Authy)
   - **Enterprise**: SMS MFA (less secure, not recommended)

### Step 2: Configure Virtual MFA Device (if chosen)

1. **Install authenticator app** on secure mobile device
   - Google Authenticator (recommended)
   - Authy
   - Microsoft Authenticator
2. **Scan QR code** displayed in AWS console
3. **Enter two consecutive MFA codes** to verify setup
4. **Save recovery codes** in secure location

### Step 3: Configure Hardware MFA Device (recommended)

1. **Insert hardware MFA device** (e.g., YubiKey)
2. **Follow device-specific setup instructions**
3. **Test MFA authentication** with device
4. **Document device serial number** for recovery purposes

### Step 4: Verify MFA Setup

1. **Sign out** of AWS console
2. **Sign back in** using root credentials + MFA
3. **Confirm successful authentication**
4. **Document MFA setup completion** with timestamp

## 🔒 Secure Credential Storage Guidelines

### Root Account Password Requirements

- **Minimum 20 characters** (longer than standard IAM users)
- **Complex password** with uppercase, lowercase, numbers, symbols
- **Unique password** not used anywhere else
- **Generated using password manager** (recommended)

### Credential Storage Best Practices

#### Primary Storage (Required)

- **Enterprise password manager** (1Password Business, Bitwarden Business)
- **Encrypted vault** with team access controls
- **Multi-person access** (minimum 2 authorized personnel)

#### Backup Storage (Required)

- **Physical secure location** (company safe, bank safety deposit box)
- **Encrypted USB drive** or printed document in sealed envelope
- **Separate location** from primary storage
- **Access log** tracking who accessed credentials when

#### Access Control Matrix

| Role             | Primary Access | Backup Access | MFA Device | Justification Required |
| ---------------- | -------------- | ------------- | ---------- | ---------------------- |
| CTO              | ✅             | ✅            | Hardware   | Emergency only         |
| DevOps Lead      | ✅             | ❌            | Hardware   | Emergency + Billing    |
| Security Officer | ✅             | ✅            | Hardware   | Audit + Emergency      |

### Credential Rotation Schedule

- **Password rotation**: Every 90 days minimum
- **MFA device review**: Every 180 days
- **Access audit**: Monthly
- **Emergency drill**: Quarterly

## 🚨 Emergency Access Procedures

### When to Use Root Account

**Approved scenarios:**

1. **IAM system failure** - All IAM users locked out
2. **Billing emergencies** - Payment issues requiring immediate attention
3. **Account recovery** - Support case requiring root account verification
4. **Security incident** - Compromise requiring immediate account lockdown

**Prohibited scenarios:**

- Daily administrative tasks
- Resource provisioning
- User management
- Development or testing activities

### Emergency Access Protocol

#### Before Access

1. **Document justification** in incident ticket
2. **Get approval** from two authorized personnel
3. **Notify security team** of intended root access
4. **Prepare access log** for documentation

#### During Access

1. **Use secure, monitored workstation**
2. **Enable CloudTrail logging** (if not already enabled)
3. **Limit session duration** to minimum required
4. **Document all actions taken**
5. **Avoid unnecessary navigation** in console

#### After Access

1. **Log all actions taken** in incident documentation
2. **Review CloudTrail logs** for session activity
3. **Notify team** of access completion
4. **Schedule security review** if needed
5. **Update procedures** based on lessons learned

## 📋 Security Monitoring and Auditing

### CloudTrail Configuration

Ensure CloudTrail is configured to log root account activity:

```json
{
  "eventName": "*",
  "userIdentity.type": "Root",
  "sourceIPAddress": "*",
  "userAgent": "*"
}
```

### Automated Alerts

Set up CloudWatch alarms for:

- Root account console sign-ins
- Root account API calls
- MFA device changes
- Password changes

### Monthly Security Review Checklist

- [ ] Review root account CloudTrail logs
- [ ] Verify MFA device functionality
- [ ] Check credential storage access logs
- [ ] Validate emergency contact information
- [ ] Test emergency access procedures
- [ ] Update documentation as needed

## 🔧 Implementation Checklist

### Initial Setup

- [ ] Enable MFA on root account
- [ ] Store credentials in enterprise password manager
- [ ] Create backup credential storage
- [ ] Document emergency procedures
- [ ] Set up CloudTrail logging
- [ ] Configure security alerts

### Ongoing Maintenance

- [ ] Monthly access reviews
- [ ] Quarterly emergency drills
- [ ] 90-day password rotation
- [ ] Annual procedure updates
- [ ] Staff training on procedures

## 📞 Emergency Contacts

### Internal Contacts

- **Primary**: CTO - [phone] (24/7)
- **Secondary**: DevOps Lead - [phone] (business hours)
- **Security**: Security Officer - [phone] (24/7)

### AWS Support

- **Enterprise Support**: 1-800-xxx-xxxx
- **Account ID**: [AWS Account ID]
- **Support Case Priority**: High/Critical for root account issues

## 📚 Additional Resources

- [AWS Root Account Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html#lock-away-credentials)
- [AWS MFA Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_mfa.html)
- [AWS CloudTrail User Guide](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/)
- [StartupCorp Security Policy] - Internal document

---

**Document Version**: 1.0  
**Last Updated**: [Current Date]  
**Next Review**: [Date + 90 days]  
**Owner**: DevOps Team  
**Approved By**: CTO, Security Officer
