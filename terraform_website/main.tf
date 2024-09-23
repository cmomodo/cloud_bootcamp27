terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Create an S3 bucket
resource "aws_s3_bucket" "website" {
  bucket = "www.cea27.com"

  tags = {
    Name        = "My bucket"
    Environment = "Dev"
  }
}

#add cloudfront distribution

resource "aws_s3_bucket" "backup" {
  bucket = "cea27.com"

  tags = {
    Name        = "Backup bucket"
    Environment = "Dev2"
  }
}

# Create a bucket policy
resource "aws_s3_bucket_policy" "backup" {
  bucket = aws_s3_bucket.backup.id

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::cea27.com/*"
    }
  ]
}
POLICY
}

# Configuring the backup bucket for static website hosting
resource "aws_s3_bucket_website_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  index_document {
    suffix = "index.html"
  }
  error_document {
    key = "error.html"
  }

  routing_rule {
    condition {
      key_prefix_equals = "docs/"
    }
    redirect {
      replace_key_prefix_with = "documents/"
    }
  }
}


# Configure website hosting for the S3 bucket
resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  index_document {
    suffix = "index.html"
  }
  error_document {
    key = "error.html"

  }

  routing_rule {
    condition {
      key_prefix_equals = "docs/"
    }
    redirect {
      replace_key_prefix_with = "documents/"
    }
  }

}

# Set public access block configuration
resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls   = false
  block_public_policy = false
}

resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id

  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "Statement1",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::www.cea27.com/*"
        },
        {
            "Sid": "Statement2",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::449095351082:user/lamin"
            },
            "Action": "s3:PutObjectAcl",
            "Resource": "arn:aws:s3:::www.cea27.com/*"
        }
    ]
}
POLICY
}

resource "aws_route53_zone" "primary" {
  name = "cea27.com"
}


locals {
  s3_origin_id = "myS3Origin"
}

