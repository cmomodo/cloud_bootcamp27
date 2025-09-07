# Cloud Bootcamp 27 - AWS Infrastructure Project

This project demonstrates various approaches to implementing AWS infrastructure for a multi-tier application deployment. We've used AWS CloudFormation, AWS CDK, and Terraform to provision resources across different availability zones and regions.

## Table of Contents

- [Project Components](#project-components)
- [AWS Services Used](#aws-services-used)
- [Architecture Overview](#architecture-overview)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Deployment Instructions](#deployment-instructions)
    - [CloudFormation Deployment](#cloudformation-deployment)
    - [CDK Deployment](#cdk-deployment)
    - [Terraform Deployment](#terraform-deployment)
- [Contributing](#contributing)
- [Feedback](#feedback)

## Project Components

This repository is organized into five main sections:

1.  [AWS CloudFormation Templates](./cea_cloudformation/README.md) - Infrastructure as Code using AWS CloudFormation
2.  [AWS CDK Infrastructure](./cdk_cea/README.md) - Infrastructure as Code using AWS CDK with TypeScript
3.  [Terraform CEA Infrastructure](./terraform_cea/README.md) - Core infrastructure provisioning with Terraform
4.  [Terraform S3 Website](./terraform_website/README.md) - Static website hosting with S3 using Terraform
5.  [AWS Portfolio Projects](./aws-iam-stack/README.md) - IAM user, group, and role management with AWS CDK

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

## Getting Started

### Prerequisites

Before you begin, ensure you have the following installed:

- [AWS CLI](https://aws.amazon.com/cli/)
- [Node.js](https://nodejs.org/en/download/) (for CDK)
- [Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
- An AWS account with the necessary permissions

### Deployment Instructions

#### CloudFormation Deployment

1.  Navigate to the CloudFormation directory:
    ```bash
    cd cea_cloudformation
    ```
2.  Deploy the stack using the AWS CLI:
    ```bash
    aws cloudformation create-stack --stack-name <your-stack-name> --template-body file://<template-file-path>
    ```

#### CDK Deployment

1.  Navigate to the CDK directory:
    ```bash
    cd cdk_cea
    ```
2.  Install the dependencies:
    ```bash
    npm install
    ```
3.  Deploy the stack:
    ```bash
    cdk deploy
    ```

#### Terraform Deployment

1.  Navigate to the Terraform directory (`terraform_cea` or `terraform_website`):
    ```bash
    cd terraform_cea
    ```
2.  Initialize Terraform:
    ```bash
    terraform init
    ```
3.  Plan the deployment:
    ```bash
    terraform plan
    ```
4.  Apply the changes:
    ```bash
    terraform apply
    ```
