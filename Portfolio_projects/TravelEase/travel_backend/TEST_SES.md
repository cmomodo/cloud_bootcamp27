# SES Testing Guide

This guide will help you test your AWS SES (Simple Email Service) configuration.

## Prerequisites

1. **AWS Credentials**: Ensure you have AWS credentials configured
   ```bash
   aws configure
   ```

2. **Email Verification**: Your email (`ceesay.ml@outlook.com`) must be verified in SES
   - Check AWS SES Console: https://console.aws.amazon.com/ses/
   - Look for the email identity in the "Verified identities" section

3. **SES Sandbox Mode** (Important!)
   - New AWS accounts start in SES Sandbox mode
   - In Sandbox: Both sender AND recipient emails must be verified
   - To send to any email: Request production access in SES console

## Test Scripts

Two test scripts are provided:

### Option 1: Python Script (Recommended)

**Requirements:**
```bash
pip install boto3
```

**Run the test:**
```bash
cd travel_backend
python3 test_ses.py
```

**Or make it executable:**
```bash
chmod +x test_ses.py
./test_ses.py
```

### Option 2: Node.js Script

**Requirements:**
```bash
cd travel_backend
npm install @aws-sdk/client-ses
```

**Run the test:**
```bash
node test_ses.js
```

**Or make it executable:**
```bash
chmod +x test_ses.js
./test_ses.js
```

## What the Test Does

1. ✅ Checks if your email identity is verified in SES
2. ✅ Displays your SES account status and sending statistics
3. ✅ Sends a test email from `ceesay.ml@outlook.com` to `ceesay.ml@outlook.com`
4. ✅ Shows the message ID if successful
5. ✅ Provides helpful error messages if something fails

## Expected Output (Success)

```
============================================================
SES Email Test Script
============================================================

📊 SES Account Status:
   Sending enabled: True
   Recent sends: 5
   Bounces: 0
   Complaints: 0

============================================================
Checking verification status for: ceesay.ml@outlook.com
✅ Email identity verified: ceesay.ml@outlook.com

============================================================
📤 Sending test email from ceesay.ml@outlook.com to ceesay.ml@outlook.com...
✅ Email sent successfully!
   Message ID: 01020193d1234567-89abcdef-0123-4567-89ab-cdefghijklmn-000000

📬 Check your inbox at ceesay.ml@outlook.com
============================================================

✅ SES test completed successfully!
```

## Common Issues & Solutions

### ❌ Email Not Verified

**Error:**
```
❌ Email identity 'ceesay.ml@outlook.com' is not verified!
   Current status: Pending
```

**Solution:**
1. Go to AWS SES Console: https://console.aws.amazon.com/ses/
2. Navigate to "Verified identities"
3. Click on your email address
4. Check your inbox for the verification email from AWS
5. Click the verification link in the email

### ❌ MessageRejected Error

**Error:**
```
❌ Error: MessageRejected
   Email address is not verified. The following identities failed the check...
```

**Solution:**
- If in **SES Sandbox mode**, both sender and recipient must be verified
- Verify the recipient email in SES Console
- OR request production access to send to any email

### ❌ Access Denied

**Error:**
```
❌ Error: AccessDenied
   User is not authorized to perform: ses:SendEmail
```

**Solution:**
1. Check your AWS credentials: `aws sts get-caller-identity`
2. Ensure your IAM user/role has SES permissions
3. Add this policy to your IAM user/role:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "ses:SendEmail",
           "ses:SendRawEmail",
           "ses:GetIdentityVerificationAttributes"
         ],
         "Resource": "*"
       }
     ]
   }
   ```

### ❌ Region Mismatch

**Error:**
```
❌ Email identity not found
```

**Solution:**
- Check which region your SES identity is in
- Update the `REGION` variable in the test script:
  - Python: Line 119
  - Node.js: Line 13

## Moving Out of SES Sandbox

To send emails to any address (not just verified ones):

1. Go to AWS SES Console
2. Navigate to "Account dashboard"
3. Look for "Production access" status
4. Click "Request production access"
5. Fill out the request form explaining your use case
6. Wait for AWS approval (usually 24-48 hours)

## Testing with Your Lambda Function

After SES test passes, test your complete Lambda function:

```bash
# Using curl to test the API endpoint
curl -X POST https://your-api-endpoint/submit \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test User",
    "email": "ceesay.ml@outlook.com",
    "phone": "123-456-7890",
    "inquiry_type": "pricing",
    "message": "This is a test message"
  }'
```

## Additional Resources

- [AWS SES Documentation](https://docs.aws.amazon.com/ses/)
- [Moving out of SES Sandbox](https://docs.aws.amazon.com/ses/latest/dg/request-production-access.html)
- [SES Sending Limits](https://docs.aws.amazon.com/ses/latest/dg/manage-sending-quotas.html)

## Troubleshooting Checklist

- [ ] AWS credentials configured (`aws configure`)
- [ ] Email verified in SES Console
- [ ] Correct AWS region specified in test script
- [ ] IAM permissions for SES operations
- [ ] If in Sandbox: Both sender and recipient verified
- [ ] Check spam/junk folder for test email
- [ ] SES sending limits not exceeded

## Need Help?

If you continue to have issues:
1. Check AWS CloudWatch Logs for detailed error messages
2. Review SES sending statistics in AWS Console
3. Verify your AWS account is in good standing
4. Contact AWS Support if necessary
