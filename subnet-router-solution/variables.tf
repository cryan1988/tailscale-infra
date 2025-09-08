variable "aws_region" {
  description = "AWS region where resources will be built"
  type        = string
  default     = "eu-west-1"
}

variable "vpc_cidr_block" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/24"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR block"
  type = list(string)
  default = [
    "10.0.0.0/28",
    "10.0.0.32/28",
    "10.0.0.48/28"
  ]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR block"
  type = list(string)
  default = [
    "10.0.0.16/28",
    "10.0.0.64/28",
    "10.0.0.80/28"
  ]
}

variable "ami_filter" {
  description = "AMI filter used with data.tf to source AMI for EC2 machines"
  type        = string
  default     = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-arm64-server-*"
}

variable "ami_owner" {
  description = "AMI owner is Canonical"
  default     = "099720109477"
}

variable "server_instance_type" {
  description = "Server instance type used for all EC2 instance in this example set up"
  type        = string
  default     = "t4g.nano"
}

variable "server_storage_size" {
  description = "Server storage size used for each EC2 instance, just an example"
  type        = number
  default     = 8
}

variable "server_username" {
  description = "AMI user"
  default     = "ubuntu"
}

variable "server_hostname" {
  description = "Server hostname"
  type        = string
  default     = "vpn"
}

variable "tailscale_auth_key" {
  description = "Auth key for registering instances, used in start up script of EC2 instances"
  type        = string
  sensitive   = true
}

## Below are commented out as the tailscale terraform provider is unavailable to me on my laptop
# These are placeholder examples of what would need to be set up

#variable "tailscale_api_key" {
#  description = "Tailscale API access token"
#  type        = string
#  sensitive   = true
#}

#variable "tailscale_tailnet" {
#  description = "Tailscale tailnet name"
#  type        = string
#  default     = "conal.ryan1988@gmail.com"
#}

#variable "tailscale_package_url" {
#  description = "Tailscale package download URL"
#  type        = string
#  default     = "https://pkgs.tailscale.com/stable/ubuntu/jammy"
#}

