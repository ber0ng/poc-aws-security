# IAM Role for ECS Task Execution
resource "aws_iam_role" "execution-role" {
  name = "${var.project}-${var.name}-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "execution-role-policy-attachment" {
  role       = aws_iam_role.execution-role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Allow ECS to read secrets
resource "aws_iam_role_policy" "ecs-secrets-policy" {
  name = "${var.project}-${var.name}-secrets-policy"
  role = aws_iam_role.execution-role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [var.secret_arn]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = [var.kms_key_arn]
      }
    ]
  })
}

# IAM Role for ECS Task
resource "aws_iam_role" "task-role" {
  name = "${var.project}-${var.name}-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "main-log-group" {
  name              = "/ecs/${var.project}/${var.name}"
  retention_in_days = 30

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

# Security Group for ECS Service
resource "aws_security_group" "ecs-sg" {
  name        = "${var.project}-${var.name}-ecs-sg"
  description = "Security group for ${var.name} ECS service"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = var.container_port
    to_port     = var.container_port
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
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

# ECS Task Definition
resource "aws_ecs_task_definition" "main-task" {
  family                   = "${var.project}-${var.name}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution-role.arn
  task_role_arn            = aws_iam_role.task-role.arn

  container_definitions = jsonencode([{
    name      = var.name
    image     = var.container_image
    essential = true

    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.main-log-group.name
        "awslogs-region"        = "ap-southeast-2"
        "awslogs-stream-prefix" = "ecs"
      }
    }

    secrets = [{
      name      = "APP_SECRETS"
      valueFrom = var.secret_arn
    }]
  }])

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

# ECS Service
resource "aws_ecs_service" "ecs-service" {
  name            = "${var.project}-${var.name}"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.main-task.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnets
    security_groups  = [aws_security_group.ecs-sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = var.name
    container_port   = var.container_port
  }

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

