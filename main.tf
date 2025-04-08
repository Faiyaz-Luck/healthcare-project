provider "aws" {
  region = "ap-south-1"
}

# --- VPC and Subnet Setup ---
resource "aws_vpc" "k8s_vpc" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "subnet_1" {
  vpc_id            = aws_vpc.k8s_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "ap-south-1a"
}

resource "aws_subnet" "subnet_2" {
  vpc_id            = aws_vpc.k8s_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-south-1b"
}

# --- Security Group ---
resource "aws_security_group" "eks_sg" {
  vpc_id = aws_vpc.k8s_vpc.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
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

# --- IAM Role for EKS Cluster ---
resource "aws_iam_role" "eks_cluster_role" {
  name = "eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# --- IAM Role for Node Group ---
resource "aws_iam_role" "eks_node_role" {
  name = "eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_autoscaler_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AutoScalingFullAccess"
}

resource "aws_iam_role_policy_attachment" "jenkins_eks_full_access" {
  role       = aws_iam_role.jenkins_eks_role.name  # Replace with your actual role name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFullAccess"
}


# --- ECR Repository ---
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
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = "1.29"

  vpc_config {
    subnet_ids         = [aws_subnet.subnet_1.id, aws_subnet.subnet_2.id]
    security_group_ids = [aws_security_group.eks_sg.id]
  }
}

# --- Node Group ---
resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.k8s_cluster.name
  node_group_name = "healthcare-node-group"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = [aws_subnet.subnet_1.id, aws_subnet.subnet_2.id]

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["t3.medium"]
  ami_type       = "AL2_x86_64"

  depends_on = [
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_policy,
    aws_eks_cluster.k8s_cluster,
    aws_iam_role_policy_attachment.node_autoscaler_policy
  ]
}

# --- Outputs ---
output "eks_cluster_name" {
  value = aws_eks_cluster.k8s_cluster.name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.medicure_repo.repository_url
}
