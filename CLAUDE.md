# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains Terraform infrastructure-as-code for deploying a high-availability Tailscale subnet router setup on AWS. The infrastructure creates a demonstration environment showing how to connect private AWS resources to a Tailscale network using subnet routers.

## Architecture

The infrastructure deploys:
- **VPC**: Single VPC (10.0.0.0/24) in eu-west-1 with 6 subnets (3 public, 3 private) across 3 availability zones
- **Subnet Routers**: 3 EC2 instances (one per AZ) in public subnets that advertise routes to 5 of the 6 subnets
- **Private EC2 with Tailscale**: 3 EC2 instances with Tailscale installed that accept advertised routes
- **Private EC2 without Tailscale**: 3 EC2 instances accessible only via SSH through subnet routers
- **NAT Gateway**: Single NAT Gateway in first public subnet for private subnet internet access
- **Security Groups**: Two groups - one with SSH ingress for private instances, one with only egress for subnet routers

**Key Design Detail**: One private subnet (10.0.0.80/28 in eu-west-1c) is intentionally NOT advertised by the subnet routers to demonstrate network isolation.

The subnet routers are actually deployed in the **private subnets** (not public as might be expected), with Elastic IPs attached for internet connectivity. This is reflected in the code at main.tf:113 where `subnet_id = aws_subnet.private[count.index].id`.

## Terraform Commands

All Terraform operations should be run from the `subnet-router-solution/` directory:

```bash
cd subnet-router-solution/

# Initialize Terraform and download providers
terraform init

# View planned changes
terraform plan

# Apply infrastructure changes
terraform apply

# Destroy all infrastructure
terraform destroy

# Format Terraform files
terraform fmt -recursive

# Validate configuration
terraform validate
```

## Required Variables

The `tailscale_auth_key` variable must be provided at runtime (it's marked as sensitive):

```bash
terraform apply -var="tailscale_auth_key=tskey-auth-xxxxx"
```

Or create a `terraform.tfvars` file:
```hcl
tailscale_auth_key = "tskey-auth-xxxxx"
```

## State Management

Terraform state is stored remotely in S3:
- **Bucket**: `apptio-tailscale-terraform-state`
- **Key**: `tailscale-infra/terraform.tfstate`
- **Region**: eu-west-1
- **AWS Profile**: `sandbox`

Ensure the AWS profile "sandbox" is configured in `~/.aws/credentials` before running Terraform commands.

## Custom AMI Creation

A custom Ubuntu 22.04 ARM64 AMI with Tailscale pre-installed is built using Packer:

```bash
cd ami-packer/

# Initialize Packer plugins
packer init packer.pkr.hcl

# Validate template
packer validate packer.pkr.hcl

# Build AMI
packer build packer.pkr.hcl
```

The GitHub Actions workflow `.github/workflows/ami-builder.yml` automates this process on workflow dispatch. **Note**: AWS credentials for the workflow have been removed, so the workflow will fail without updating secrets.

The hardcoded AMI ID `ami-071c4abb2fd20328a` in main.tf should be updated when a new AMI is built.

## Key Pair Management

The infrastructure creates a TLS key pair named "tailscale-network" used for SSH access to all EC2 instances. The private key is stored in AWS Systems Manager Parameter Store at `/tailscale/private-key`.

To retrieve the private key:
```bash
aws ssm get-parameter --name /tailscale/private-key --with-decryption --profile sandbox --region eu-west-1 --query Parameter.Value --output text
```

## Subnet Router Configuration

Subnet routers are configured via user_data script to:
1. Enable IP forwarding (IPv4 and IPv6)
2. Start Tailscale daemon
3. Authenticate using the provided auth key
4. Advertise routes: `10.0.0.0/28,10.0.0.16/28,10.0.0.32/28,10.0.0.48/28,10.0.0.64/28`
5. Enable Tailscale SSH

The subnet at 10.0.0.80/28 is intentionally excluded from advertised routes.

## Terraform Provider Configuration

The project uses:
- **AWS Provider** (~> 6.12.0)
- **Tailscale Provider** (~> 0.21.1) - currently unused, resources in tailscale-resources.tf are commented out
- **TLS Provider** (~> 4.0) - for key pair generation
- **Null Provider** (~> 3.2)

The Tailscale provider configuration exists but is not actively used in this demonstration setup.

## File Structure

```
.
├── ami-packer/
│   └── packer.pkr.hcl          # Packer template for custom AMI
├── subnet-router-solution/
│   ├── provider.tf              # Terraform and provider configuration
│   ├── variables.tf             # All variable definitions
│   ├── data.tf                  # Data sources (AMI lookup, AZ discovery)
│   ├── main.tf                  # Core infrastructure (VPC, subnets, EC2s)
│   ├── nat-gateway.tf           # NAT Gateway and routing
│   ├── key-pair.tf              # SSH key pair generation and storage
│   └── tailscale-resources.tf   # Placeholder for Tailscale API resources (unused)
└── .github/workflows/
    └── ami-builder.yml          # GitHub Actions workflow for AMI building
```

## Important Notes

- All EC2 instances use ARM-based t4g.nano instances for cost efficiency
- The infrastructure is designed for demonstration/testing purposes, not production use
- Resources are tagged with Environment="engineering" and Service="pne" (or "PRE" for AMIs)
- The NAT Gateway incurs ongoing costs even when instances are stopped
- Tailscale SSH is enabled on all instances with Tailscale installed
