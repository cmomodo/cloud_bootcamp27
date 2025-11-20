package terraform.module

# --- Helpers to walk the JSON tree and find resources ---

resources contains r if {
	some path, value
	walk(input.planned_values, [path, value])
	some r in module_resources(path, value)
}

# Variant to match root_module resources
module_resources(path, value) := value if {
	reverse_index(path, 1) == "resources"
	reverse_index(path, 2) == "root_module"
}

# Variant to match child_modules resources
module_resources(path, value) := value if {
	reverse_index(path, 1) == "resources"
	reverse_index(path, 3) == "child_modules"
}

reverse_index(path, idx) := path[count(path) - idx]

# --- Policies ---

# 1. Global Accelerator provides consistent endpoint addresses
deny contains msg if {
    count({r | some r in resources; r.type == "aws_globalaccelerator_accelerator"}) == 0
    msg := "Global Accelerator is required but missing. The solution must provide consistent endpoint addresses."
}

# 2. Route53 health checks accurately detect application failures
deny contains msg if {
    count({r | some r in resources; r.type == "aws_route53_health_check"}) == 0
    msg := "Route53 Health Check is required but missing. The solution must detect application failures."
}

# 3. CloudWatch alarms trigger appropriate notifications
deny contains msg if {
    count({r | some r in resources; r.type == "aws_cloudwatch_metric_alarm"}) == 0
    msg := "CloudWatch Alarm is required but missing. The solution must trigger notifications on failure."
}

# 4. Lambda function properly processes alert notifications
deny contains msg if {
    count({r | some r in resources; r.type == "aws_lambda_function"}) == 0
    msg := "Lambda Function is required but missing. The solution must process alert notifications."
}

# 5. SSM Automation document executes recovery workflow
deny contains msg if {
    count({r | some r in resources; r.type == "aws_ssm_document"}) == 0
    msg := "SSM Automation Document is required but missing. The solution must execute a recovery workflow."
}

# 6. Terraform successfully deploys multi-region infrastructure
# We check for at least 2 EC2 instances as a proxy for multi-region setup in this context.
deny contains msg if {
    count({r | some r in resources; r.type == "aws_instance"}) < 2
    msg := "Multi-region infrastructure requires at least two EC2 instances (Primary and Secondary)."
}
