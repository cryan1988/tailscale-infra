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
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = false
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table_association" "private_rta" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_security_group" "sg" {
  name   = "${var.server_hostname}-${var.aws_region}"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"

    cidr_blocks = [
      "0.0.0.0/0",
    ]
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

resource "aws_eip" "ip" {
  instance = aws_instance.ec2.id
  domain   = "vpc"

  depends_on = [
    aws_internet_gateway.gw,
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_instance" "ec2" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.server_instance_type
  subnet_id     = aws_subnet.public[0].id 
  key_name      = "tailscale-network"

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
    Name        = "tailscale-subnet-router"
    Environment = "engineering"
    Service     = "pne"
  }
}

resource "aws_instance" "private-ec2" {
  count		= 2
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.server_instance_type
  subnet_id     = aws_subnet.private.id
  key_name      = "tailscale-network"

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
    Name        = "private-subnet-instance-${count.index + 1}"
    Environment = "engineering"
    Service     = "pne"
  }
}

resource "aws_instance" "tailscale-installed" {
  count         = 1
  ami           = "ami-071c4abb2fd20328a" ## ami with tailscale installed 
  instance_type = var.server_instance_type
  subnet_id     = aws_subnet.private.id
  key_name      = "tailscale-network"

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
