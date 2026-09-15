module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["ap-southeast-2a", "ap-southeast-2b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

# ECR Repository
resource "aws_ecr_repository" "ecr-backend" {
  name                 = "${var.project}-backend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
  }

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_ecr_repository" "ecr-frontend" {
  name                 = "${var.project}-frontend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
  }

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "main-cluster" {
  name = "${var.project}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_ecs_cluster_capacity_providers" "main-cluster-capacity-providers" {
  cluster_name       = aws_ecs_cluster.main-cluster.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

# KMS Key
resource "aws_kms_key" "kms-key" {
  description             = "KMS key for ${var.project}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_kms_alias" "kms-alias" {
  name          = "alias/${var.project}"
  target_key_id = aws_kms_key.kms-key.key_id
}

# Secrets Manager Secret
resource "aws_secretsmanager_secret" "app-secrets" {
  name                    = "${var.project}/app-secrets"
  description             = "Application secrets for ${var.project}"
  kms_key_id              = aws_kms_key.kms-key.key_id
  recovery_window_in_days = 7

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "app-secrets-version" {
  secret_id = aws_secretsmanager_secret.app-secrets.id
  secret_string = jsonencode({
    API_KEY = "dummy-api-key-replace-in-prod"
    APP_ENV = "development"
  })
}

# Security Group for ALB
resource "aws_security_group" "alb-sg" {
  name        = "${var.project}-alb-sg"
  description = "Security group for ALB"
  vpc_id      = module.vpc.vpc_id

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

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

# ALB
resource "aws_lb" "main-alb" {
  name               = "${var.project}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb-sg.id]
  subnets            = module.vpc.public_subnets

  enable_deletion_protection = false

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

# ALB Target Group - Backend
resource "aws_lb_target_group" "backend-tg" {
  name        = "${var.project}-backend-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
  }

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

# ALB Target Group - Frontend
resource "aws_lb_target_group" "frontend-tg" {
  name        = "${var.project}-frontend-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/"
    matcher             = "200"
  }

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

# ALB Listener
resource "aws_lb_listener" "alb-listener" {
  load_balancer_arn = aws_lb.main-alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend-tg.arn
  }
}

# ALB Listener Rule - Backend
resource "aws_lb_listener_rule" "alb-listener-rule-backend" {
  listener_arn = aws_lb_listener.alb-listener.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend-tg.arn
  }

  condition {
    path_pattern {
      values = ["/api/*", "/health"]
    }
  }
}

module "backend_service" {
  source = "../modules/ecs-service"

  project          = var.project
  environment      = var.environment
  name             = "backend"
  cluster_id       = aws_ecs_cluster.main-cluster.id
  vpc_id           = module.vpc.vpc_id
  private_subnets  = module.vpc.private_subnets
  container_image  = "${aws_ecr_repository.ecr-backend.repository_url}:latest"
  container_port   = 3000
  target_group_arn = aws_lb_target_group.backend-tg.arn
  kms_key_arn      = aws_kms_key.kms-key.arn
  secret_arn       = aws_secretsmanager_secret.app-secrets.arn
}

module "frontend_service" {
  source = "../modules/ecs-service"

  project          = var.project
  environment      = var.environment
  name             = "frontend"
  cluster_id       = aws_ecs_cluster.main-cluster.id
  vpc_id           = module.vpc.vpc_id
  private_subnets  = module.vpc.private_subnets
  container_image  = "${aws_ecr_repository.ecr-frontend.repository_url}:latest"
  container_port   = 80
  target_group_arn = aws_lb_target_group.frontend-tg.arn
  kms_key_arn      = aws_kms_key.kms-key.arn
  secret_arn       = aws_secretsmanager_secret.app-secrets.arn
}

# OIDC Provider for GitHub Actions
resource "aws_iam_openid_connect_provider" "github_oidc" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# IAM Role for GitHub Actions
resource "aws_iam_role" "github_actions_role" {
  name = "${var.project}-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github_oidc.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:ber0ng/poc-aws-security:*"
        }
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

# Policy for GitHub Actions - ECR + ECS
resource "aws_iam_role_policy" "github_actions_policy" {
  name = "${var.project}-github-actions-policy"
  role = aws_iam_role.github_actions_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = "*"
      }
    ]
  })
}
