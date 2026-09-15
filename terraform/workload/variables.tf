variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-2"
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "poc-aws-workload"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "workload"
}
