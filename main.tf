provider "aws" {
  region = "ap-south-1"
}

# --- VPC & Networking ---
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

# --- Security Groups ---
resource "aws_security_group" "eks_sg" {
  vpc_id = aws_vpc.k8s_vpc.id

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- IAM Role for EKS ---
resource "aws_iam_role" "eks_role" {
  name = "eks-cluster-role-new"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })

  lifecycle {
    ignore_changes = [name]
  }
}


resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# --- Create EKS Cluster ---
resource "aws_eks_cluster" "k8s_cluster" {
  name     = "healthcareproject-cluster"
  role_arn = aws_iam_role.eks_role.arn

  vpc_config {
    subnet_ids = [aws_subnet.subnet_1.id, aws_subnet.subnet_2.id]
    security_group_ids = [aws_security_group.eks_sg.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
  ]
}


# --- IAM Role for Worker Nodes ---
resource "aws_iam_role" "eks_worker_role" {
  name = "eks-worker-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "worker_node_policy" {
  role       = aws_iam_role.eks_worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# Additional IAM policies for worker nodes
resource "aws_iam_role_policy_attachment" "worker_node_ec2_policy" {
  role       = aws_iam_role.eks_worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "worker_node_cni_policy" {
  role       = aws_iam_role.eks_worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# --- EKS Worker Nodes ---
resource "aws_eks_node_group" "worker_nodes" {
  cluster_name    = aws_eks_cluster.k8s_cluster.name
  node_group_name = "worker-nodes"
  node_role_arn   = aws_iam_role.eks_worker_role.arn
  subnet_ids      = [aws_subnet.subnet_1.id, aws_subnet.subnet_2.id]

  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 3
  }

  instance_types = ["t3.medium"]
}

# --- Jenkins EC2 Instance ---
resource "aws_instance" "jenkins_server" {
  ami           = "ami-006d9dc984b8eb4b9"  # Ubuntu AMI (update if needed)
  instance_type = "t3.medium"
  subnet_id     = aws_subnet.subnet_1.id
  security_groups = [aws_security_group.eks_sg.id]
  key_name      = "healthcare-key"

  user_data = <<-EOF
    #!/bin/bash
    sudo apt update -y
    sudo apt install -y openjdk-11-jdk
    sudo wget -q -O - https://pkg.jenkins.io/debian-stable/jenkins.io.key | sudo apt-key add -
    sudo sh -c 'echo deb http://pkg.jenkins.io/debian-stable binary/ > /etc/apt/sources.list.d/jenkins.list'
    sudo apt update -y
    sudo apt install -y jenkins
    sudo systemctl start jenkins
    sudo systemctl enable jenkins
  EOF

  tags = {
    Name = "Jenkins-Server"
  }
}

# --- Amazon ECR Repository ---
resource "aws_ecr_repository" "medicure_repo" {
  name = "medicure-app"
  force_delete = true
}


# --- Monitoring Setup (Prometheus & Grafana via Helm) ---
resource "null_resource" "install_monitoring" {
  provisioner "local-exec" {
    command = <<EOT
      aws eks update-kubeconfig --region ap-south-1 --name healthcareproject-cluster
      helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
      helm install prometheus prometheus-community/kube-prometheus-stack
      helm repo add grafana https://grafana.github.io/helm-charts
      helm install grafana grafana/grafana --set adminPassword=admin
    EOT
  }
  depends_on = [aws_eks_cluster.k8s_cluster]
}

# --- Outputs ---
output "kubeconfig" {
  value = aws_eks_cluster.k8s_cluster.endpoint
}

output "jenkins_url" {
  value = "http://${aws_instance.jenkins_server.public_ip}:8080"
}

output "ecr_repository_url" {
  value = aws_ecr_repository.medicure_repo.repository_url
}
