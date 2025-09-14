import { SESClient, SendEmailCommand } from "@aws-sdk/client-ses";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, PutCommand } from "@aws-sdk/lib-dynamodb";
import { randomUUID } from "crypto";

const sesClient = new SESClient({ region: "us-east-1" }); // replace with your region
const ddbClient = new DynamoDBClient({ region: "us-east-1" }); // replace with your region
const ddbDocClient = DynamoDBDocumentClient.from(ddbClient);

type HandlerArgs = {
  name: string;
  email: string;
  phone?: string;
  inquiryType: "VACATION_PACKAGE" | "PRICING" | "AVAILABILITY";
  message: string;
};

export const handler = async (args: HandlerArgs) => {
  console.log("payload", args);

  const { name, email, inquiryType, message, phone } = args;
  const referenceId = randomUUID();

  // Save to DynamoDB
  const tableName = process.env.TABLE_NAME;
  const putCommand = new PutCommand({
    TableName: tableName,
    Item: {
      id: referenceId,
      name,
      email,
      phone,
      inquiryType,
      message,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      __typename: "ContactFormSubmission",
    },
  });

  try {
    await ddbDocClient.send(putCommand);
  } catch (error) {
    console.error("Failed to save to DynamoDB", error);
    throw new Error("Failed to save submission.");
  }

  // Send confirmation email
  const emailCommand = new SendEmailCommand({
    Destination: {
      ToAddresses: [email],
    },
    Message: {
      Body: {
        Text: {
          Data: `Dear ${name},

Thank you for your inquiry. We have received your message and will get back to you within 24 hours.

Your reference number is: ${referenceId}

Inquiry Type: ${inquiryType}
Message: ${message}

Best regards,
The TravelEase Team`,
        },
      },
      Subject: {
        Data: "Your TravelEase Inquiry Confirmation",
      },
    },
    Source: "your-verified-email@example.com", // replace with a verified sender email
  });

  try {
    await sesClient.send(emailCommand);
    console.log("Email sent successfully");
  } catch (error) {
    console.error("Failed to send email", error);
    // We don't throw an error here because the submission was saved.
  }

  return referenceId;
};
