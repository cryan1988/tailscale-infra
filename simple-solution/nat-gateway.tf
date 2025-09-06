# ---------------------------
# Elastic IP for NAT Gateway
# ---------------------------
resource "aws_eip" "nat_eip" {
  tags = {
    Name = "nat-eip"
  }
}

# ---------------------------
# NAT Gateway (in public subnet)
# ---------------------------
resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public.id
  depends_on    = [aws_internet_gateway.gw]

  tags = {
    Name = "nat-gateway"
  }
}

# ---------------------------
# Private Route Table with NAT Gateway
# ---------------------------
resource "aws_route" "private_nat_route" {
  route_table_id         = aws_route_table.private_rt.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gw.id

  depends_on = [aws_nat_gateway.nat_gw]
}
