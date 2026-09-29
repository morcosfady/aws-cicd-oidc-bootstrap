terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      Project   = "cicd-oidc-bootstrap"
      ManagedBy = "terraform"
      Owner     = "fady-morcos"
    }
  }
}

variable "github_repo" {
  description = "The only repo allowed to deploy, in GitHub's OIDC 'sub' format with immutable IDs (owner@ownerId/repo@repoId). IDs survive renames, so a new repo with the same name cannot hijack this role."
  type        = string
  default     = "morcosfady@311470950/aws-serverless-visitor-counter@1394010293"
}

data "aws_caller_identity" "me" {}

locals {
  account_id = data.aws_caller_identity.me.account_id
}
