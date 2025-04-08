provider "aws" {
  region = "ap-south-1"
}

# --- VPC and Subnet Setup ---
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

data "aws_subnets" "existing_subnets" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
}

resource "aws_subnet" "subnet_1" {
  count             = length(data.aws_subnets.existing_subnets.ids) > 0 ? 0 : 1
  vpc_id            = local.vpc_id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "ap-south-1a"
}

resource "aws_subnet" "subnet_2" {
  count             = length(data.aws_subnets.existing_subnets.ids) > 1 ? 0 : 1
  vpc_id            = local.vpc_id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-south-1b"
}

locals {
  subnet_ids = length(data.aws_subnets.existing_subnets.ids) > 0 ? data.aws_subnets.existing_subnets.ids : [aws_subnet.subnet_1[0].id, aws_subnet.subnet_2[0].id]
}

# --- Security Group ---
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

# --- IAM Role for EKS Cluster ---
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

# --- IAM Role for EKS Node Group ---
data "aws_iam_role" "existing_node_role" {
  name = "eks-node-role"
}

resource "aws_iam_role" "eks_node_role" {
  count = length(data.aws_iam_role.existing_node_role.arn) > 0 ? 0 : 1
  name  = "eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

locals {
  eks_node_role_arn = try(data.aws_iam_role.existing_node_role.arn, aws_iam_role.eks_node_role[0].arn)
}

resource "aws_iam_role_policy_attachment" "eks_node_worker_policy" {
  role       = local.eks_node_role_arn
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_node_ecr_policy" {
  role       = local.eks_node_role_arn
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "eks_node_cni_policy" {
  role       = local.eks_node_role_arn
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# --- ECR Repository ---
data "aws_ecr_repository" "existing_repo" {
  name  = "medicure-repo"
  count = 1
}


resource "aws_ecr_repository" "medicure_repo" {
  count                = length(data.aws_ecr_repository.existing_repo[*].repository_url) > 0 ? 0 : 1
  name                 = "medicure-repo"
  image_tag_mutability = "MUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }
}

locals {
  ecr_repo_url = try(data.aws_ecr_repository.existing_repo[0].repository_url, aws_ecr_repository.medicure_repo[0].repository_url)
}

# --- EKS Cluster ---
resource "aws_eks_cluster" "k8s_cluster" {
  name     = "health-cluster"
  role_arn = local.eks_role_arn
  version  = "1.29"

  vpc_config {
    subnet_ids         = local.subnet_ids
    security_group_ids = [local.security_group_id]
  }
}

# --- EKS Node Group ---
resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.k8s_cluster.name
  node_group_name = "healthcare-node-group"
  node_role_arn   = local.eks_node_role_arn
  subnet_ids      = local.subnet_ids

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["t3.medium"]
  ami_type       = "AL2_x86_64"

  tags = {
    Name = "healthcare-node-group"
  }

  depends_on = [
    aws_eks_cluster.k8s_cluster,
    aws_iam_role_policy_attachment.eks_node_worker_policy,
    aws_iam_role_policy_attachment.eks_node_ecr_policy,
    aws_iam_role_policy_attachment.eks_node_cni_policy
  ]
}

# --- Outputs ---
output "eks_cluster_name" {
  value = aws_eks_cluster.k8s_cluster.name
}

output "ecr_repository_url" {
  value = local.ecr_repo_url
}
