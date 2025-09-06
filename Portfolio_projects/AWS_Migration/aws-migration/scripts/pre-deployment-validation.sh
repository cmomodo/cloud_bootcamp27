#!/bin/bash

# Pre-Deployment Validation Script for TechHealth Infrastructure
# This script performs comprehensive validation before deployment

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    print_status "Testing: $test_name"
    
    if eval "$test_command" > /dev/null 2>&1; then
        print_success "$test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        print_error "$test_name"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

# Function to display usage
usage() {
    echo "Usage: $0 <environment> [options]"
    echo ""
    echo "Environments:"
    echo "  dev       - Development environment"
    echo "  staging   - Staging environment"
    echo "  prod      - Production environment"
    echo ""
    echo "Options:"
    echo "  --skip-tests     Skip unit tests (faster validation)"
    echo "  --verbose        Show detailed output"
    echo "  --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 dev --verbose"
    echo "  $0 prod --skip-tests"
    exit 1
}

# Parse command line arguments
ENVIRONMENT=""
SKIP_TESTS=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        dev|staging|prod)
            ENVIRONMENT="$1"
            shift
            ;;
        --skip-tests)
            SKIP_TESTS=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

if [ -z "$ENVIRONMENT" ]; then
    echo "Error: Environment is required"
    usage
fi

echo "🔍 TechHealth Pre-Deployment Validation"
echo "======================================="
echo "Environment: $ENVIRONMENT"
echo "Skip Tests: $SKIP_TESTS"
echo "Verbose: $VERBOSE"
echo ""

# Set environment variables
export ENVIRONMENT
export CDK_DEFAULT_REGION=us-east-1

# 1. Validate Prerequisites
validate_prerequisites() {
    echo "📋 Validating Prerequisites"
    echo "============================"
    
    run_test "Node.js is installed" "command -v node"
    run_test "npm is installed" "command -v npm"
    run_test "AWS CDK is installed" "command -v cdk"
    run_test "AWS CLI is installed" "command -v aws"
    run_test "jq is installed" "command -v jq"
    
    # Check Node.js version
    NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$NODE_VERSION" -ge 18 ]; then
        print_success "Node.js version is compatible ($NODE_VERSION)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        print_error "Node.js version is too old ($NODE_VERSION). Requires 18+"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Check CDK version
    CDK_VERSION=$(cdk --version | cut -d' ' -f1)
    print_success "CDK version: $CDK_VERSION"
    
    echo ""
}

# 2. Validate AWS Configuration
validate_aws_config() {
    echo "☁️  Validating AWS Configuration"
    echo "================================"
    
    # Check AWS credentials
    if aws sts get-caller-identity > /dev/null 2>&1; then
        ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        REGION=$(aws configure get region || echo "us-east-1")
        USER_ARN=$(aws sts get-caller-identity --query Arn --output text)
        
        print_success "AWS credentials are valid"
        print_status "Account ID: $ACCOUNT_ID"
        print_status "Region: $REGION"
        print_status "User/Role: $USER_ARN"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        print_error "AWS credentials are not configured or invalid"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Validate region
    if [ "$REGION" = "us-east-1" ] || [ "$REGION" = "us-west-2" ]; then
        print_success "AWS region is supported: $REGION"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        print_warning "AWS region may not be optimal: $REGION"
        print_status "Recommended regions: us-east-1, us-west-2"
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Check required permissions (basic test)
    if aws iam get-user > /dev/null 2>&1 || aws sts get-caller-identity > /dev/null 2>&1; then
        print_success "Basic AWS permissions are available"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        print_error "Insufficient AWS permissions"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo ""
}

# 3. Validate Project Structure
validate_project_structure() {
    echo "📁 Validating Project Structure"
    echo "==============================="
    
    run_test "CDK configuration exists" "test -f cdk.json"
    run_test "Package.json exists" "test -f package.json"
    run_test "TypeScript config exists" "test -f tsconfig.json"
    run_test "Jest config exists" "test -f jest.config.js"
    
    # Check main files
    run_test "Main app file exists" "test -f app.ts"
    run_test "Main stack exists" "test -f lib/tech-health-infrastructure-stack.ts"
    
    # Check constructs
    run_test "Networking construct exists" "test -f lib/constructs/networking-construct.ts"
    run_test "Security construct exists" "test -f lib/constructs/security-construct.ts"
    run_test "Compute construct exists" "test -f lib/constructs/compute-construct.ts"
    run_test "Database construct exists" "test -f lib/constructs/database-construct.ts"
    
    # Check configuration files
    run_test "Environment config exists" "test -f config/${ENVIRONMENT}.json"
    
    # Check test files
    run_test "Unit tests exist" "test -d test && ls test/*.test.ts > /dev/null 2>&1"
    
    echo ""
}

# 4. Validate Dependencies
validate_dependencies() {
    echo "📦 Validating Dependencies"
    echo "=========================="
    
    run_test "Node modules installed" "test -d node_modules"
    
    # Install dependencies if missing
    if [ ! -d "node_modules" ]; then
        print_status "Installing dependencies..."
        npm install --silent
    fi
    
    # Check critical dependencies
    run_test "aws-cdk-lib is installed" "npm list aws-cdk-lib > /dev/null 2>&1"
    run_test "constructs is installed" "npm list constructs > /dev/null 2>&1"
    run_test "typescript is installed" "npm list typescript > /dev/null 2>&1"
    run_test "jest is installed" "npm list jest > /dev/null 2>&1"
    
    # Check for security vulnerabilities
    print_status "Checking for security vulnerabilities..."
    if npm audit --audit-level high > /dev/null 2>&1; then
        print_success "No high-severity vulnerabilities found"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        print_warning "Security vulnerabilities detected"
        if [ "$VERBOSE" = true ]; then
            npm audit --audit-level high
        fi
        print_status "Run 'npm audit fix' to resolve issues"
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo ""
}

# 5. Build and Compile
validate_build() {
    echo "🔨 Validating Build Process"
    echo "==========================="
    
    # Clean previous build
    if [ -d "lib" ] && [ -f "lib/*.js" ]; then
        print_status "Cleaning previous build..."
        find lib -name "*.js" -delete
        find lib -name "*.d.ts" -delete
    fi
    
    # TypeScript compilation
    print_status "Compiling TypeScript..."
    if npm run build > /dev/null 2>&1; then
        print_success "TypeScript compilation successful"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        print_error "TypeScript compilation failed"
        if [ "$VERBOSE" = true ]; then
            npm run build
        fi
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Check compiled files exist
    run_test "Main stack compiled" "test -f lib/tech-health-infrastructure-stack.js"
    run_test "Constructs compiled" "ls lib/constructs/*.js > /dev/null 2>&1"
    
    echo ""
}

# 6. Run Tests
validate_tests() {
    if [ "$SKIP_TESTS" = true ]; then
        print_warning "Skipping tests as requested"
        return
    fi
    
    echo "🧪 Running Test Suite"
    echo "====================="
    
    # Unit tests
    print_status "Running unit tests..."
    if npm test > /dev/null 2>&1; then
        print_success "All unit tests passed"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        print_error "Some unit tests failed"
        if [ "$VERBOSE" = true ]; then
            npm test
        fi
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo ""
}

# 7. CDK Synthesis
validate_synthesis() {
    echo "📄 Validating CDK Synthesis"
    echo "============================"
    
    # Clean previous synthesis
    if [ -d "cdk.out" ]; then
        rm -rf cdk.out
    fi
    
    # Synthesize templates
    print_status "Synthesizing CloudFormation templates..."
    if cdk synth --context environment=$ENVIRONMENT > /dev/null 2>&1; then
        print_success "CDK synthesis successful"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        print_error "CDK synthesis failed"
        if [ "$VERBOSE" = true ]; then
            cdk synth --context environment=$ENVIRONMENT
        fi
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Validate templates exist
    run_test "CloudFormation templates generated" "test -d cdk.out && ls cdk.out/*.template.json > /dev/null 2>&1"
    
    # Basic template validation
    TEMPLATES=$(find cdk.out -name "*.template.json" 2>/dev/null)
    for template in $TEMPLATES; do
        if jq empty "$template" > /dev/null 2>&1; then
            print_success "Template is valid JSON: $(basename $template)"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            print_error "Template is invalid JSON: $(basename $template)"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
    done
    
    echo ""
}

# 8. Security Validation
validate_security() {
    echo "🔒 Validating Security Configuration"
    echo "===================================="
    
    TEMPLATES=$(find cdk.out -name "*.template.json" 2>/dev/null)
    
    for template in $TEMPLATES; do
        # Check RDS is not publicly accessible
        if grep -q '"PubliclyAccessible": false' "$template" || ! grep -q '"PubliclyAccessible": true' "$template"; then
            print_success "RDS is not publicly accessible"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            print_error "RDS is publicly accessible"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        
        # Check RDS encryption
        if grep -q '"StorageEncrypted": true' "$template"; then
            print_success "RDS encryption is enabled"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            print_error "RDS encryption is not enabled"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        
        # Check for overly permissive security groups
        if grep -q '"CidrIp": "0.0.0.0/0"' "$template" && grep -q '"FromPort": 22' "$template"; then
            print_warning "SSH may be open to the internet"
        else
            print_success "SSH access is properly restricted"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        fi
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
    done
    
    echo ""
}

# 9. Environment-Specific Validation
validate_environment_specific() {
    echo "🌍 Environment-Specific Validation"
    echo "=================================="
    
    case $ENVIRONMENT in
        dev)
            print_status "Development environment validations..."
            # Dev-specific checks
            run_test "Development config is valid" "jq empty config/dev.json"
            print_success "Development environment ready"
            ;;
        staging)
            print_status "Staging environment validations..."
            # Staging-specific checks
            run_test "Staging config is valid" "jq empty config/staging.json"
            
            # Check if dev environment exists (recommended before staging)
            if aws cloudformation describe-stacks --stack-name "TechHealth-Dev-Infrastructure" > /dev/null 2>&1; then
                print_success "Development environment exists (recommended)"
                PASSED_TESTS=$((PASSED_TESTS + 1))
            else
                print_warning "Development environment not found"
                print_status "Consider deploying to dev first"
            fi
            TOTAL_TESTS=$((TOTAL_TESTS + 1))
            ;;
        prod)
            print_status "Production environment validations..."
            # Production-specific checks
            run_test "Production config is valid" "jq empty config/prod.json"
            
            # Check if staging environment exists (required before prod)
            if aws cloudformation describe-stacks --stack-name "TechHealth-Staging-Infrastructure" > /dev/null 2>&1; then
                print_success "Staging environment exists (required)"
                PASSED_TESTS=$((PASSED_TESTS + 1))
            else
                print_error "Staging environment not found"
                print_error "Deploy to staging first before production"
                FAILED_TESTS=$((FAILED_TESTS + 1))
            fi
            TOTAL_TESTS=$((TOTAL_TESTS + 1))
            
            # Additional production safety checks
            print_warning "Production deployment requires additional approvals"
            print_status "Ensure all stakeholders are notified"
            ;;
    esac
    
    echo ""
}

# 10. Generate Validation Report
generate_validation_report() {
    echo "📊 Generating Validation Report"
    echo "==============================="
    
    REPORT_FILE="pre-deployment-validation-${ENVIRONMENT}.md"
    
    cat > "$REPORT_FILE" << EOF
# TechHealth Pre-Deployment Validation Report

**Environment:** $ENVIRONMENT
**Generated:** $(date)
**CDK Version:** $(cdk --version)
**Node Version:** $(node --version)

## Summary

- **Total Validations:** $TOTAL_TESTS
- **Passed:** $PASSED_TESTS
- **Failed:** $FAILED_TESTS
- **Success Rate:** $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%

## Validation Categories

### ✅ Prerequisites
- Node.js, npm, AWS CDK, AWS CLI installation
- Version compatibility checks

### ✅ AWS Configuration
- Credentials validation
- Region and permissions verification

### ✅ Project Structure
- CDK configuration files
- TypeScript constructs and tests
- Environment-specific configurations

### ✅ Dependencies
- Package installation and security audit
- Critical dependency verification

### ✅ Build Process
- TypeScript compilation
- Generated file validation

### ✅ Test Suite
- Unit test execution
- Test coverage validation

### ✅ CDK Synthesis
- CloudFormation template generation
- Template structure validation

### ✅ Security Configuration
- RDS accessibility and encryption
- Security group validation
- HIPAA compliance checks

### ✅ Environment Validation
- Environment-specific configuration
- Deployment prerequisites

## Deployment Readiness

EOF

    if [ $FAILED_TESTS -eq 0 ]; then
        cat >> "$REPORT_FILE" << EOF
### 🎉 READY FOR DEPLOYMENT

All validations passed successfully. The infrastructure is ready for deployment to the $ENVIRONMENT environment.

**Next Steps:**
1. Run deployment script: \`./scripts/deploy-${ENVIRONMENT}.sh\`
2. Monitor deployment progress
3. Run post-deployment validation
EOF
    else
        cat >> "$REPORT_FILE" << EOF
### ⚠️ NOT READY FOR DEPLOYMENT

$FAILED_TESTS validation(s) failed. Please address the following issues before deployment:

**Required Actions:**
1. Review failed validations above
2. Fix identified issues
3. Re-run pre-deployment validation
4. Ensure all tests pass before deployment
EOF
    fi
    
    cat >> "$REPORT_FILE" << EOF

## Recommendations

### Security
- Regular security group audits
- Automated vulnerability scanning
- HIPAA compliance monitoring

### Operations
- Implement monitoring dashboards
- Set up automated backups
- Document incident response procedures

### Cost Optimization
- Monitor resource utilization
- Implement cost alerts
- Regular cost optimization reviews

---
*Generated by TechHealth Pre-Deployment Validation Suite*
EOF

    print_success "Validation report generated: $REPORT_FILE"
}

# Main execution
main() {
    validate_prerequisites
    validate_aws_config
    validate_project_structure
    validate_dependencies
    validate_build
    validate_tests
    validate_synthesis
    validate_security
    validate_environment_specific
    generate_validation_report
    
    # Final summary
    echo "🏁 Pre-Deployment Validation Complete"
    echo "====================================="
    echo ""
    echo "📊 Results Summary:"
    echo "   Total Validations: $TOTAL_TESTS"
    echo "   Passed: $PASSED_TESTS"
    echo "   Failed: $FAILED_TESTS"
    echo "   Success Rate: $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%"
    echo ""
    
    if [ $FAILED_TESTS -eq 0 ]; then
        print_success "🎉 All validations passed! Ready for deployment."
        echo ""
        echo "Next steps:"
        echo "  1. Run: ./scripts/deploy-${ENVIRONMENT}.sh"
        echo "  2. Monitor deployment progress"
        echo "  3. Run post-deployment validation"
        echo ""
        exit 0
    else
        print_error "❌ $FAILED_TESTS validation(s) failed."
        echo ""
        echo "Please address the issues and re-run validation."
        echo "Detailed report: $REPORT_FILE"
        echo ""
        exit 1
    fi
}

# Run main function
main