## Creates a private/pubic key pair called tailscale-network
# Key is used for all EC2 instances in this vpc
# Private key can be found in the Param store in the /tailscale/private-key directory

resource "tls_private_key" "pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "akp" {
  key_name   = "tailscale-network"
  public_key = tls_private_key.pk.public_key_openssh
}

resource "aws_ssm_parameter" "ssm" {
  name  = "/tailscale/private-key"
  type  = "SecureString"
  value = tls_private_key.pk.private_key_pem
}
