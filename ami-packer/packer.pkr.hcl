packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = ">= 1.2.0"
    }
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "ami_filter" {
  description = "Base AMI filter"
  type        = string
  default     = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-arm64-server-*"
}

variable "ami_owner" {
  description = "Canonical account ID for Ubuntu AMIs"
  type        = string
  default     = "099720109477"
}

source "amazon-ebs" "ubuntu" {
  region        = var.region
  instance_type = "t4g.micro"  # ARM instance

  source_ami_filter {
    filters = {
      name                = var.ami_filter
      virtualization-type = "hvm"
    }
    owners      = [var.ami_owner]
    most_recent = true
  }

  ssh_username = "ubuntu"

  ami_name        = "tailscale-ubuntu-jammy-{{timestamp}}"
  ami_description = "Ubuntu 22.04 AMI with Tailscale installed"
}

build {
  name    = "tailscale-ubuntu"
  sources = ["source.amazon-ebs.ubuntu"]

  provisioner "shell" {
    inline = [
      # Update and install prerequisites
      "sudo apt-get update",
      "sudo apt-get install -y curl gnupg2 software-properties-common",

      # Add Tailscale repo
      "curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null",
      "curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list",

      # Install Tailscale
      "sudo apt-get update",
      "sudo apt-get install -y tailscale"
    ]
  }
}

