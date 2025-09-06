#!/usr/bin/env node
import * as cdk from "aws-cdk-lib";
import { AwsIamStackStack } from "../lib/aws-iam-stack-stack";

const app = new cdk.App();
new AwsIamStackStack(app, "AwsSecurityStack", {
  description:
    "AWS Security Implementation Stack - IAM users, groups, and policies for StartupCorp",

  /* Uncomment the next line to specialize this stack for the AWS Account
   * and Region that are implied by the current CLI configuration. */
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },

  /* For more information, see https://docs.aws.amazon.com/cdk/latest/guide/environments.html */
});
