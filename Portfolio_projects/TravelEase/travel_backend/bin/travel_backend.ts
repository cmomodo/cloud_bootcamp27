#!/usr/bin/env node
import * as cdk from "aws-cdk-lib";
import { TravelBackendStack } from "../lib/travel_backend-stack";
import { SesStack } from "../lib/ses-stack";

const app = new cdk.App();

// Deploy SES stack first
const sesStack = new SesStack(app, "SesStack", {
  /* Uncomment the next line to specialize this stack for the AWS Account
   * and Region that are implied by the current CLI configuration. */
  // env: { account: process.env.CDK_DEFAULT_ACCOUNT, region: process.env.CDK_DEFAULT_REGION },
});

// Deploy TravelBackend stack with dependency on SES stack
const travelBackendStack = new TravelBackendStack(app, "TravelBackendStack", {
  emailIdentity: sesStack.emailIdentity,
  emailAddress: sesStack.emailAddress,
  /* Uncomment the next line to specialize this stack for the AWS Account
   * and Region that are implied by the current CLI configuration. */
  // env: { account: process.env.CDK_DEFAULT_ACCOUNT, region: process.env.CDK_DEFAULT_REGION },

  /* Uncomment the next line if you know exactly what Account and Region you
   * want to deploy the stack to. */
  // env: { account: '123456789012', region: 'us-east-1' },

  /* For more information, see https://docs.aws.amazon.com/cdk/latest/guide/environments.html */
});

// Explicitly add dependency to ensure SES stack deploys first
travelBackendStack.addDependency(sesStack);
