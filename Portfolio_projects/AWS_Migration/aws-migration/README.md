# TechHealth Infrastructure Modernization

A HIPAA-compliant AWS infrastructure modernization project using AWS CDK with TypeScript. This project migrates TechHealth Inc.'s patient portal web application from manually-managed infrastructure to Infrastructure as Code (IaC).

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Deployment Guide](#deployment-guide)
- [Configuration](#configuration)
- [Testing](#testing)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)
- [Cost Management](#cost-management)
- [Security & Compliance](#security--compliance)

## Architecture Overview

This infrastructure implements a secure, multi-tier architecture with proper network segmentation:

```
┌─────────────────────────────────────────────────────────────────┐
│                        AWS Region                               │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                VPC (10.0.0.0/16)                           ││
│  │  ┌─────────────────┐    ┌─────────────────┐                ││
│  │  │  Availability   │    │  Availability   │                ││
│  │  │    Zone A       │    │    Zone B       │                ││
│  │  │                 │    │                 │                ││
│  │  │ ┌─────────────┐ │    │ ┌─────────────┐ │                ││
│  │  │ │Public Subnet│ │    │ │Public Subnet│ │                ││
│  │  │ │10.0.1.0/24  │ │    │ │10.0.2.0/24  │ │                ││
│  │  │ │             │ │    │ │             │ │                ││
│  │  │ │   EC2       │ │    │ │   EC2       │ │                ││
│  │  │ │ (t2.micro)  │ │    │ │ (t2.micro)  │ │                ││
│  │  │ └─────────────┘ │    │ └─────────────┘ │                ││
│  │  │                 │    │                 │                ││
│  │  │ ┌─────────────┐ │    │ ┌─────────────┐ │                ││
│  │  │ │Private      │ │    │ │Private      │ │                ││
│  │  │ │Subnet       │ │    │ │Subnet       │ │                ││
│  │  │ │10.0.3.0/24  │ │    │ │10.0.4.0/24  │ │                ││
│  │  │ │             │ │    │ │             │ │                ││
│  │  │ │    RDS      │ │    │ │    RDS      │ │                ││
│  │  │ │  (Multi-AZ) │ │    │ │  (Multi-AZ) │ │                ││
│  │  │ └─────────────┘ │    │ └─────────────┘ │                ││
│  │  └─────────────────┘    └─────────────────┘                ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

### Key Components

- **VPC**: 10.0.0.0/16 CIDR with DNS hostnames and support enabled
- **Public Subnets**: Host EC2 instances with internet access via Internet Gateway
- **Private Subnets**: Host RDS database with no direct internet access
- **Security Groups**: Implement least-privilege access controls
- **RDS MySQL**: Multi-AZ deployment with encryption at rest
- **Secrets Manager**: Secure database credential storage
- **IAM Roles**: Minimal required permissions for EC2 instances

## Prerequisites

### Required Software

1. **Node.js** (v18.x or later)

   ```bash
   # Check version
   node --version
   npm --version
   ```

2. **AWS CLI** (v2.x)

   ```bash
   # Install AWS CLI
   curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
   sudo installer -pkg AWSCLIV2.pkg -target /

   # Verify installation
   aws --version
   ```

3. **AWS CDK CLI**

   ```bash
   # Install CDK CLI globally
   npm install -g aws-cdk

   # Verify installation
   cdk --version
   ```

4. **TypeScript** (installed as dev dependency)
   ```bash
   # Will be installed with npm install
   ```

### AWS Account Setup

1. **AWS Account**: Active AWS account with appropriate permissions
2. **IAM User**: Create IAM user with programmatic access and these policies:
   - `PowerUserAccess` (for development)
   - `IAMFullAccess` (for role creation)
3. **AWS Credentials**: Configure using one of these methods:

   **Option A: AWS CLI Configure**

   ```bash
   aws configure
   # Enter Access Key ID, Secret Access Key, Region, Output format
   ```

   **Option B: Environment Variables**

   ```bash
   export AWS_ACCESS_KEY_ID=your-access-key
   export AWS_SECRET_ACCESS_KEY=your-secret-key
   export AWS_DEFAULT_REGION=us-east-1
   ```

   **Option C: AWS Profile**

   ```bash
   aws configure --profile techhealth
   export AWS_PROFILE=techhealth
   ```

4. **CDK Bootstrap**: Bootstrap your AWS account for CDK
   ```bash
   cdk bootstrap aws://ACCOUNT-NUMBER/REGION
   ```

### System Requirements

- **Operating System**: macOS, Linux, or Windows with WSL2
- **Memory**: Minimum 4GB RAM (8GB recommended)
- **Disk Space**: At least 2GB free space
- **Network**: Internet connection for AWS API calls and npm packages

## Quick Start

1. **Clone and Setup**

   ```bash
   git clone <repository-url>
   cd aws-migration
   npm install
   ```

2. **Build Project**

   ```bash
   npm run build
   ```

3. **Run Tests**

   ```bash
   npm test
   ```

4. **Deploy to Development**

   ```bash
   # Deploy with development configuration
   npx cdk deploy --context environment=dev
   ```

5. **Verify Deployment**
   ```bash
   # Check stack status
   aws cloudformation describe-stacks --stack-name TechHealthInfrastructureStack
   ```

## Deployment Guide

### Environment Configuration

The project supports three environments: `dev`, `staging`, and `prod`. Each has its own configuration file in the `config/` directory.

#### Development Deployment

```bash
# 1. Set environment context
export CDK_ENVIRONMENT=dev

# 2. Validate configuration
npm run build
npm test

# 3. Preview changes
npx cdk diff --context environment=dev

# 4. Deploy stack
npx cdk deploy --context environment=dev

# 5. Verify deployment
./scripts/post-deployment-verification.sh
```

#### Staging Deployment

```bash
# 1. Set environment context
export CDK_ENVIRONMENT=staging

# 2. Run pre-deployment validation
./scripts/pre-deployment-validation.sh

# 3. Deploy with approval
npx cdk deploy --context environment=staging --require-approval=any-change

# 4. Run integration tests
npm run test:integration
```

#### Production Deployment

```bash
# 1. Set environment context
export CDK_ENVIRONMENT=prod

# 2. Run comprehensive validation
./scripts/pre-deployment-validation.sh
./scripts/security-scan.sh

# 3. Deploy with manual approval
npx cdk deploy --context environment=prod --require-approval=any-change

# 4. Verify production deployment
./scripts/post-deployment-verification.sh
./scripts/validate-infrastructure.sh
```

### Deployment Scripts

The project includes automated deployment scripts in the `scripts/` directory:

- `deploy-dev.sh`: Automated development deployment
- `deploy-staging.sh`: Staging deployment with validation
- `deploy-prod.sh`: Production deployment with security checks
- `update-stack.sh`: Update existing stack
- `rollback-stack.sh`: Rollback to previous version

### Step-by-Step Deployment Process

#### 1. Pre-Deployment Validation

```bash
# Validate AWS credentials
aws sts get-caller-identity

# Validate CDK version compatibility
cdk --version

# Run security scan
./scripts/security-scan.sh

# Validate infrastructure configuration
./scripts/validate-infrastructure.sh
```

#### 2. Infrastructure Deployment

```bash
# Generate CloudFormation template
npx cdk synth --context environment=dev

# Review generated template
cat cdk.out/TechHealthInfrastructureStack.template.json

# Deploy infrastructure
npx cdk deploy --context environment=dev --outputs-file outputs.json
```

#### 3. Post-Deployment Verification

```bash
# Verify resource creation
./scripts/post-deployment-verification.sh

# Test connectivity
npm run test:connectivity

# Validate security configuration
./scripts/security-scan.sh

# Setup monitoring
./scripts/setup-monitoring.sh
```

## Configuration

### Environment-Specific Settings

Configuration files are located in `config/`:

- `dev.json`: Development environment settings
- `staging.json`: Staging environment settings
- `prod.json`: Production environment settings

#### Example Configuration (dev.json)

```json
{
  "environment": "dev",
  "region": "us-east-1",
  "availabilityZones": ["us-east-1a", "us-east-1b"],
  "vpc": {
    "cidr": "10.0.0.0/16",
    "enableDnsHostnames": true,
    "enableDnsSupport": true
  },
  "ec2": {
    "instanceType": "t2.micro",
    "keyPairName": "techhealth-dev-keypair"
  },
  "rds": {
    "instanceClass": "db.t3.micro",
    "engine": "mysql",
    "engineVersion": "8.0.35",
    "allocatedStorage": 20,
    "multiAz": false,
    "backupRetentionPeriod": 7
  }
}
```

### CDK Context Configuration

The `cdk.json` file contains CDK-specific configuration:

```json
{
  "app": "npx ts-node --prefer-ts-exts bin/aws-migration.ts",
  "watch": {
    "include": ["**"],
    "exclude": [
      "README.md",
      "cdk*.json",
      "**/*.d.ts",
      "**/*.js",
      "tsconfig.json",
      "package*.json",
      "yarn.lock",
      "node_modules",
      "test"
    ]
  },
  "context": {
    "@aws-cdk/aws-lambda:recognizeLayerVersion": true,
    "@aws-cdk/core:checkSecretUsage": true,
    "@aws-cdk/core:target-partitions": ["aws", "aws-cn"]
  }
}
```

## Testing

### Test Categories

1. **Unit Tests**: Test individual CDK constructs
2. **Integration Tests**: Test complete stack deployment
3. **Security Tests**: Validate security configurations
4. **Connectivity Tests**: Verify network connectivity

### Running Tests

```bash
# Run all tests
npm test

# Run specific test suites
npm test -- --testNamePattern="NetworkingConstruct"
npm test -- --testNamePattern="SecurityConstruct"
npm test -- --testNamePattern="DatabaseConstruct"
npm test -- --testNamePattern="ComputeConstruct"

# Run tests with coverage
npm test -- --coverage

# Run integration tests
npm run test:integration

# Run connectivity tests
npm run test:connectivity
```

### Test Structure

```
test/
├── networking-construct.test.ts    # VPC and networking tests
├── security-construct.test.ts      # Security group and IAM tests
├── database-construct.test.ts      # RDS configuration tests
├── compute-construct.test.ts       # EC2 instance tests
├── integration.test.ts             # Full stack integration tests
├── connectivity.test.ts            # Network connectivity tests
└── security-validation.test.ts     # Security compliance tests
```

## Monitoring

### CloudWatch Integration

The infrastructure automatically sets up CloudWatch monitoring for:

- **EC2 Instances**: CPU, memory, disk, and network metrics
- **RDS Database**: Connection count, CPU, memory, and storage metrics
- **VPC**: Flow logs for network traffic analysis
- **Application Logs**: Custom application metrics and logs

### Monitoring Setup

```bash
# Setup monitoring dashboards and alarms
./scripts/setup-monitoring.sh

# View CloudWatch logs
aws logs describe-log-groups --log-group-name-prefix "/aws/ec2"

# Create custom dashboard
aws cloudwatch put-dashboard --dashboard-name "TechHealth-Infrastructure" --dashboard-body file://monitoring/dashboard.json
```

### Cost Monitoring

```bash
# Monitor current costs
./scripts/cost-monitoring.sh

# Set up billing alerts
aws budgets create-budget --account-id ACCOUNT-ID --budget file://config/budget.json
```

## Troubleshooting

### Common Issues and Solutions

#### 1. CDK Bootstrap Issues

**Problem**: `CDK toolkit stack not found`

**Solution**:

```bash
# Bootstrap your account
cdk bootstrap aws://ACCOUNT-NUMBER/REGION

# Verify bootstrap
aws cloudformation describe-stacks --stack-name CDKToolkit
```

#### 2. Permission Denied Errors

**Problem**: `User is not authorized to perform: iam:CreateRole`

**Solution**:

```bash
# Check current permissions
aws sts get-caller-identity

# Attach required policies to your IAM user
aws iam attach-user-policy --user-name YOUR-USERNAME --policy-arn arn:aws:iam::aws:policy/PowerUserAccess
```

#### 3. VPC CIDR Conflicts

**Problem**: `The CIDR '10.0.0.0/16' conflicts with another subnet`

**Solution**:

```bash
# Check existing VPCs
aws ec2 describe-vpcs --query 'Vpcs[*].[VpcId,CidrBlock]'

# Update CIDR in config file
# Edit config/dev.json and change vpc.cidr to non-conflicting range
```

#### 4. RDS Connection Issues

**Problem**: EC2 cannot connect to RDS

**Solution**:

```bash
# Check security group rules
aws ec2 describe-security-groups --group-names TechHealth-RDS-SecurityGroup

# Test connectivity from EC2
ssh -i keypair.pem ec2-user@EC2-IP
mysql -h RDS-ENDPOINT -u admin -p

# Verify route tables
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=VPC-ID"
```

#### 5. Deployment Rollback

**Problem**: Deployment failed and needs rollback

**Solution**:

```bash
# Rollback using script
./scripts/rollback-stack.sh

# Manual rollback
aws cloudformation cancel-update-stack --stack-name TechHealthInfrastructureStack
aws cloudformation continue-update-rollback --stack-name TechHealthInfrastructureStack
```

### Debug Commands

```bash
# CDK debugging
export CDK_DEBUG=true
npx cdk deploy --verbose

# CloudFormation events
aws cloudformation describe-stack-events --stack-name TechHealthInfrastructureStack

# Resource status
aws cloudformation describe-stack-resources --stack-name TechHealthInfrastructureStack

# VPC debugging
aws ec2 describe-vpcs --vpc-ids vpc-xxxxxxxxx
aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-xxxxxxxxx"
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=vpc-xxxxxxxxx"
```

### Log Analysis

```bash
# CloudWatch logs
aws logs describe-log-groups
aws logs get-log-events --log-group-name "/aws/lambda/function-name"

# VPC Flow logs
aws ec2 describe-flow-logs
aws logs filter-log-events --log-group-name "VPCFlowLogs" --start-time 1609459200000
```

## Cost Management

### Cost Optimization Features

- **Free Tier Resources**: Uses t2.micro EC2 and db.t3.micro RDS instances
- **No NAT Gateway**: Private subnets don't use NAT Gateway to reduce costs
- **Automated Cleanup**: Scripts to destroy test environments
- **Resource Tagging**: Comprehensive tagging for cost allocation

### Cost Monitoring

```bash
# Check current costs
./scripts/cost-monitoring.sh

# Estimate monthly costs
aws pricing get-products --service-code AmazonEC2 --filters file://pricing-filters.json

# Set up cost alerts
aws budgets create-budget --account-id ACCOUNT-ID --budget file://config/cost-budget.json
```

### Resource Cleanup

```bash
# Clean up development environment
./scripts/cleanup-resources.sh dev

# Destroy entire stack
npx cdk destroy --context environment=dev

# Verify cleanup
aws cloudformation describe-stacks --stack-name TechHealthInfrastructureStack
```

## Security & Compliance

### HIPAA Compliance Features

- **Encryption**: All data encrypted at rest and in transit
- **Network Isolation**: Database in private subnets with no internet access
- **Access Controls**: Least-privilege security groups and IAM roles
- **Audit Logging**: CloudTrail and VPC Flow Logs enabled
- **Secure Secrets**: Database credentials stored in AWS Secrets Manager

### Security Validation

```bash
# Run security scan
./scripts/security-scan.sh

# Validate best practices
./scripts/validate-best-practices.sh

# Check compliance
aws config get-compliance-details-by-config-rule --config-rule-name encrypted-volumes
```

### Security Monitoring

```bash
# Enable CloudTrail
aws cloudtrail create-trail --name TechHealth-Audit-Trail --s3-bucket-name audit-logs-bucket

# Enable VPC Flow Logs
aws ec2 create-flow-logs --resource-type VPC --resource-ids vpc-xxxxxxxxx --traffic-type ALL
```

## Useful Commands

### CDK Commands

```bash
# Build and compile
npm run build                    # Compile TypeScript to JavaScript
npm run watch                    # Watch for changes and auto-compile

# Testing
npm test                         # Run Jest unit tests
npm run test:integration         # Run integration tests
npm run test:connectivity        # Test network connectivity

# CDK Operations
npx cdk list                     # List all stacks
npx cdk synth                    # Generate CloudFormation template
npx cdk diff                     # Compare deployed vs current state
npx cdk deploy                   # Deploy stack to AWS
npx cdk destroy                  # Remove deployed resources

# Environment-specific deployment
npx cdk deploy --context environment=dev
npx cdk deploy --context environment=staging
npx cdk deploy --context environment=prod
```

### AWS CLI Commands

```bash
# Stack management
aws cloudformation describe-stacks --stack-name TechHealthInfrastructureStack
aws cloudformation describe-stack-events --stack-name TechHealthInfrastructureStack
aws cloudformation describe-stack-resources --stack-name TechHealthInfrastructureStack

# Resource inspection
aws ec2 describe-vpcs --filters "Name=tag:Project,Values=TechHealth"
aws ec2 describe-instances --filters "Name=tag:Project,Values=TechHealth"
aws rds describe-db-instances --db-instance-identifier techhealth-database
```

## Support and Contributing

### Getting Help

1. **Documentation**: Check this README and inline code comments
2. **AWS Documentation**: [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/)
3. **Issues**: Create GitHub issues for bugs or feature requests
4. **AWS Support**: Use AWS Support for account-specific issues

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes with appropriate tests
4. Run full test suite
5. Submit pull request with detailed description

### Development Workflow

```bash
# 1. Create feature branch
git checkout -b feature/new-feature

# 2. Make changes
# Edit code, add tests, update documentation

# 3. Test changes
npm run build
npm test
./scripts/validate-infrastructure.sh

# 4. Commit and push
git add .
git commit -m "Add new feature"
git push origin feature/new-feature

# 5. Create pull request
```
