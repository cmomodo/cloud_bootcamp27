import json
import boto3
import os
import base64
import uuid

# import requests


def lambda_handler(event, context):
    """Lambda function that processes form input and sends to SQS and SES

    Parameters
    ----------
    event: dict, required
        API Gateway Lambda Proxy Input Format

    context: object, required
        Lambda Context runtime methods and attributes

    Returns
    ------
    API Gateway Lambda Proxy Output Format: dict
    """

    try:
        # Parse the body
        if 'body' in event:
            if event.get('isBase64Encoded', False):
                body = base64.b64decode(event['body']).decode('utf-8')
            else:
                body = event['body']
            # Prepare emails: customer receipt and owner notification
            # Customer receipt email
            customer_email_subject = f"Thank you for your submission, {form_data['name']}"
            customer_email_text = f"""Hello {form_data['name']},

    Thank you for contacting TravelEase. We received your submission (ID: {form_data['submission_id']}).
    Here are the details:
    - Name: {form_data['name']}
    - Email: {form_data['email']}
    - Phone: {form_data['phone']}
    - Inquiry Type: {form_data['inquiry_type']}
    - Message: {form_data['message']}
        <body>
        <h1>New Form Submission</h1>
        <p><b>Submission ID:</b> {form_data['submission_id']}</p>
            customer_email_html = f"""<html><body><h1>TravelEase Submission Received</h1><p>Submission ID: {form_data['submission_id']}</p><ul><li>Name: {form_data['name']}</li><li>Email: {form_data['email']}</li><li>Phone: {form_data['phone']}</li><li>Inquiry Type: {form_data['inquiry_type']}</li><li>Message: {form_data['message']}</li></ul></body></html>"""

            ses_customer_response = ses.send_email(
                Source=source_email,
                Destination={
                    'ToAddresses': [form_data['email']],
                },
                Message={
                    'Subject': {
                        'Data': customer_email_subject
                    },
                    'Body': {
                        'Text': {
                            'Data': customer_email_text
                        },
                        'Html': {
                            'Data': customer_email_html
                        }
                    }
                }
            )

            # Owner/Business notification email
            owner_email = os.environ.get('OWNER_EMAIL', to_email)
            owner_subject = f"New TravelEase submission from {form_data['name']}"
            owner_text = f"""A new travel form submission has been received.
    Submission ID: {form_data['submission_id']}
    Name: {form_data['name']}
    Email: {form_data['email']}
    Phone: {form_data['phone']}
    Inquiry Type: {form_data['inquiry_type']}
    Message: {form_data['message']}
    """
            owner_html = f"""<html><body><h1>New TravelEase Form Submission</h1><p>Submission ID: {form_data['submission_id']}</p><ul><li>Name: {form_data['name']}</li><li>Email: {form_data['email']}</li><li>Phone: {form_data['phone']}</li><li>Inquiry Type: {form_data['inquiry_type']}</li><li>Message: {form_data['message']}</li></ul></body></html>"""

            ses_owner_response = ses.send_email(
                Source=source_email,
                Destination={
                    'ToAddresses': [owner_email],
                },
                Message={
                    'Subject': {
                        'Data': owner_subject
                    },
                    'Body': {
                        'Text': {
                            'Data': owner_text
                        },
                        'Html': {
                            'Data': owner_html
                        }
                    }
                }
            )

            # Put item in DynamoDB
            table.put_item(Item=form_data)

            return {
                "statusCode": 200,
                "body": json.dumps({
                    "message": "Form submitted successfully",
                    "sqs_message_id": sqs_response['MessageId'],
                    "customer_ses_message_id": ses_customer_response['MessageId'],
                    "owner_ses_message_id": ses_owner_response['MessageId'],
                    "business_ses_message_id": ses_business_response['MessageId'],
                    "submission_id": form_data['submission_id']
                }),
            }
        <ul>
            <li><b>Name:</b> {form_data['name']}</li>
            <li><b>Email:</b> {form_data['email']}</li>
            <li><b>Phone:</b> {form_data['phone']}</li>
            <li><b>Inquiry Type:</b> {form_data['inquiry_type']}</li>
            <li><b>Message:</b> {form_data['message']}</li>
        </ul>
        </body>
        </html>"""

        ses_business_response = ses.send_email(
            Source=source_email,
            Destination={
                'ToAddresses': [
                    to_email,
                ]
            },
            Message={
                'Subject': {
                    'Data': business_email_subject
                },
                'Body': {
                    'Text': {
                        'Data': business_email_text
                    },
                    'Html': {
                        'Data': business_email_html
                    }
                }
            }
        )

        # Put item in DynamoDB
        table.put_item(Item=form_data)

        return {
            "statusCode": 200,
            "body": json.dumps({
                "message": "Form submitted successfully",
                "sqs_message_id": sqs_response['MessageId'],
                "customer_ses_message_id": ses_customer_response['MessageId'],
                "business_ses_message_id": ses_business_response['MessageId']
            }),
        }

    except Exception as e:
        print(e)
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)})
        }
