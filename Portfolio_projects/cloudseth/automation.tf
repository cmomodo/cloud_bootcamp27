# --- IAM Roles ---

resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-Lambda-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_ssm" {
  name = "${var.project_name}-Lambda-SSM-Policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:StartAutomationExecution"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "ssm_role" {
  name = "${var.project_name}-SSM-Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ssm.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "ssm_policy" {
  name = "${var.project_name}-SSM-Policy"
  role = aws_iam_role.ssm_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:StartInstances",
          "ec2:DescribeInstanceStatus",
          "globalaccelerator:UpdateEndpointGroup"
        ]
        Resource = "*"
      }
    ]
  })
}

# --- Lambda Function ---

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

resource "aws_lambda_function" "recovery" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.project_name}-Recovery"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.11"
  timeout          = 60

  environment {
    variables = {
      SSM_DOCUMENT_NAME     = aws_ssm_document.recovery.name
      SECONDARY_INSTANCE_ID = aws_instance.secondary.id
      SECONDARY_REGION      = var.secondary_region
      ENDPOINT_GROUP_ARN    = aws_globalaccelerator_endpoint_group.secondary.id
      SSM_ROLE_ARN          = aws_iam_role.ssm_role.arn
    }
  }
}

resource "aws_lambda_permission" "with_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.recovery.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alerts.arn
}

# --- SSM Document ---

resource "aws_ssm_document" "recovery" {
  name          = "${var.project_name}-Recovery-Workflow"
  document_type = "Automation"
  document_format = "YAML"
  content       = file("${path.module}/recovery_workflow.yaml")
  
  # We need to attach the role to the execution, but SSM Automation usually assumes a role 
  # passed at runtime or uses the user's permissions. 
  # However, for `aws:executeScript`, we might need a role.
  # Actually, `aws:executeScript` runs in a sandbox. 
  # Let's just ensure the Lambda passes the role if needed, or we rely on the caller.
  # Wait, `ssm.start_automation_execution` can take a `AutomationAssumeRole` parameter.
  # I should update the Lambda to pass this role ARN.
}

# Output the SSM Role ARN for use in Lambda environment if needed, 
# but better to pass it as a parameter to the automation or configure it in the Lambda.
# Let's update the Lambda environment variable to include the Role ARN and pass it.
