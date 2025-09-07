terraform {
  required_version = ">= 1.5.0"

  # Use S3 as the remote backend for state management with DynamoDB for state locking
  backend "s3" {
    bucket         = "apptio-tailscale-terraform-state"
    key            = "tailscale-infra/terraform.tfstate"
    region         = "eu-west-1"
    encrypt        = true

    # Add AWS profile for authentication
    profile        = "sandbox"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.12.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }

    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.21.1"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "tailscale" {
  api_key = var.tailscale_api_key
  tailnet = var.tailscale_tailnet
}
