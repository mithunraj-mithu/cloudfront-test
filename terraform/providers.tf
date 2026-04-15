# providers.tf
#
# aws            — primary region for all resources.
# aws.us_east_1  — required for ACM certificates used by CloudFront.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.82.0"
    }
  }

  backend "s3" {
    encrypt = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Service        = "Alamy Labs"
      TeamName       = "DevOps"
      RepositoryName = "cloudfront-labs"
      CreatedBy      = "Terraform"
      Environment    = title(terraform.workspace)
      Org            = "Alamy"
    }
  }
}

# ACM certificates for CloudFront must reside in us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Service        = "Alamy Labs"
      TeamName       = "DevOps"
      RepositoryName = "cloudfront-labs"
      CreatedBy      = "Terraform"
      Environment    = title(terraform.workspace)
      Org            = "Alamy"
    }
  }
}
