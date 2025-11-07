#!/usr/bin/env python3
"""
SES Test Script
This script tests if your SES email identity is properly configured and can send emails.
"""

import boto3
import sys
from botocore.exceptions import ClientError

def test_ses_email(source_email, to_email, region='us-east-1'):
    """
    Test SES by sending a test email.

    Args:
        source_email (str): The verified sender email address
        to_email (str): The recipient email address (must also be verified in SES sandbox)
        region (str): AWS region where SES is configured
    """

    # Create SES client
    ses_client = boto3.client('ses', region_name=region)

    # Email content
    subject = "SES Test Email"
    body_text = """
    This is a test email from your SES configuration.

    If you received this email, your SES setup is working correctly!

    Timestamp: {timestamp}
    """.format(timestamp=boto3.session.Session().get_credentials().method)

    body_html = """<html>
    <head></head>
    <body>
        <h1>SES Test Email</h1>
        <p>This is a test email from your SES configuration.</p>
        <p><strong>If you received this email, your SES setup is working correctly!</strong></p>
        <hr>
        <p style="color: #666; font-size: 12px;">
            This is an automated test email.
        </p>
    </body>
    </html>
    """

    try:
        # Check if email identity is verified
        print(f"Checking verification status for: {source_email}")
        response = ses_client.get_identity_verification_attributes(
            Identities=[source_email]
        )

        verification_status = response['VerificationAttributes'].get(source_email, {}).get('VerificationStatus')

        if verification_status != 'Success':
            print(f"❌ Email identity '{source_email}' is not verified!")
            print(f"   Current status: {verification_status}")
            print(f"\n📧 Please verify your email by checking your inbox for a verification email from AWS.")
            return False

        print(f"✅ Email identity verified: {source_email}")

        # Send the test email
        print(f"\n📤 Sending test email from {source_email} to {to_email}...")
        response = ses_client.send_email(
            Source=source_email,
            Destination={
                'ToAddresses': [to_email]
            },
            Message={
                'Subject': {
                    'Data': subject,
                    'Charset': 'UTF-8'
                },
                'Body': {
                    'Text': {
                        'Data': body_text,
                        'Charset': 'UTF-8'
                    },
                    'Html': {
                        'Data': body_html,
                        'Charset': 'UTF-8'
                    }
                }
            }
        )

        print(f"✅ Email sent successfully!")
        print(f"   Message ID: {response['MessageId']}")
        print(f"\n📬 Check your inbox at {to_email}")
        return True

    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_message = e.response['Error']['Message']

        print(f"❌ Error: {error_code}")
        print(f"   {error_message}")

        if error_code == 'MessageRejected':
            print("\n💡 Tips:")
            print("   - Make sure the email address is verified in SES")
            print("   - If in SES Sandbox, both sender and recipient must be verified")
            print("   - Check your AWS account's SES sending limits")

        return False

    except Exception as e:
        print(f"❌ Unexpected error: {str(e)}")
        return False


def check_ses_sandbox_status(region='us-east-1'):
    """Check if the account is in SES sandbox mode."""
    ses_client = boto3.client('ses', region_name=region)

    try:
        response = ses_client.get_account_sending_enabled()
        print(f"\n📊 SES Account Status:")
        print(f"   Sending enabled: {response.get('Enabled', 'Unknown')}")

        # Try to get sending statistics
        stats = ses_client.get_send_statistics()
        if stats['SendDataPoints']:
            latest = stats['SendDataPoints'][-1]
            print(f"   Recent sends: {int(latest.get('DeliveryAttempts', 0))}")
            print(f"   Bounces: {int(latest.get('Bounces', 0))}")
            print(f"   Complaints: {int(latest.get('Complaints', 0))}")

    except Exception as e:
        print(f"⚠️  Could not retrieve account status: {str(e)}")


if __name__ == "__main__":
    # Configuration
    SOURCE_EMAIL = "modoulaminceesay7@gmail.com"
    TO_EMAIL = "modoulaminceesay7@gmail.com"  # In sandbox mode, this must be verified
    REGION = "us-east-1"  # Change if your SES is in a different region

    print("=" * 60)
    print("SES Email Test Script")
    print("=" * 60)

    # Check sandbox status
    check_ses_sandbox_status(REGION)

    # Test sending email
    print("\n" + "=" * 60)
    success = test_ses_email(SOURCE_EMAIL, TO_EMAIL, REGION)
    print("=" * 60)

    if success:
        print("\n✅ SES test completed successfully!")
        sys.exit(0)
    else:
        print("\n❌ SES test failed. Please check the errors above.")
        sys.exit(1)
