# Terraform configuration for EC2 + VPC infrastructure
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  # Backend will be configured dynamically by pre-step
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = var.default_tags
  }
}

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "key_pair_name" {
  description = "AWS key pair name"
  type        = string
  default     = null
}

variable "ssh_public_key" {
  description = "SSH public key material to import as an AWS key pair"
  type        = string
  default     = null
}

variable "study_name" {
  description = "Study name for resource naming"
  type        = string
}

variable "default_tags" {
  description = "Default tags for all resources"
  type        = map(string)
  default     = {}
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.study_name}-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.study_name}-igw"
  }
}

# Public Subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.study_name}-public-subnet"
  }
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.study_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security Group
resource "aws_security_group" "web" {
  name        = "${var.study_name}-web-sg"
  description = "Security group for web server"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.study_name}-web-sg"
  }
}

# Regional AMI mapping for Ubuntu 22.04 LTS - more comprehensive
locals {
  ami_mapping = {
    "us-east-1"      = "ami-0c02fb55956c7d316"  # Ubuntu 22.04 LTS
    "us-west-2"      = "ami-017fecd1353bcc96e"  # Ubuntu 22.04 LTS  
    "us-west-1"      = "ami-0d382e80be7ffdae5"  # Ubuntu 22.04 LTS
    "eu-west-1"      = "ami-096800910c1b781ba"  # Ubuntu 22.04 LTS
    "eu-central-1"   = "ami-06dd92ecc74fdfb36"  # Ubuntu 22.04 LTS
    "ap-south-1"     = "ami-0f5ee92e2d63afc18"  # Ubuntu 22.04 LTS
    "ap-southeast-1" = "ami-0d058fe428540cd89"  # Ubuntu 22.04 LTS
    "ap-northeast-1" = "ami-09a81b370b76de6a2"  # Ubuntu 22.04 LTS
    "sa-east-1"      = "ami-0c820c196a818d66a"  # Ubuntu 22.04 LTS
  }
}

# Use regional AMI mapping directly - more reliable than data source queries
locals {
  ubuntu_ami_id = lookup(local.ami_mapping, var.aws_region, local.ami_mapping["us-east-1"])
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Managed key pair — when public key changes, instance is replaced automatically
resource "aws_key_pair" "deployer" {
  count      = var.ssh_public_key != null ? 1 : 0
  key_name   = var.key_pair_name
  public_key = var.ssh_public_key
}

locals {
  key_name = var.ssh_public_key != null ? aws_key_pair.deployer[0].key_name : var.key_pair_name
}

# EC2 Instance
resource "aws_instance" "web" {
  ami                    = local.ubuntu_ami_id
  instance_type          = var.instance_type
  key_name               = local.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]

  lifecycle {
    replace_triggered_by = [aws_key_pair.deployer]
  }

  user_data = <<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y python3 python3-pip
    pip3 install boto3
  EOF

  tags = {
    Name = "${var.study_name}-web-server"
  }
}

# Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}

output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.web.id
}

output "public_ip" {
  description = "Public IP address of the instance"
  value       = aws_instance.web.public_ip
}

output "private_ip" {
  description = "Private IP address of the instance"
  value       = aws_instance.web.private_ip
}

output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.web.id
}