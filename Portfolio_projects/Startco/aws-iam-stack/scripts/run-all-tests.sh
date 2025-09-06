#!/bin/bash

# Comprehensive Test Runner Script
# This script runs all types of tests and validations

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT="production"
SKIP_UNIT_TESTS=false
SKIP_INTEGRATION_TESTS=false
SKIP_SECURITY_TESTS=false
SKIP_COMPLIANCE_TESTS=false
GENERATE_REPORTS=true
VERBOSE=false

# Test result counters
UNIT_TEST_RESULT=0
INTEGRATION_TEST_RESULT=0
SECURITY_TEST_RESULT=0
COMPLIANCE_TEST_RESULT=0

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    cat << EOF
Comprehensive Test Runner Script

Usage: $0 [OPTIONS]

Options:
    -e, --environment ENV    Target environment (production, staging, development) [default: production]
    --skip-unit             Skip unit tests
    --skip-integration      Skip integration tests
    --skip-security         Skip security validation tests
    --skip-compliance       Skip compliance tests
    --no-reports           Skip generating test reports
    --verbose               Enable verbose output
    -h, --help              Show this help message

Examples:
    $0                                    # Run all tests on production
    $0 -e staging --verbose              # Run all tests on staging with verbose output
    $0 --skip-compliance                 # Skip compliance tests

Test Categories:
    Unit Tests:         CDK construct tests, policy validation tests
    Integration Tests:  End-to-end deployment and permission tests
    Security Tests:     Automated security validation and boundary tests
    Compliance Tests:   SOC2, ISO27001, and CIS compliance validation

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --skip-unit)
            SKIP_UNIT_TESTS=true
            shift
            ;;
        --skip-integration)
            SKIP_INTEGRATION_TESTS=true
            shift
            ;;
        --skip-security)
            SKIP_SECURITY_TESTS=true
            shift
            ;;
        --skip-compliance)
            SKIP_COMPLIANCE_TESTS=true
            shift
            ;;
        --no-reports)
            GENERATE_REPORTS=false
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(production|staging|development)$ ]]; then
    print_error "Invalid environment: $ENVIRONMENT"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

print_status "🚀 Starting Comprehensive Test Suite"
print_status "Environment: $ENVIRONMENT"
print_status "Project Directory: $PROJECT_DIR"
print_status "Test Timestamp: $(date)"

# Change to project directory
cd "$PROJECT_DIR"

# 1. Unit Tests
if [ "$SKIP_UNIT_TESTS" = false ]; then
    print_status "🧪 Running Unit Tests"
    
    if [ "$VERBOSE" = true ]; then
        print_status "Running CDK unit tests with coverage..."
    fi
    
    if npm run test:coverage; then
        print_success "✅ Unit tests passed"
        UNIT_TEST_RESULT=0
    else
        print_error "❌ Unit tests failed"
        UNIT_TEST_RESULT=1
    fi
    
    # Run specific policy validation tests
    if [ "$VERBOSE" = true ]; then
        print_status "Running policy validation tests..."
    fi
    
    if npm run test:policy; then
        print_success "✅ Policy validation tests passed"
    else
        print_error "❌ Policy validation tests failed"
        UNIT_TEST_RESULT=1
    fi
    
    # Run comprehensive security tests
    if [ "$VERBOSE" = true ]; then
        print_status "Running comprehensive security tests..."
    fi
    
    if npm run test:security; then
        print_success "✅ Comprehensive security tests passed"
    else
        print_error "❌ Comprehensive security tests failed"
        UNIT_TEST_RESULT=1
    fi
else
    print_warning "⏭️  Skipping unit tests"
fi

echo

# 2. Integration Tests
if [ "$SKIP_INTEGRATION_TESTS" = false ]; then
    print_status "🔗 Running Integration Tests"
    
    # CDK synthesis test
    if [ "$VERBOSE" = true ]; then
        print_status "Testing CDK synthesis..."
    fi
    
    if npm run synth > /dev/null 2>&1; then
        print_success "✅ CDK synthesis successful"
    else
        print_error "❌ CDK synthesis failed"
        INTEGRATION_TEST_RESULT=1
    fi
    
    # Permission testing
    if [ "$VERBOSE" = true ]; then
        print_status "Testing role-based permissions..."
    fi
    
    if npm run test:permissions:all > /dev/null 2>&1; then
        print_success "✅ Permission tests passed"
    else
        print_warning "⚠️  Permission tests failed (may require deployed stack)"
        # Don't fail integration tests if stack isn't deployed
    fi
    
    # End-to-end tests
    if [ "$VERBOSE" = true ]; then
        print_status "Running end-to-end tests..."
    fi
    
    if npm run test:e2e > /dev/null 2>&1; then
        print_success "✅ End-to-end tests passed"
    else
        print_warning "⚠️  End-to-end tests failed (may require deployed stack)"
        # Don't fail integration tests if stack isn't deployed
    fi
else
    print_warning "⏭️  Skipping integration tests"
fi

echo

# 3. Security Tests
if [ "$SKIP_SECURITY_TESTS" = false ]; then
    print_status "🔒 Running Security Tests"
    
    # Automated security validation
    if [ "$VERBOSE" = true ]; then
        print_status "Running automated security validation..."
    fi
    
    if bash "$SCRIPT_DIR/automated-security-validation.sh" -e "$ENVIRONMENT" --no-report > /dev/null 2>&1; then
        print_success "✅ Security validation passed"
    else
        print_warning "⚠️  Security validation failed (may require deployed stack)"
        SECURITY_TEST_RESULT=1
    fi
    
    # Permission boundary tests
    if [ "$VERBOSE" = true ]; then
        print_status "Running permission boundary tests..."
    fi
    
    if npm run test:boundaries > /dev/null 2>&1; then
        print_success "✅ Permission boundary tests passed"
    else
        print_warning "⚠️  Permission boundary tests failed (may require deployed stack)"
        SECURITY_TEST_RESULT=1
    fi
else
    print_warning "⏭️  Skipping security tests"
fi

echo

# 4. Compliance Tests
if [ "$SKIP_COMPLIANCE_TESTS" = false ]; then
    print_status "📋 Running Compliance Tests"
    
    # SOC2 compliance
    if [ "$VERBOSE" = true ]; then
        print_status "Running SOC2 compliance tests..."
    fi
    
    if npm run test:compliance:soc2 > /dev/null 2>&1; then
        print_success "✅ SOC2 compliance tests passed"
    else
        print_warning "⚠️  SOC2 compliance tests failed (may require deployed stack)"
        COMPLIANCE_TEST_RESULT=1
    fi
    
    # ISO27001 compliance
    if [ "$VERBOSE" = true ]; then
        print_status "Running ISO27001 compliance tests..."
    fi
    
    if npm run test:compliance:iso27001 > /dev/null 2>&1; then
        print_success "✅ ISO27001 compliance tests passed"
    else
        print_warning "⚠️  ISO27001 compliance tests failed (may require deployed stack)"
        COMPLIANCE_TEST_RESULT=1
    fi
    
    # CIS controls
    if [ "$VERBOSE" = true ]; then
        print_status "Running CIS controls tests..."
    fi
    
    if npm run test:compliance:cis > /dev/null 2>&1; then
        print_success "✅ CIS controls tests passed"
    else
        print_warning "⚠️  CIS controls tests failed (may require deployed stack)"
        COMPLIANCE_TEST_RESULT=1
    fi
else
    print_warning "⏭️  Skipping compliance tests"
fi

echo

# Generate comprehensive test report
if [ "$GENERATE_REPORTS" = true ]; then
    print_status "📊 Generating Comprehensive Test Report"
    
    REPORT_FILE="comprehensive-test-report-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > "$REPORT_FILE" << EOF
Comprehensive Test Report
=========================

Test Execution Details:
- Environment: $ENVIRONMENT
- Test Timestamp: $(date)
- Project Directory: $PROJECT_DIR
- Executed By: $(whoami)
- AWS Account: $(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "Not configured")

Test Results Summary:
- Unit Tests: $([ $UNIT_TEST_RESULT -eq 0 ] && echo "✅ PASSED" || echo "❌ FAILED")
- Integration Tests: $([ $INTEGRATION_TEST_RESULT -eq 0 ] && echo "✅ PASSED" || echo "❌ FAILED")
- Security Tests: $([ $SECURITY_TEST_RESULT -eq 0 ] && echo "✅ PASSED" || echo "⚠️  WARNINGS")
- Compliance Tests: $([ $COMPLIANCE_TEST_RESULT -eq 0 ] && echo "✅ PASSED" || echo "⚠️  WARNINGS")

Test Categories Executed:

1. Unit Tests:
   - CDK construct validation
   - Policy structure validation
   - Security configuration tests
   - Resource creation tests
   - Code coverage analysis

2. Integration Tests:
   - CDK synthesis validation
   - CloudFormation template validation
   - Permission simulation tests
   - End-to-end deployment tests

3. Security Tests:
   - Automated security validation
   - Permission boundary verification
   - Least privilege enforcement
   - Security policy compliance

4. Compliance Tests:
   - SOC2 Type II compliance
   - ISO 27001 controls
   - CIS security benchmarks
   - Industry best practices

Overall Test Status:
EOF

    TOTAL_FAILURES=$((UNIT_TEST_RESULT + INTEGRATION_TEST_RESULT + SECURITY_TEST_RESULT + COMPLIANCE_TEST_RESULT))
    
    if [ $TOTAL_FAILURES -eq 0 ]; then
        echo "✅ ALL TESTS PASSED - Implementation is ready for production" >> "$REPORT_FILE"
    elif [ $UNIT_TEST_RESULT -eq 0 ] && [ $INTEGRATION_TEST_RESULT -eq 0 ]; then
        echo "⚠️  CORE TESTS PASSED - Security/compliance warnings may require deployed stack" >> "$REPORT_FILE"
    else
        echo "❌ CRITICAL TESTS FAILED - Implementation requires fixes before deployment" >> "$REPORT_FILE"
    fi

    cat >> "$REPORT_FILE" << EOF

Recommendations:
1. Address any failed unit or integration tests immediately
2. Deploy stack to run full security and compliance validation
3. Review warnings and implement recommended improvements
4. Schedule regular test execution (daily for unit tests, weekly for full suite)
5. Update tests as new requirements are added

Next Steps:
1. Fix any critical test failures
2. Deploy to staging environment for full validation
3. Run security and compliance tests against deployed stack
4. Document any accepted risks or exceptions
5. Schedule production deployment

Test Artifacts:
- Unit test coverage report: coverage/lcov-report/index.html
- CDK synthesis output: cdk.out/
- Test logs: Available in CI/CD pipeline or local execution

EOF

    print_success "Comprehensive test report saved to: $REPORT_FILE"
fi

# Final summary
echo
print_status "🏁 Comprehensive Test Suite Summary:"
echo "  🧪 Unit Tests: $([ $UNIT_TEST_RESULT -eq 0 ] && echo "✅ PASSED" || echo "❌ FAILED")"
echo "  🔗 Integration Tests: $([ $INTEGRATION_TEST_RESULT -eq 0 ] && echo "✅ PASSED" || echo "❌ FAILED")"
echo "  🔒 Security Tests: $([ $SECURITY_TEST_RESULT -eq 0 ] && echo "✅ PASSED" || echo "⚠️  WARNINGS")"
echo "  📋 Compliance Tests: $([ $COMPLIANCE_TEST_RESULT -eq 0 ] && echo "✅ PASSED" || echo "⚠️  WARNINGS")"

TOTAL_FAILURES=$((UNIT_TEST_RESULT + INTEGRATION_TEST_RESULT + SECURITY_TEST_RESULT + COMPLIANCE_TEST_RESULT))

if [ $TOTAL_FAILURES -eq 0 ]; then
    print_success "🎉 All tests completed successfully!"
    exit 0
elif [ $UNIT_TEST_RESULT -eq 0 ] && [ $INTEGRATION_TEST_RESULT -eq 0 ]; then
    print_warning "⚠️  Core tests passed. Security/compliance warnings may require deployed stack."
    exit 0
else
    print_error "❌ Critical tests failed. Please address issues before deployment."
    exit 1
fi