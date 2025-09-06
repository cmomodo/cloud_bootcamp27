#!/usr/bin/env node
import * as cdk from "aws-cdk-lib";
import { TechHealthInfrastructureStack } from "../lib/tech-health-infrastructure-stack";

/**
 * TechHealth Infrastructure CDK App
 *
 * Entry point for the TechHealth infrastructure modernization project.
 * This app creates the main infrastructure stack with proper environment
 * configuration for AWS deployment.
 */
const app = new cdk.App();

// Create the main infrastructure stack
new TechHealthInfrastructureStack(app, "TechHealthInfrastructureStack", {
  // Environment configuration - uses current CLI configuration
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },

  // Stack description for AWS CloudFormation
  description:
    "TechHealth Inc. modernized infrastructure stack with HIPAA compliance",

  // Enable termination protection for production deployments
  terminationProtection: false, // Set to true for production
});
