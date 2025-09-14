import { defineBackend } from "@aws-amplify/backend";
import { auth } from "./auth/resource";
import { data } from "./data/resource";
import { contactFormHandler } from "./functions/contactFormHandler/resource";
import { PolicyStatement } from "aws-cdk-lib/aws-iam";

const backend = defineBackend({
  auth,
  data,
  contactFormHandler,
});

// grant the function access to the ContactFormSubmission table
const ddbPolicy = new PolicyStatement({
  actions: [
    "dynamodb:PutItem",
    "dynamodb:GetItem",
    "dynamodb:UpdateItem",
    "dynamodb:DeleteItem",
    "dynamodb:Query",
    "dynamodb:Scan",
  ],
  resources: [backend.data.resources.tables.ContactFormSubmission.tableArn],
});
backend.contactFormHandler.resources.lambda.addToRolePolicy(ddbPolicy);

// grant the function access to send emails
backend.contactFormHandler.resources.lambda.addToRolePolicy(
  new PolicyStatement({
    actions: ["ses:SendEmail"],
    resources: ["*"],
  }),
);

// Pass the table name to the function as an environment variable
backend.contactFormHandler.addEnvironment(
  "TABLE_NAME",
  backend.data.resources.tables.ContactFormSubmission.tableName,
);
