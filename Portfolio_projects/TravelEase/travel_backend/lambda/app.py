import base64
import json
import os
import uuid
from datetime import datetime, timezone

import boto3

sqs = boto3.client("sqs")
ses = boto3.client("ses")
sns = boto3.client("sns")
dynamodb = boto3.resource("dynamodb")

table_name = os.environ.get("TABLE_NAME")
queue_url = os.environ.get("QUEUE_URL")
source_email = os.environ.get("SOURCE_EMAIL")
owner_email = os.environ.get("OWNER_EMAIL", source_email)
business_email = os.environ.get("BUSINESS_EMAIL", owner_email)
sns_topic_arn = os.environ.get("SNS_TOPIC_ARN")
ses_configuration_set = os.environ.get("SES_CONFIGURATION_SET")

table = dynamodb.Table(table_name) if table_name else None


class BadRequestError(ValueError):
    """Raised when the incoming payload is invalid."""


def _load_body(event: dict) -> dict:
    """Extract and decode the JSON body from the API Gateway event."""

    body = event.get("body", "")
    if isinstance(body, (bytes, bytearray)):
        body = body.decode("utf-8")

    if event.get("isBase64Encoded"):
        body = base64.b64decode(body).decode("utf-8")

    if not body:
        raise BadRequestError("Request body is required.")

    try:
        payload = json.loads(body)
    except json.JSONDecodeError as exc:
        raise BadRequestError("Request body must be valid JSON.") from exc

    return payload


def _validate_payload(payload: dict) -> dict:
    """Validate required fields and construct the form data item."""

    required_fields = ["name", "email", "phone", "inquiry_type", "message"]
    missing = [field for field in required_fields if not payload.get(field)]
    if missing:
        raise BadRequestError(f"Missing required fields: {', '.join(missing)}")

    submission_id = str(uuid.uuid4())
    timestamp = datetime.now(timezone.utc).isoformat()

    form_data = {
        "submission_id": submission_id,
        "name": payload["name"],
        "email": payload["email"],
        "phone": payload["phone"],
        "inquiry_type": payload["inquiry_type"],
        "message": payload["message"],
        "created_at": timestamp,
    }

    return form_data


def _send_sqs_message(form_data: dict) -> dict | None:
    if not queue_url:
        return None

    message = json.dumps(form_data)
    return sqs.send_message(QueueUrl=queue_url, MessageBody=message)


def _store_submission(form_data: dict) -> None:
    if table is None:
        return
    table.put_item(Item=form_data)


def _build_customer_email(form_data: dict) -> tuple[str, dict]:
    subject = f"Thank you for your submission, {form_data['name']}"
    text = (
        "Hello {name},\n\n"
        "Thank you for contacting TravelEase. We received your submission (ID: {submission_id}).\n"
        "Here are the details:\n"
        "- Name: {name}\n"
        "- Email: {email}\n"
        "- Phone: {phone}\n"
        "- Inquiry Type: {inquiry_type}\n"
        "- Message: {message}\n"
    ).format(**form_data)

    html = f"""
    <html>
      <body>
        <h1>TravelEase Submission Received</h1>
        <p><strong>Submission ID:</strong> {form_data['submission_id']}</p>
        <ul>
          <li><strong>Name:</strong> {form_data['name']}</li>
          <li><strong>Email:</strong> {form_data['email']}</li>
          <li><strong>Phone:</strong> {form_data['phone']}</li>
          <li><strong>Inquiry Type:</strong> {form_data['inquiry_type']}</li>
          <li><strong>Message:</strong> {form_data['message']}</li>
        </ul>
      </body>
    </html>
    """

    return subject, {"Text": {"Data": text}, "Html": {"Data": html}}


def _build_owner_email(form_data: dict) -> tuple[str, dict]:
    subject = f"New TravelEase submission from {form_data['name']}"
    text = (
        "A new travel form submission has been received.\n\n"
        "Submission ID: {submission_id}\n"
        "Name: {name}\n"
        "Email: {email}\n"
        "Phone: {phone}\n"
        "Inquiry Type: {inquiry_type}\n"
        "Message: {message}\n"
    ).format(**form_data)

    html = f"""
    <html>
      <body>
        <h1>New TravelEase Form Submission</h1>
        <p><strong>Submission ID:</strong> {form_data['submission_id']}</p>
        <ul>
          <li><strong>Name:</strong> {form_data['name']}</li>
          <li><strong>Email:</strong> {form_data['email']}</li>
          <li><strong>Phone:</strong> {form_data['phone']}</li>
          <li><strong>Inquiry Type:</strong> {form_data['inquiry_type']}</li>
          <li><strong>Message:</strong> {form_data['message']}</li>
        </ul>
      </body>
    </html>
    """

    return subject, {"Text": {"Data": text}, "Html": {"Data": html}}


def _send_email(recipient: str, subject: str, body: dict) -> dict:
    if not source_email:
        raise RuntimeError("SOURCE_EMAIL environment variable is not set.")

    params: dict = {
        "Source": source_email,
        "Destination": {"ToAddresses": [recipient]},
        "Message": {
            "Subject": {"Data": subject},
            "Body": body,
        },
    }

    if ses_configuration_set:
        params["ConfigurationSetName"] = ses_configuration_set

    return ses.send_email(**params)


def _publish_to_topic(form_data: dict) -> dict | None:
    if not sns_topic_arn:
        return None

    message = json.dumps(form_data, default=str)
    subject = f"TravelEase submission from {form_data['name']}"

    return sns.publish(
        TopicArn=sns_topic_arn,
        Subject=subject,
        Message=message,
    )


def lambda_handler(event, _context):
    try:
        payload = _load_body(event)
        form_data = _validate_payload(payload)

        sqs_response = _send_sqs_message(form_data)
        _store_submission(form_data)

        customer_subject, customer_body = _build_customer_email(form_data)
        owner_subject, owner_body = _build_owner_email(form_data)

        customer_email_id = _send_email(form_data["email"], customer_subject, customer_body)
        owner_email_id = _send_email(owner_email, owner_subject, owner_body)

        business_email_id = None
        if business_email and business_email != owner_email:
            business_email_id = _send_email(business_email, owner_subject, owner_body)

        sns_response = _publish_to_topic(form_data)

        response_body = {
            "message": "Form submitted successfully",
            "submission_id": form_data["submission_id"],
            "customer_ses_message_id": customer_email_id.get("MessageId"),
            "owner_ses_message_id": owner_email_id.get("MessageId"),
            "business_ses_message_id": business_email_id.get("MessageId") if business_email_id else None,
            "sqs_message_id": sqs_response.get("MessageId") if sqs_response else None,
            "sns_message_id": sns_response.get("MessageId") if sns_response else None,
        }

        return {
            "statusCode": 200,
            "body": json.dumps(response_body),
            "headers": {"Content-Type": "application/json"},
        }

    except BadRequestError as exc:
        return {
            "statusCode": 400,
            "body": json.dumps({"error": str(exc)}),
            "headers": {"Content-Type": "application/json"},
        }

    except Exception as exc:
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(exc)}),
            "headers": {"Content-Type": "application/json"},
        }
