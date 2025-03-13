# Terraform Infrastructure as Code (CEA)

This directory contains Terraform configurations for deploying AWS infrastructure in a repeatable, consistent manner.

## Configuration Files

- **main.tf** - Primary Terraform configuration that defines AWS resources including VPC, subnets, Internet Gateway, route tables, EC2 instances, and security groups.
- **state.tf** - Configuration for Terraform state management using S3 bucket for remote state storage and DynamoDB for state locking.

## Infrastructure Components

The Terraform configuration deploys:
- A VPC with CIDR block 192.168.0.0/16
- Multiple subnets across availability zones (us-east-1a and us-east-1b)
- Internet Gateway for public internet access
- Route table and associations for subnet connectivity
- EC2 instances (MyServer and AppServer)
- Security group allowing SSH access

## Remote State Management

This project uses remote state management with:
- S3 bucket: "my-27-state-bucket"
- State file key: "global/s3/terraform.tfstate"
- DynamoDB table: "terraform-lock-table" for state locking

## Usage

To deploy this infrastructure:

```bash
# Initialize Terraform
terraform init

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply

# To destroy the infrastructure
terraform destroy
```

Make sure you have AWS credentials configured properly before running these commands.