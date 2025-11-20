# --- Health Check Helpers ---
locals {
  primary_health_check_ip = try(aws_instance.primary.public_ip, "")
  health_check_enabled    = var.enable_health_checks
}

# --- Route53 Health Check ---

resource "aws_route53_health_check" "primary" {
  count             = local.health_check_enabled ? 1 : 0
  ip_address        = local.primary_health_check_ip
  port              = 80
  type              = "HTTP"
  resource_path     = "/"
  failure_threshold = "3"
  request_interval  = "30"

  tags = {
    Name    = "${var.project_name}-Primary-HC"
    Project = var.project_name
  }
}

# --- CloudWatch Alarm ---

resource "aws_cloudwatch_metric_alarm" "primary_failure" {
  count               = local.health_check_enabled ? 1 : 0
  alarm_name          = "${var.project_name}-Primary-Failure"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "1"
  alarm_description   = "This metric monitors the health of the primary web server"
  actions_enabled     = true
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = local.health_check_enabled ? {
    HealthCheckId = aws_route53_health_check.primary[0].id
  } : {}
}

# --- SNS Topic ---

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-Alerts"
}

resource "aws_sns_topic_subscription" "lambda" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.recovery.arn
}
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
