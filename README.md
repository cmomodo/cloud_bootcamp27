# Cloud Bootcamp 27 - AWS Infrastructure Project

This project demonstrates various approaches to implementing AWS infrastructure for a multi-tier application deployment. We've used both AWS CloudFormation and Terraform to provision resources across different availability zones and regions.

## Project Components

This repository is organized into three main sections:

1. [AWS CloudFormation Templates](./cea_cloudformation/README.md) - Infrastructure as Code using AWS CloudFormation
2. [Terraform CEA Infrastructure](./terraform_cea/README.md) - Core infrastructure provisioning with Terraform
3. [Terraform S3 Website](./terraform_website/README.md) - Static website hosting with S3 using Terraform

## AWS Services Used

- **EC2** - Virtual servers for compute capacity
- **VPC** - Virtual Private Cloud for network isolation
- **Internet Gateway** - For connecting VPC to the internet
- **Route Tables** - For controlling subnet traffic flow
- **Subnets** - Network segmentation across availability zones
- **Security Groups** - Virtual firewalls for resources
- **S3** - Object storage and static website hosting
- **RDS** - Relational database service
- **Load Balancers** - For distributing traffic across instances
- **Auto Scaling** - Dynamic resource allocation

## Architecture Overview

The infrastructure follows a multi-tier architecture:
- Public tier with load balancers and bastion hosts
- Application tier with web/app servers
- Database tier with isolated network access
- Static content served through S3 buckets

All components are deployed across multiple availability zones for high availability.

## Deployment Instructions

### CloudFormation Deployment

```bash
aws cloudformation create-stack --stack-name <your-stack-name> --template-body file://<template-file-path>
```

### Terraform Deployment

```bash
cd terraform_cea  # or terraform_website
terraform init
terraform plan
terraform apply
```

## Feedback

If you have any feedback, please reach out to me at ceesay.ml@outlook.com