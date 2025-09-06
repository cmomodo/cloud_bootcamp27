# AWS Account Access - User Onboarding Guide

## Welcome to StartupCorp's AWS Environment! 🎉

This guide will help you set up secure access to our AWS environment. Please follow all steps carefully to ensure proper security configuration.

## 📋 Prerequisites

Before you begin, ensure you have:

- [ ] Received your AWS username and temporary password from the DevOps team
- [ ] A smartphone or tablet for MFA setup
- [ ] Access to your corporate email for notifications
- [ ] Understanding of your assigned role and responsibilities

## 🔐 Step 1: Initial Login

### 1.1 Access the AWS Console

1. **Navigate to the AWS Console**: [https://console.aws.amazon.com/](https://console.aws.amazon.com/)
2. **Select "IAM user"** (not root user)
3. **Enter Account ID**: `[Your AWS Account ID will be provided]`
4. **Click "Next"**

### 1.2 First Login

1. **Enter your username**: As provided by the DevOps team
2. **Enter temporary password**: As provided by the DevOps team
3. **Click "Sign In"**

### 1.3 Change Your Password

You'll be prompted to change your password immediately:

1. **Enter your temporary password** in "Old password"
2. **Create a new password** that meets these requirements:
   - Minimum 12 characters
   - At least one uppercase letter (A-Z)
   - At least one lowercase letter (a-z)
   - At least one number (0-9)
   - At least one special character (!@#$%^&\*)
3. **Confirm your new password**
4. **Click "Confirm password change"**

> 💡 **Password Tips**: Use a password manager to generate and store a strong, unique password.

## 📱 Step 2: Set Up Multi-Factor Authentication (MFA)

**⚠️ CRITICAL: MFA setup is mandatory. You cannot access AWS resources without MFA configured.**

### 2.1 Navigate to MFA Setup

1. After password change, you'll see the AWS Console
2. **Click on your username** in the top-right corner
3. **Select "Security credentials"**
4. **Scroll down to "Multi-factor authentication (MFA)"**
5. **Click "Assign MFA device"**

### 2.2 Choose MFA Device Type

You have two options:

#### Option A: Virtual MFA Device (Recommended for most users)

- Uses smartphone app (Google Authenticator, Authy, etc.)
- Free and convenient
- Works offline

#### Option B: Hardware MFA Device (For high-security roles)

- Physical device (YubiKey, etc.)
- Most secure option
- Provided by company for Operations team

### 2.3 Set Up Virtual MFA Device

If you chose Virtual MFA Device:

1. **Select "Virtual MFA device"**
2. **Click "Continue"**
3. **Install an authenticator app** on your smartphone:

   - **Google Authenticator** (recommended)
   - **Authy**
   - **Microsoft Authenticator**
   - **1Password** (if you have a subscription)

4. **Scan the QR code** with your authenticator app
5. **Enter two consecutive MFA codes** from your app:
   - Wait for the first code to appear
   - Enter it in "MFA code 1"
   - Wait for the code to refresh (about 30 seconds)
   - Enter the new code in "MFA code 2"
6. **Click "Assign MFA"**

### 2.4 Set Up Hardware MFA Device

If you chose Hardware MFA Device:

1. **Select "Hardware MFA device"**
2. **Click "Continue"**
3. **Enter the device serial number** (found on the device)
4. **Insert the device** and press the button
5. **Enter the first authentication code**
6. **Wait for the next code** and enter it
7. **Click "Assign MFA"**

### 2.5 Verify MFA Setup

1. **Sign out** of the AWS Console
2. **Sign back in** using your username and password
3. **Enter the MFA code** when prompted
4. **Confirm successful login**

> ✅ **Success!** You should now see the AWS Console with your role-specific permissions.

## 🎯 Step 3: Understand Your Role and Permissions

Your access level depends on your assigned role:

### 🔧 Developer Role

**What you can do:**

- Start, stop, and reboot EC2 instances
- Access application S3 buckets (app-\*)
- View CloudWatch logs for troubleshooting
- Describe EC2 instances and their status

**What you cannot do:**

- Create or terminate EC2 instances
- Access data S3 buckets (data-\*)
- Modify IAM users, roles, or policies
- Access billing or cost information

### ⚙️ Operations Role

**What you can do:**

- Full EC2 management (create, modify, terminate instances)
- Complete CloudWatch access (metrics, alarms, dashboards)
- Systems Manager access (Session Manager, Parameter Store)
- Full RDS management
- All S3 bucket access

**What you cannot do:**

- Access billing or cost information
- Modify IAM users, roles, or policies
- Access Cost Explorer or Budgets

### 💰 Finance Role

**What you can do:**

- Full Cost Explorer access
- AWS Budgets management
- View all resources for cost allocation
- Access cost and usage reports

**What you cannot do:**

- Modify any infrastructure resources
- Access application or data files
- Start, stop, or create EC2 instances
- Modify IAM users, roles, or policies

### 📊 Analyst Role

**What you can do:**

- Read data from S3 data buckets (data-\*)
- View CloudWatch metrics
- Describe RDS instances and clusters
- Access read-only database information

**What you cannot do:**

- Modify any data or infrastructure
- Access application S3 buckets (app-\*)
- Create, start, or stop EC2 instances
- Write to any S3 buckets

## 🔧 Step 4: Test Your Access

### 4.1 Basic Console Navigation

1. **Explore the AWS Console** - familiarize yourself with the interface
2. **Check the services menu** - you'll only see services you have access to
3. **Try accessing a service** relevant to your role

### 4.2 Role-Specific Testing

#### For Developers:

```bash
# Test EC2 access (if you have AWS CLI configured)
aws ec2 describe-instances

# Test S3 access to app buckets
aws s3 ls s3://app-bucket-name
```

#### For Operations:

```bash
# Test full EC2 access
aws ec2 describe-instances
aws ec2 describe-security-groups

# Test CloudWatch access
aws cloudwatch list-metrics
```

#### For Finance:

```bash
# Test Cost Explorer access
aws ce get-cost-and-usage --time-period Start=2024-01-01,End=2024-01-31 --granularity MONTHLY --metrics BlendedCost

# Test budget access
aws budgets describe-budgets --account-id YOUR-ACCOUNT-ID
```

#### For Analysts:

```bash
# Test data bucket access
aws s3 ls s3://data-bucket-name

# Test CloudWatch metrics
aws cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name CPUUtilization --start-time 2024-01-01T00:00:00Z --end-time 2024-01-01T23:59:59Z --period 3600 --statistics Average
```

## 🚨 Security Best Practices

### Password Security

- **Use a unique password** - never reuse your AWS password elsewhere
- **Use a password manager** - to generate and store strong passwords
- **Change password regularly** - you'll be prompted every 90 days
- **Never share your password** - with anyone, including IT support

### MFA Security

- **Keep your MFA device secure** - treat it like a key to your house
- **Have a backup plan** - save recovery codes in a secure location
- **Report lost devices immediately** - contact DevOps team right away
- **Don't share MFA codes** - never give codes to anyone

### General Security

- **Always sign out** - when finished using AWS Console
- **Use secure networks** - avoid public Wi-Fi for AWS access
- **Keep software updated** - browser and MFA apps should be current
- **Report suspicious activity** - contact security team immediately

## 🆘 Troubleshooting Common Issues

### Cannot Login

**Problem**: "Invalid username or password"
**Solutions**:

- Verify you're using the correct Account ID
- Check that you're selecting "IAM user" not "Root user"
- Ensure Caps Lock is off
- Contact DevOps team if password was recently changed

### MFA Issues

**Problem**: "Invalid MFA code"
**Solutions**:

- Ensure your device's time is synchronized
- Wait for a fresh code (don't reuse old codes)
- Check that you're using the correct authenticator app
- Try entering the code more quickly

**Problem**: "Lost MFA device"
**Solutions**:

- Contact DevOps team immediately
- Provide your username and employee ID
- You may need manager approval for MFA reset
- Temporary access may be provided for urgent needs

### Permission Denied

**Problem**: "You don't have permission to access this resource"
**Solutions**:

- Verify you're trying to access resources appropriate for your role
- Check that MFA is working (sign out and back in)
- Contact DevOps team if you believe you should have access
- Review the permission matrix in this guide

### Password Policy Issues

**Problem**: "Password doesn't meet requirements"
**Solutions**:

- Ensure password is at least 12 characters
- Include uppercase, lowercase, numbers, and symbols
- Don't reuse any of your last 12 passwords
- Use a password manager to generate compliant passwords

## 📞 Getting Help

### Internal Support

- **DevOps Team**: devops@startupcorp.com
- **Security Team**: security@startupcorp.com
- **IT Helpdesk**: helpdesk@startupcorp.com
- **Emergency Contact**: [24/7 phone number]

### Self-Service Resources

- **AWS Documentation**: [https://docs.aws.amazon.com/](https://docs.aws.amazon.com/)
- **Internal Wiki**: [Internal documentation link]
- **Training Materials**: [Training portal link]

### Emergency Procedures

If you suspect a security incident:

1. **Immediately sign out** of all AWS sessions
2. **Change your password** if you suspect it's compromised
3. **Contact the security team** immediately
4. **Document what happened** for the incident report

## 📚 Additional Resources

### Training and Certification

- **AWS Training**: [https://aws.amazon.com/training/](https://aws.amazon.com/training/)
- **Role-specific training** will be provided by your manager
- **Security awareness training** is mandatory for all users

### Documentation

- **Permission Matrix**: See `permission-matrix.md` for detailed access rights
- **Security Policies**: See `root-account-security-guide.md`
- **Architecture Overview**: See `architecture-diagram.md`

### Tools and Utilities

- **AWS CLI**: Command-line interface for AWS services
- **AWS Mobile App**: Monitor resources on mobile devices
- **Cost Calculator**: Estimate costs for new resources

## ✅ Onboarding Checklist

Complete this checklist to ensure proper setup:

### Initial Setup

- [ ] Successfully logged in with temporary password
- [ ] Changed password to meet policy requirements
- [ ] Set up MFA device (virtual or hardware)
- [ ] Verified MFA works by signing out and back in
- [ ] Tested access to role-appropriate services

### Security Configuration

- [ ] Saved password in password manager
- [ ] Saved MFA recovery codes securely
- [ ] Reviewed role permissions and limitations
- [ ] Read and understood security best practices
- [ ] Configured secure browser settings

### Knowledge and Training

- [ ] Reviewed permission matrix for your role
- [ ] Understood what you can and cannot do
- [ ] Know who to contact for help
- [ ] Completed required security training
- [ ] Bookmarked important documentation

### Final Verification

- [ ] Manager confirmed role assignment is correct
- [ ] DevOps team verified successful setup
- [ ] Security team notified of new user activation
- [ ] Added to relevant team communication channels

---

**Welcome to the team!** 🎉

You're now ready to securely access StartupCorp's AWS environment. Remember to always follow security best practices and don't hesitate to ask for help when needed.

**Document Version**: 1.0.0  
**Last Updated**: January 8, 2025  
**Next Review**: April 8, 2025  
**Owner**: DevOps Team
