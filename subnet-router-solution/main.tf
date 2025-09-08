# ------------------
# Networking Set Up
# ------------------


## Deploy new VPC in eu-west-1

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr_block
}

## Create public and private subnets, one in each AZ

resource "aws_subnet" "public" {
  count             = 3
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index] 
  availability_zone = data.aws_availability_zones.available.names[count.index] 
}

resource "aws_subnet" "private" {
  count                   = 3
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false
}

## Create an internet gateway for use in public subnets

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

## Create route tables for both public and private subnets
# Create a route to the internet via the igw for public subnet

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id
}

## Attach the route tables to the subnets
resource "aws_route_table_association" "rta" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.rt.id
}

resource "aws_route_table_association" "private_rta" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.private[count.index].id 
  route_table_id = aws_route_table.private_rt.id
}

## Create two separate security groups, one with SSH access and one without 

resource "aws_security_group" "sg" {
  name   = "${var.server_hostname}-${var.aws_region}"
  vpc_id = aws_vpc.main.id

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"

    cidr_blocks = ["0.0.0.0/0",]
  }
}

resource "aws_security_group" "private_sg" {
  name   = "${var.aws_region}-private-security-group"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"

    cidr_blocks = ["0.0.0.0/0",]
  }
}

# -----------------------
# Subnet Router Creation
# -----------------------

# The below creates 3 subnet routers in each availability zone in the public subnets.
# They are using an ami with tailscale already installed, created via Github action in the repo
# A security group with ONLY egress permissions is attached
# A script runs on startup to configure traffic forwarding and advertise 5/6 available subnets, ensuring 1 remains private for demonstration purposes


resource "aws_instance" "subnet-router" {
  count         = length(aws_subnet.private)
  ami           = "ami-071c4abb2fd20328a"
  instance_type = var.server_instance_type
  subnet_id     = aws_subnet.private[count.index].id
  key_name      = "tailscale-network"

  ## Register the instance with our tailnet
  user_data = <<-EOF
    #!/bin/bash
    set -e
    echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
    echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
    sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
    
    sudo systemctl enable --now tailscaled
    sleep 5
    tailscale up --auth-key="${var.tailscale_auth_key}" --advertise-routes=10.0.0.0/28,10.0.0.16/28,10.0.0.32/28,10.0.0.48/28,10.0.0.64/28 --ssh
  EOF

  vpc_security_group_ids = [
    aws_security_group.sg.id,
  ]

  root_block_device {
    volume_size = var.server_storage_size

    tags = {
      Environment = "engineering"
    }
  }

  tags = {
    Name        = "tailscale-subnet-router-${data.aws_availability_zones.available.names[count.index]}" 
    Environment = "engineering"
    Service     = "pne"
  }
}

## Assign public ips to each subnet router
resource "aws_eip" "ip" {
  count    = length(aws_instance.subnet-router)
  instance = aws_instance.subnet-router[count.index].id
  domain   = "vpc"

  depends_on = [
    aws_internet_gateway.gw,
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------
# Private EC2 Creation
# ---------------------

# The below creates 3 EC2 instances built from a publicly available ubuntu AMI without tailscale installed
# They are created in each of the 3 AZs and are accessible through a combination of the key pair attached and the
# security group which allows inbound SSH connections

resource "aws_instance" "private-ec2" {
  count         = length(aws_subnet.private)
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.server_instance_type
  subnet_id     = aws_subnet.private[count.index].id 
  key_name      = "tailscale-network"

  vpc_security_group_ids = [
    aws_security_group.private_sg.id,
  ]

  root_block_device {
    volume_size = var.server_storage_size

    tags = {
      Environment = "engineering"
    }
  }

  tags = {
    Name        = "private-subnet-instance-${count.index + 1}"
    Environment = "engineering"
    Service     = "pne"
  }
}

# -----------------------------------------
# Private Tailscale Installed EC2 Creation
# -----------------------------------------

# The below creates 3 EC2 instances with Tailscale installed and then running a one liner to register each instance on the tailnet using an auth key
# The same line also enables Tailscale ssh feature on each instance and accepts the routes that are being advertised by the subnet routers created earlier

resource "aws_instance" "tailscale-installed" {
  count         = length(aws_subnet.private)
  ami           = "ami-071c4abb2fd20328a"
  instance_type = var.server_instance_type
  subnet_id     = aws_subnet.private[count.index].id 
  key_name      = "tailscale-network"

  ## Register the instance with our tailnet
  user_data = <<-EOF
    #!/bin/bash
    set -e
    tailscale up --auth-key="${var.tailscale_auth_key}" --ssh --accept-routes
  EOF

  vpc_security_group_ids = [
    aws_security_group.sg.id,
  ]

  root_block_device {
    volume_size = var.server_storage_size

    tags = {
      Environment = "engineering"
    }
  }

  tags = {
    Name        = "tailscale-installed"
    Environment = "engineering"
    Service     = "pne"
  }
}
