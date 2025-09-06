#!/usr/bin/env node
import * as cdk from "aws-cdk-lib";
import { TechHealthInfrastructureStack } from "./lib/tech-health-infrastructure-stack";
import {
  getDeploymentConfig,
  getAwsEnvironment,
} from "./lib/config/config-loader";

/**
 * TechHealth Infrastructure CDK App
 *
 * Alternative entry point for the TechHealth infrastructure modernization project.
 * This app supports environment-specific deployments with proper configuration management.
 */
const app = new cdk.App();

// Get environment from context or environment variables
const environment =
  app.node.tryGetContext("environment") || process.env.ENVIRONMENT || "dev";

// Load environment-specific configuration
const deploymentConfig = getDeploymentConfig(environment);
const awsEnv = getAwsEnvironment(deploymentConfig.configFile);

// Create the main infrastructure stack with environment-specific configuration
new TechHealthInfrastructureStack(app, deploymentConfig.stackName, {
  // Environment configuration
  env: awsEnv,
  config: deploymentConfig.config,
  environment: environment,

  // Stack description for AWS CloudFormation
  description: `TechHealth Inc. ${environment} infrastructure stack with HIPAA compliance`,

  // Enable termination protection for production deployments
  terminationProtection: deploymentConfig.config.environment === "prod",

  // Stack tags
  tags: {
    Environment: deploymentConfig.config.environment,
    Project: deploymentConfig.config.tags.project,
    Owner: deploymentConfig.config.tags.owner,
    CostCenter: deploymentConfig.config.tags.costCenter,
    Application: deploymentConfig.config.tags.application,
    Compliance: deploymentConfig.config.tags.compliance,
  },
});
