provider "aws" {
  region = "ap-south-1"
}

data "aws_vpc" "existing_vpc" {
  default = true
}


resource "aws_vpc" "k8s_vpc" {
  count      = length(data.aws_vpc.existing_vpc.id) > 0 ? 0 : 1
  cidr_block = "10.0.0.0/16"
}

locals {
  vpc_id = try(data.aws_vpc.existing_vpc.id, aws_vpc.k8s_vpc[0].id)
}

# --- Check for existing subnets ---
data "aws_subnets" "existing_subnets" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
}

# --- Create subnets only if they don't exist ---
resource "aws_subnet" "subnet_1" {
  count             = length(data.aws_subnets.existing_subnets.ids) > 0 ? 0 : 1
  vpc_id           = local.vpc_id
  cidr_block       = "10.0.1.0/24"
  availability_zone = "ap-south-1a"
}

resource "aws_subnet" "subnet_2" {
  count             = length(data.aws_subnets.existing_subnets.ids) > 1 ? 0 : 1
  vpc_id           = local.vpc_id
  cidr_block       = "10.0.2.0/24"
  availability_zone = "ap-south-1b"
}

locals {
  subnet_ids = length(data.aws_subnets.existing_subnets.ids) > 0 ? data.aws_subnets.existing_subnets.ids : [aws_subnet.subnet_1[0].id, aws_subnet.subnet_2[0].id]
}

# --- Security Group for EKS ---
resource "aws_security_group" "eks_sg" {
  vpc_id = local.vpc_id

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
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
}

locals {
  security_group_id = aws_security_group.eks_sg.id
}

# --- IAM Role for EKS ---
data "aws_iam_role" "existing_eks_role" {
  name = "eks-cluster-role"
}

resource "aws_iam_role" "eks_role" {
  count = length(data.aws_iam_role.existing_eks_role.arn) > 0 ? 0 : 1
  name  = "eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

locals {
  eks_role_arn = try(data.aws_iam_role.existing_eks_role.arn, aws_iam_role.eks_role[0].arn)
}

# --- AWS ECR Repository ---
resource "aws_ecr_repository" "medicure_repo" {
  name                 = "medicure-repo"
  image_tag_mutability = "MUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# --- EKS Cluster ---
resource "aws_eks_cluster" "k8s_cluster" {
  name     = "health-cluster"
  role_arn = local.eks_role_arn
  version  = "1.29" # Update based on latest stable version

  vpc_config {
    subnet_ids         = local.subnet_ids
    security_group_ids = [local.security_group_id]
  }
}

# --- Outputs ---
output "eks_cluster_name" {
  value = aws_eks_cluster.k8s_cluster.name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.medicure_repo.repository_url
}
