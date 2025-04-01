# AWS CDK Infrastructure Project

This project uses AWS Cloud Development Kit (CDK) with TypeScript to deploy infrastructure as code. The infrastructure includes EC2 instances deployed within a VPC with proper networking configuration.

## Project Structure

- `lib/cdk_cea-stack.ts` - Main infrastructure stack definition
- `bin/` - CDK app entry point
- `test/` - Unit tests for infrastructure components

## Prerequisites

- Node.js and npm installed
- AWS CLI configured with appropriate credentials
- AWS CDK Toolkit installed (`npm install -g aws-cdk`)

## Deployment Instructions

1. Install dependencies:
   ```bash
   npm install
   ```

2. Bootstrap CDK resources (only needed once per AWS account/region):
   ```bash
   cdk bootstrap
   ```

3. Synthesize CloudFormation template:
   ```bash
   cdk synth
   ```

4. Deploy the stack:
   ```bash
   cdk deploy
   ```

5. To destroy the stack when no longer needed:
   ```bash
   cdk destroy
   ```

## Useful Commands

* `npm run build`   - Compile TypeScript to JavaScript
* `npm run watch`   - Watch for changes and compile
* `npm run test`    - Perform Jest unit tests
* `cdk deploy`      - Deploy stack to AWS
* `cdk diff`        - Compare deployed stack with current state
* `cdk synth`       - Generate CloudFormation template
* `cdk destroy`     - Remove stack from AWS

## Infrastructure Components

The CDK stack provisions:
- VPC with public and private subnets
- EC2 instances with appropriate security groups
- IAM roles and policies for secure operation
