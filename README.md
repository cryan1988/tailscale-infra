# Tailscale Infrastructure

The subnet-router-solution folder contains a Terraform configuration which deploys a high availability Tailscale subnet router set up.
The infrastructure deployed primarily consists of a VPC with 6 subnets, a NAT Gateway, 2 Security Groups and 9 EC2 instances.

The EC2s are deployed as follows:
3 Subnet routers in each AZ and each public subnet, 3 EC2s in the privates subnets with Tailscale installed, 3 EC2s in the private subnets without Tailscale

The subnet routers are advertising 5/6 of the subnets, leaving 1 completely isolated in the eu-west-1c private subnet, this is by design for demonstration purposes.

### Architecture Diagram

<img width="1471" height="1095" alt="image" src="https://github.com/user-attachments/assets/75f42078-4636-4039-a6e5-10cdbe5ebfd5" />




#### References
To create this infrastructure I mainly made use of the following 3 sources:

- [Tailscale on AWS installation guide](https://tailscale.com/kb/1021/install-aws)  
- [Tailscale subnet routers documentation](https://tailscale.com/kb/1019/subnets)  
- [Blog: Create your own personal VPN with Tailscale on AWS using Terraform](https://ayltai.medium.com/create-your-own-personal-vpn-with-tailscale-on-aws-using-terraform-e54ea2b90ab2)  
- [Terraform Tailscale GitHub repository](https://github.com/ayltai/terraform-tailscale/tree/master)  

# AMI Creation

A Github Action has been used to create a custom AMI with Tailscale installed, this AMI is being used by the subnet routers and 3 of the EC2s in the private subnet.
The Action calls a packer image builder file located in the *ami-packer/* folder which runs the commands necessary to install Tailscale on each machine.

NOTE: I have since removed the credentials for the iam user that was used in the build, re-running the workflow will not complete without an error
This set up was for a demonstration purpose only on how we might build an AMI.
