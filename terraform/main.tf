provider "aws" {
    region = "eu-north-1"  # Stockholm region
  }
  
  ##########################
  # Variables
  ##########################
  variable "dockerhub_username" {
    description = "DockerHub username"
    type        = string
  }
  
  variable "dockerhub_password" {
    description = "DockerHub password"
    type        = string
  }
  
  ##########################
  # Secrets Manager - Store DockerHub credentials
  ##########################
  resource "aws_secretsmanager_secret" "dockerhub" {
    name = "dockerhub-credentials"
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
  }
  
  resource "aws_internet_gateway" "igw" {
    vpc_id = aws_vpc.main.id
  }
  
  resource "aws_subnet" "public" {
    vpc_id                  = aws_vpc.main.id
    cidr_block              = "10.0.1.0/24"
    availability_zone       = "eu-north-1a"
    map_public_ip_on_launch = true
  }
  
  resource "aws_route_table" "public" {
    vpc_id = aws_vpc.main.id
  
    route {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_internet_gateway.igw.id
    }
  }
  
  resource "aws_route_table_association" "public" {
    subnet_id      = aws_subnet.public.id
    route_table_id = aws_route_table.public.id
  }
  
  resource "aws_security_group" "ecs_sg" {
    name        = "ecs-sg"
    description = "Allow HTTP inbound"
    vpc_id      = aws_vpc.main.id
  
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
  
  ##########################
  # IAM Role for ECS Task Execution and additional secret access
  ##########################
  resource "aws_iam_role" "ecs_task_execution_role" {
    name = "ecsTaskExecutionRole"
    assume_role_policy = jsonencode({
      Version   = "2012-10-17",
      Statement = [{
        Action    = "sts:AssumeRole",
        Effect    = "Allow",
        Principal = { Service = "ecs-tasks.amazonaws.com" }
      }]
    })
  }
  
  resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
    role       = aws_iam_role.ecs_task_execution_role.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  }
  
  # Retrieve the current AWS account ID
  data "aws_caller_identity" "current" {}
  
  # Additional policy to allow getting secrets from Secrets Manager
  resource "aws_iam_policy" "ecs_get_secret_policy" {
    name        = "ecs-get-secret-policy"
    description = "Allow ECS tasks to retrieve DockerHub credentials from Secrets Manager"
    policy      = jsonencode({
      Version: "2012-10-17",
      Statement: [
        {
          Action: ["secretsmanager:GetSecretValue"],
          Effect: "Allow",
          Resource: "arn:aws:secretsmanager:eu-north-1:${data.aws_caller_identity.current.account_id}:secret:dockerhub-credentials-*"
        }
      ]
    })
  }
  
  resource "aws_iam_role_policy_attachment" "ecs_get_secret_attach" {
    role       = aws_iam_role.ecs_task_execution_role.name
    policy_arn = aws_iam_policy.ecs_get_secret_policy.arn
  }
  
  ##########################
  # ECS Cluster
  ##########################
  resource "aws_ecs_cluster" "cluster" {
    name = "sampleapp-cluster"
  }
  
  ##########################
  # ECS Task Definition
  ##########################
  resource "aws_ecs_task_definition" "sampleapp" {
    family                   = "sampleapp-task"
    network_mode             = "awsvpc"
    requires_compatibilities = ["FARGATE"]
    cpu                      = "256"
    memory                   = "512"
    execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
    task_role_arn            = aws_iam_role.ecs_task_execution_role.arn
  
    container_definitions = jsonencode([
      {
        name  = "sampleapp"
        image = "${var.dockerhub_username}/sampleapp:latest"
        portMappings = [
          {
            containerPort = 80,
            hostPort      = 80,
            protocol      = "tcp"
          }
        ]
        repositoryCredentials = {
          credentialsParameter = aws_secretsmanager_secret.dockerhub.arn
        }
      }
    ])
  }
  
  ##########################
  # ECS Service
  ##########################
  resource "aws_ecs_service" "sampleapp" {
    name            = "sampleapp-service"
    cluster         = aws_ecs_cluster.cluster.id
    task_definition = aws_ecs_task_definition.sampleapp.arn
    desired_count   = 1
    launch_type     = "FARGATE"
  
    network_configuration {
      subnets         = [aws_subnet.public.id]
      security_groups = [aws_security_group.ecs_sg.id]
      assign_public_ip = true
    }
  }
  