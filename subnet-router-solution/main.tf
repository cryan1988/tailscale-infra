resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr_block
}

resource "aws_subnet" "public" {
  count             = 3
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index] 
  availability_zone = data.aws_availability_zones.available.names[count.index] 
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "rta" {
  count          = length(aws_subnet.public)
  route_table_id = aws_route_table.rt.id
  subnet_id      = aws_subnet.public[count.index].id
}

# ---------------------------
# Private Subnet
# ---------------------------
resource "aws_subnet" "private" {
  count                   = 3
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidrs[count.index] 
  availability_zone       = data.aws_availability_zones.available.names[count.index] 
  map_public_ip_on_launch = false
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table_association" "private_rta" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.private[count.index].id 
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_security_group" "sg" {
  name   = "${var.server_hostname}-${var.aws_region}"
  vpc_id = aws_vpc.main.id

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"

    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }
}

resource "aws_security_group" "private_sg" {
  name   = "${var.aws_region}-private-security-group"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["2.100.5.99/32"]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"

    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }
}

resource "aws_instance" "subnet-router" {
  count         = length(aws_subnet.private)
  ami           = "ami-071c4abb2fd20328a" ## ami with tailscale installed
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

resource "aws_instance" "tailscale-installed" {
  count         = length(aws_subnet.private)
  ami           = "ami-071c4abb2fd20328a" ## ami with tailscale installed 
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
