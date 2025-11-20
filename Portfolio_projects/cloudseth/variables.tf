variable "primary_region" {
  description = "The primary AWS region"
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "The secondary AWS region"
  type        = string
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPCs"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnets"
  type        = string
  default     = "10.0.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "project_name" {
  description = "Project name for tagging"
  type        = string
  default     = "CloudSleuth"
}

variable "sns_topic_name" {
  description = "Name of the SNS topic for notifications"
  type        = string
  default     = "CloudSleuthNotifications"
}

variable "alert_email" {
  description = "Email address to receive SNS notifications"
  type        = string
  default     = "ceesay.ml@outlook.com"
}

