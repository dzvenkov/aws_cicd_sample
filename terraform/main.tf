provider "aws" {
  region = "eu-north-1"  # Stockholm region
}

terraform {
  backend "s3" {
    bucket  = "tfstate748914"           
    region  = "eu-north-1"              
    encrypt = false # removed encryption out of curiosity
    key = "main.tfstate"
  }
}

##########################
# Variables
##########################
variable "app_prefix" {
  description = "Application specific naming prefix"
  type        = string
}

variable "dockerhub_username" {
  description = "DockerHub username"
  type        = string
}

variable "dockerhub_password" {
  description = "DockerHub password"
  type        = string
}

variable "docker_image" {
  description = "Docker image name"
  type        = string
}

variable "build_tag1" {
  description = "Server docker image tag for slot1"
  type        = string
}

variable "build_tag2" {
  description = "Server docker image tag for slot2"
  type        = string
}

variable "slot1settings" {
  description = "settings parameter for slot1"
  type        = string
}

variable "slot2settings" {
  description = "settings parameter for slot2"
  type        = string
}

##########################
# Secrets Manager - Store DockerHub credentials
##########################
resource "aws_secretsmanager_secret" "dockerhub" {
  name = "${var.app_prefix}-dockerhub-creds"

  tags = {
    Name        = "${var.app_prefix}-dockerhub-creds"
    AppPrefix = var.app_prefix
  }
}

resource "aws_secretsmanager_secret_version" "dockerhub" {
  secret_id     = aws_secretsmanager_secret.dockerhub.id
  secret_string = jsonencode({
    username = var.dockerhub_username,
    password = var.dockerhub_password
  })
}

##########################
# VPC & Networking (Minimal setup)
##########################
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name        = "${var.app_prefix}-main-vpc"
    AppPrefix = var.app_prefix
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.app_prefix}-igw"
    AppPrefix = var.app_prefix
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-north-1a"
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.app_prefix}-public-subnet"
    AppPrefix = var.app_prefix
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name        = "${var.app_prefix}-public-rt"
    AppPrefix = var.app_prefix
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "ecs_sg" {
  name        = "${var.app_prefix}-ecs-sg"
  description = "Allow HTTP inbound"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
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
    Name        = "${var.app_prefix}-ecs-sg"
    AppPrefix = var.app_prefix
  }
}

##########################
# IAM Role for ECS Task Execution and additional secret access
##########################
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.app_prefix}-ecsTaskExecutionRole"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = {
    Name        = "${var.app_prefix}-ecsTaskExecutionRole"
    AppPrefix = var.app_prefix
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_caller_identity" "current" {}

resource "aws_iam_policy" "ecs_get_secret_policy" {
  name        = "${var.app_prefix}-ecs-get-secret-policy"
  description = "Allow ECS tasks to retrieve DockerHub credentials from Secrets Manager"
  policy      = jsonencode({
    Version: "2012-10-17",
    Statement: [
      {
        Action: ["secretsmanager:GetSecretValue"],
        Effect: "Allow",
        Resource: "arn:aws:secretsmanager:eu-north-1:${data.aws_caller_identity.current.account_id}:secret:${var.app_prefix}-dockerhub-creds*"
      }
    ]
  })

  tags = {
    Name        = "${var.app_prefix}-ecs-get-secret-policy"
    AppPrefix = var.app_prefix
  }
}

resource "aws_iam_role_policy_attachment" "ecs_get_secret_attach" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.ecs_get_secret_policy.arn
}

##########################
# ECS Cluster
##########################
resource "aws_ecs_cluster" "cluster" {
  name = "${var.app_prefix}-cluster"

  tags = {
    Name        = "${var.app_prefix}-cluster"
    AppPrefix = var.app_prefix
  }
}

##########################
# IAM Role for ECS Container Instance (EC2)
##########################
resource "aws_iam_role" "ecs_instance_role" {
  name = "${var.app_prefix}-ecs-instance-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
  tags = {
    Name        = "${var.app_prefix}-ecs-instance-role"
    AppPrefix = var.app_prefix
  }
}

resource "aws_iam_role_policy_attachment" "ecs_instance_role_policy" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "${var.app_prefix}-ecs-instance-profile"
  role = aws_iam_role.ecs_instance_role.name
}

##########################
# Data Lookup for ECS Optimized AMI (Amazon Linux 2)
##########################
data "aws_ami" "ecs_ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }
}

##########################
# EC2 Instance for ECS Container
##########################
resource "aws_instance" "ecs_instance" {
  ami                    = data.aws_ami.ecs_ami.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ecs_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ecs_instance_profile.name

  # Register this instance with your ECS cluster
  user_data = <<EOF
#!/bin/bash
echo "ECS_CLUSTER=${aws_ecs_cluster.cluster.name}" >> /etc/ecs/ecs.config
EOF

  tags = {
    Name        = "${var.app_prefix}-ecs-instance"
    AppPrefix = var.app_prefix
  }
}

##########################
# ECS Task Definition 
##########################
resource "aws_ecs_task_definition" "sampleapp" {
  family                   = "${var.app_prefix}-task"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
      name  = "slot1container"
      image = "${var.dockerhub_username}/${var.docker_image}:${var.build_tag1}"
      portMappings = [{
        containerPort = 80,
        hostPort      = 80,
        protocol      = "tcp"
      }]
      repositoryCredentials = {
        credentialsParameter = aws_secretsmanager_secret.dockerhub.arn
      }
      environment = [
        {
          name  = "BUILD_TAG"
          value = "${var.build_tag1}"
        },
        {
          name  = "SETTINGS_FILE"
          value = "${var.slot1settings}"
        }
      ]
    },
    {
      name  = "slot2container"
      image = "${var.dockerhub_username}/${var.docker_image}:${var.build_tag2}"
      portMappings = [{
        containerPort = 80,
        hostPort      = 8080,
        protocol      = "tcp"
      }]
      repositoryCredentials = {
        credentialsParameter = aws_secretsmanager_secret.dockerhub.arn
      }
      environment = [
        {
          name  = "BUILD_TAG"
          value = "${var.build_tag2}"
        },
        {
          name  = "SETTINGS_FILE"
          value = "${var.slot2settings}"
        }
      ]
    }
    ])

  tags = {
    Name        = "${var.app_prefix}-task"
    AppPrefix = var.app_prefix
  }
}

##########################
# ECS Service 
##########################
resource "aws_ecs_service" "sampleapp" {
  name            = "${var.app_prefix}-service"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.sampleapp.arn
  desired_count   = 1
  launch_type     = "EC2"

  # Note: With EC2 launch type and bridge networking, the network_configuration block is not required.
  tags = {
    Name        = "${var.app_prefix}-service"
    AppPrefix = var.app_prefix
  }
}
