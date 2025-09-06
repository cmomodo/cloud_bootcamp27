# AWS Security Implementation Scripts

This directory contains deployment, validation, and testing scripts for the AWS security implementation.

## 📋 Script Overview

### 🚀 Deployment Scripts

#### `deploy.sh`

Comprehensive deployment script with environment-specific configurations.

**Usage:**

```bash
# Deploy to production (default)
./scripts/deploy.sh

# Deploy to staging environment
./scripts/deploy.sh -e staging

# Deploy to development with auto-approval
./scripts/deploy.sh -e development -y

# Deploy with verbose output, skip tests
./scripts/deploy.sh --verbose -s
```

**Features:**

- Environment-specific configurations (production, staging, development)
- Prerequisites validation (AWS CLI, CDK, credentials)
- Unit test execution before deployment
- CDK bootstrap management
- Post-deployment validation
- Deployment report generation

**NPM Scripts:**

```bash
npm run deploy:prod      # Deploy to production
npm run deploy:staging   # Deploy to staging
npm run deploy:dev       # Deploy to development (auto-approve)
```

### ✅ Validation Scripts

#### `validate-deployment.sh`

Validates deployed IAM policies, permissions, and stack health.

**Usage:**

```bash
# Validate production deployment
./scripts/validate-deployment.sh

# Validate staging with verbose output
./scripts/validate-deployment.sh -e staging --verbose

# Validate without generating report
./scripts/validate-deployment.sh --no-report
```

**Validation Tests:**

- IAM groups existence and configuration
- IAM users creation and group membership
- Managed policies existence and attachment
- Permission simulation tests
- Security policy validation
- CloudFormation stack health
- Resource count verification

**NPM Scripts:**

```bash
npm run validate         # Validate production
npm run validate:staging # Validate staging
npm run validate:dev     # Validate development
```

### 🧪 Permission Testing Scripts

#### `test-permissions.sh`

Interactive and automated IAM permission testing using AWS policy simulation.

**Usage:**

```bash
# Interactive mode
./scripts/test-permissions.sh -i

# Test specific user
./scripts/test-permissions.sh -u dev1

# Test all developer permissions
./scripts/test-permissions.sh -r developer

# Test all roles with verbose output
./scripts/test-permissions.sh -r all --verbose
```

**Test Categories:**

- **Developer**: EC2 management, S3 app access, CloudWatch logs
- **Operations**: Full EC2, CloudWatch, Systems Manager, RDS
- **Finance**: Cost Explorer, Budgets, read-only resources
- **Analyst**: Read-only S3 data, CloudWatch metrics, RDS describe

**NPM Scripts:**

```bash
npm run test:permissions         # Interactive mode
npm run test:permissions:dev     # Test developer role
npm run test:permissions:ops     # Test operations role
npm run test:permissions:finance # Test finance role
npm run test:permissions:analyst # Test analyst role
npm run test:permissions:all     # Test all roles
```

### 🔄 End-to-End Testing Scripts

#### `e2e-test.sh`

Comprehensive end-to-end testing of the entire security implementation.

**Usage:**

```bash
# Run full E2E test suite
./scripts/e2e-test.sh

# Run E2E tests without cleanup
./scripts/e2e-test.sh --no-cleanup

# Run E2E tests on staging environment
./scripts/e2e-test.sh -e staging --verbose
```

**Test Suite:**

- Developer role functionality (3 tests)
- Operations role functionality (3 tests)
- Finance role functionality (3 tests)
- Analyst role functionality (3 tests)
- Security policy enforcement (2 tests)
- Cross-role access restrictions (2 tests)
- Infrastructure validation (3 tests)
- Stack health verification (1 test)

**NPM Scripts:**

```bash
npm run test:e2e         # E2E tests for production
npm run test:e2e:staging # E2E tests for staging
npm run test:e2e:dev     # E2E tests for development
```

### 📚 Documentation Scripts

#### `generate-docs.js`

Automatically generates documentation from TypeScript code comments.

**Usage:**

```bash
# Generate code documentation
node scripts/generate-docs.js

# Or use npm script
npm run docs:generate
```

**Features:**

- Extracts JSDoc comments from TypeScript files
- Generates markdown documentation
- Creates comprehensive API documentation
- Provides usage statistics

## 🔧 Script Configuration

### Environment Variables

Scripts support the following environment variables:

```bash
# AWS Configuration
export AWS_PROFILE=your-profile
export AWS_REGION=us-east-1

# Script Behavior
export VERBOSE=true
export SKIP_TESTS=false
export AUTO_APPROVE=false
```

### Environment-Specific Settings

#### Production Environment

- Full security policies enabled
- All 10 users created (3 dev, 2 ops, 2 finance, 3 analyst)
- MFA required for all users
- Comprehensive validation

#### Staging Environment

- Reduced user set for testing
- Relaxed policies for development
- 5 users created (2 dev, 1 ops, 1 finance, 1 analyst)
- Full security features enabled

#### Development Environment

- Minimal setup for development work
- 4 users created (1 per role)
- Auto-approval enabled by default
- Faster deployment and testing

## 📊 Output and Reporting

### Report Files Generated

All scripts generate detailed reports:

- **Deployment Reports**: `deployment-report-YYYYMMDD-HHMMSS.txt`
- **Validation Reports**: `validation-report-YYYYMMDD-HHMMSS.txt`
- **E2E Test Reports**: `e2e-test-report-YYYYMMDD-HHMMSS.txt`

### Report Contents

Reports include:

- Execution details and timestamps
- Test results and success rates
- AWS resource information
- Security recommendations
- Next steps and action items

## 🚨 Troubleshooting

### Common Issues

#### Permission Errors

```bash
# Ensure AWS credentials are configured
aws sts get-caller-identity

# Check IAM permissions for deployment
aws iam simulate-principal-policy --policy-source-arn $(aws sts get-caller-identity --query Arn --output text) --action-names cloudformation:CreateStack --resource-arns "*"
```

#### CDK Bootstrap Issues

```bash
# Re-bootstrap CDK
cdk bootstrap --force

# Check bootstrap stack
aws cloudformation describe-stacks --stack-name CDKToolkit
```

#### Script Execution Issues

```bash
# Ensure scripts are executable
chmod +x scripts/*.sh

# Check script syntax
bash -n scripts/deploy.sh
```

### Debug Mode

Enable debug mode for detailed troubleshooting:

```bash
# Enable bash debug mode
bash -x scripts/deploy.sh

# Enable verbose output
./scripts/deploy.sh --verbose

# Enable AWS CLI debug
export AWS_CLI_DEBUG=1
```

## 🔐 Security Considerations

### Script Security

- Scripts validate AWS credentials before execution
- Sensitive information is not logged or stored
- Temporary resources are cleaned up automatically
- All actions are logged for audit purposes

### Access Control

- Scripts require appropriate AWS IAM permissions
- Production deployments should require approval
- Test scripts use least-privilege principles
- Emergency procedures are documented

### Best Practices

1. **Always test in development first**
2. **Review deployment diffs before applying**
3. **Use version control for all script changes**
4. **Monitor CloudTrail logs for script execution**
5. **Regularly update and test emergency procedures**

## 📞 Support

### Getting Help

- **Script Issues**: Check the troubleshooting section above
- **AWS Errors**: Review CloudFormation events and CloudTrail logs
- **Permission Problems**: Use the permission testing scripts
- **Emergency Support**: Follow procedures in `docs/root-account-security-guide.md`

### Useful Commands

```bash
# Quick health check
npm test && npm run validate

# Full deployment pipeline
npm run build && npm run deploy:staging && npm run test:e2e:staging

# Permission debugging
npm run test:permissions:all --verbose

# Generate fresh documentation
npm run docs:generate && npm run docs:serve
```

---

**Last Updated**: [Current Date]  
**Version**: 1.0.0  
**Owner**: DevOps Team
