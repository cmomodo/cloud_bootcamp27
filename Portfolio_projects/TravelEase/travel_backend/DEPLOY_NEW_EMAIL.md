# Deploy SES with New Email Address

I've updated all the files to use the new email address: `modoulaminceesay7@gmail.com`

## Files Updated:

✅ **lib/ses-stack.ts** - Changed email to `modoulaminceesay7@gmail.com`
✅ **test_ses.py** - Updated test script with new email
✅ **test_ses.js** - Updated test script with new email

## Deployment Steps:

### Step 1: Deploy the SES Stack

```bash
cd travel_backend
cdk deploy SesStack
```

This will:
- Create a new SES email identity for `modoulaminceesay7@gmail.com`
- Update the CloudFormation stack

### Step 2: Verify Your Email

**IMPORTANT:** After deployment, AWS will send a verification email to `modoulaminceesay7@gmail.com`

1. Check your Gmail inbox
2. Look for an email from `no-reply-aws@amazon.com` with subject: "Amazon SES Address Verification Request"
3. Click the verification link in the email
4. You should see a success message in your browser

⚠️ **Without verification, you CANNOT send emails from this address!**

### Step 3: Deploy the TravelBackend Stack

Once the email is verified, deploy the main stack:

```bash
cdk deploy TravelBackendStack
```

Or deploy both stacks together:

```bash
cdk deploy --all
```

### Step 4: Test SES

After verification, run the test script:

```bash
# Node.js version (recommended)
node test_ses.js

# Or Python version
python3 test_ses.py
```

You should receive a test email in your Gmail inbox.

## Expected Output After Deployment:

```
Outputs:
SesStack.SesEmailAddress = modoulaminceesay7@gmail.com
SesStack.SesEmailIdentityArn = arn:aws:ses:us-east-1:449095351082:identity/modoulaminceesay7@gmail.com
SesStack.SesEmailIdentityName = modoulaminceesay7@gmail.com

TravelBackendStack.ApiEndpoint = https://...
TravelBackendStack.QueueUrl = https://sqs...
TravelBackendStack.TableName = travelease-form
```

## Troubleshooting:

### If deployment is stuck:

Check CloudFormation in AWS Console:
```
https://console.aws.amazon.com/cloudformation/
```

Look for the `SesStack` and check its status.

### If there's an existing CDK process:

Kill it and retry:
```bash
pkill -f "cdk deploy"
cdk deploy SesStack
```

### If email verification doesn't arrive:

1. Check Gmail spam/junk folder
2. Check "Promotions" or "Updates" tabs in Gmail
3. Request a new verification email from AWS SES Console:
   - Go to: https://console.aws.amazon.com/ses/
   - Click on "Verified identities"
   - Find your email
   - Click "Resend verification email"

## Gmail vs Outlook Difference:

✅ **Gmail is much better for SES emails** because:
- Rarely marks AWS emails as spam
- Better deliverability
- Clearer inbox organization
- Easy to search for verification emails

You should receive emails successfully in Gmail!

## Next Steps After Verification:

1. Test the contact form by sending a POST request to your API endpoint
2. Check if emails arrive in Gmail
3. Consider requesting SES production access to send to any email address (not just verified ones)

## Quick Test Command:

After everything is deployed and verified:

```bash
curl -X POST https://YOUR-API-ENDPOINT/submit \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test User",
    "email": "modoulaminceesay7@gmail.com",
    "phone": "123-456-7890",
    "inquiry_type": "pricing",
    "message": "Testing the contact form"
  }'
```

Replace `YOUR-API-ENDPOINT` with the actual endpoint from the TravelBackendStack outputs.
