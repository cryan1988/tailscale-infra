## Tailscale Infrastructure

The subnet-router-solution folder contains a Terraform configuration which deploys a high availability Tailscale subnet router set up.
The infrastructure deployed primarily consists of a VPC with 6 subnets, a NAT Gateway, 2 Security Groups and 9 EC2 instances.

The EC2s are deployed as follows:
3 Subnet routers in each AZ and each public subnet, 3 EC2s in the privates subnets with Tailscale installed, 3 EC2s in the private subnets without Tailscale

The subnet routers are advertising 5/6 of the subnets, leaving 1 completely isolated in the eu-west-1c private subnet, this is by design for demonstration purposes.

### Architecture Diagram

The diagram below shows the basic architecture that is created in the AWS account, as well as an example route of how we can reach an EC2 instance NOT installed with Tailscale
and located in a private subnet from outside the VPC.

<img width="1849" height="1366" alt="image" src="https://github.com/user-attachments/assets/c4116470-ed39-4a26-99e6-4433aa466b42" />





#### References
To create this infrastructure I mainly made use of the following 4 sources:

- [Tailscale on AWS installation guide](https://tailscale.com/kb/1021/install-aws)  
- [Tailscale subnet routers documentation](https://tailscale.com/kb/1019/subnets) 
- [Tailscale NAT Traversal](https://tailscale.com/blog/how-nat-traversal-works) 
- [Blog: Create your own personal VPN with Tailscale on AWS using Terraform](https://ayltai.medium.com/create-your-own-personal-vpn-with-tailscale-on-aws-using-terraform-e54ea2b90ab2)  
- [Terraform Tailscale GitHub repository](https://github.com/ayltai/terraform-tailscale/tree/master)  

## AMI Creation

A Github Action has been used to create a custom AMI with Tailscale installed, this AMI is being used by the subnet routers and 3 of the EC2s in the private subnet.
The Action calls a packer image builder file located in the *ami-packer/* folder which runs the commands necessary to install Tailscale on each machine.

NOTE: I have since removed the credentials for the iam user that was used in the build, re-running the workflow will not complete without an error.

This set up was for a demonstration purpose only on how we might build an AMI.

## End Result
Below is an image of the infrastructure that is created, as seen in the admin console of the tailnet:

<img width="1229" height="921" alt="image" src="https://github.com/user-attachments/assets/b31f4bb1-de0a-4c3a-9e45-a1c993b4c611" />






















Further reading on Tailscale:

https://tailscale.com/blog/how-nat-traversal-works
