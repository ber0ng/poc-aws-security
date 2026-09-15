variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-2"
}

variable "management_account_id" {
  type    = string
  default = "835107812500"
}

variable "security_account_id" {
  type    = string
  default = "962635286921"
}

variable "workload_account_id" {
  type    = string
  default = "129264592348"
}
