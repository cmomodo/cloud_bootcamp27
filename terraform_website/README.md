# Terraform S3 Static Website Hosting

This directory contains Terraform configuration for deploying an S3 bucket configured to host a static website.

## Configuration Files

- **main.tf** - Defines the AWS S3 bucket resources with proper configuration for static website hosting and public access.

## Infrastructure Components

The Terraform configuration creates:
- An S3 bucket named "www.cea27.com"
- Public access settings allowing the bucket to serve content publicly
- Bucket policy that grants read access to all objects in the bucket

## Features

- **Static Website Hosting**: The bucket is configured to serve static website content
- **Public Access**: The bucket allows public access to its contents
- **Bucket Policy**: A policy is attached to allow GetObject actions from any source

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

After deployment, you can access the website by navigating to the S3 bucket website endpoint.

## Requirements

- Terraform ~> 5.0
- AWS Provider ~> 5.0
- AWS CLI configured with appropriate permissions