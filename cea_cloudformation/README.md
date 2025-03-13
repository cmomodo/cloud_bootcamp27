# AWS CloudFormation Templates

This directory contains CloudFormation templates for deploying various AWS resources.

## Available Templates

- **vpc.yaml** - Creates a VPC with public, application, and database subnets in two availability zones, along with associated components like Internet Gateway, route tables, and security groups.
- **ec2.yaml** - Deploys EC2 instances with a load balancer in a VPC setup with proper security groups and networking.
- **s3-bucket.yaml** - Template for creating an S3 bucket.
- **s3-static.yaml** - Creates an S3 bucket configured for static website hosting.
- **rds.yaml** - Template for provisioning an RDS database instance.
- **asg.yaml** - Setup for Auto Scaling Group to manage EC2 instances.
- **iam.yaml** - IAM roles and policies definitions.

## Usage

To deploy any of these templates, use the AWS CLI:

```bash
aws cloudformation create-stack --stack-name <your-stack-name> --template-body file://<template-file-path.yaml>
```

For templates that require parameters, you can specify them using the `--parameters` option or create a parameters file.

Example:
```bash
aws cloudformation create-stack --stack-name my-vpc-stack --template-body file://vpc.yaml
```

## Template Architecture

The templates in this directory follow a multi-tier architecture approach:
- VPC with public and private subnets across multiple availability zones
- Bastion hosts in public subnets for secure SSH access
- Application instances in private subnets
- Database instances in isolated subnets
- Web servers with load balancing for high availability
- S3 buckets for static content and storage