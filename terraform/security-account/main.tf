# GuardDuty - Security Account (Delegated Admin)
resource "aws_guardduty_detector" "security-detector" {
  enable = true

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = false
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  tags = {
    Project     = "poc-aws-security"
    Environment = "security"
  }
}

# GuardDuty - Workload Account
resource "aws_guardduty_detector" "workload-detector" {
  provider = aws.workload
  enable   = true

  tags = {
    Project     = "poc-aws-security"
    Environment = "workload"
  }
}

# Security Hub - Security Account
resource "aws_securityhub_account" "security-account" {
  enable_default_standards = true
}

# Enable AWS Foundational Security Best Practices
resource "aws_securityhub_standards_subscription" "fsbp" {
  depends_on    = [aws_securityhub_account.security-account]
  standards_arn = "arn:aws:securityhub:ap-southeast-2::standards/aws-foundational-security-best-practices/v/1.0.0"
}

# Enable CIS AWS Foundations
resource "aws_securityhub_standards_subscription" "cis" {
  depends_on    = [aws_securityhub_account.security-account]
  standards_arn = "arn:aws:securityhub:ap-southeast-2::standards/cis-aws-foundations-benchmark/v/1.4.0"
}

# CloudTrail - Org level
resource "aws_cloudtrail" "cloudtrail-org" {
  name                          = "poc-aws-security-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail-s3-bucket.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  tags = {
    Project     = "poc-aws-security"
    Environment = "security"
  }
}

# S3 Bucket for CloudTrail
resource "aws_s3_bucket" "cloudtrail-s3-bucket" {
  bucket        = "poc-aws-security-cloudtrail-${var.security_account_id}"
  force_destroy = true

  tags = {
    Project     = "poc-aws-security"
    Environment = "security"
  }
}

resource "aws_s3_bucket_versioning" "cloudtrail-s3-bucket-versioning" {
  bucket = aws_s3_bucket.cloudtrail-s3-bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail-s3-bucket-public-access-block" {
  bucket                  = aws_s3_bucket.cloudtrail-s3-bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "cloudtrail-s3-bucket-policy" {
  bucket = aws_s3_bucket.cloudtrail-s3-bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail-s3-bucket.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail-s3-bucket.arn}/AWSLogs/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid    = "AWSConfigWrite"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail-s3-bucket.arn}/config/AWSLogs/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid    = "AWSConfigAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail-s3-bucket.arn
      }
    ]
  })
}

# AWS Config - Security Account
resource "aws_config_configuration_recorder" "security-config-recorder" {
  name     = "poc-aws-security-recorder"
  role_arn = aws_iam_role.config-role.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "security-config-delivery" {
  name           = "poc-aws-security-delivery"
  s3_bucket_name = aws_s3_bucket.cloudtrail-s3-bucket.id
  s3_key_prefix  = "config"
  depends_on     = [aws_config_configuration_recorder.security-config-recorder]
}

resource "aws_config_configuration_recorder_status" "security-config-recorder-status" {
  name       = aws_config_configuration_recorder.security-config-recorder.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.security-config-delivery]
}

# IAM Role for AWS Config
resource "aws_iam_role" "config-role" {
  name = "poc-aws-security-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "config.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "config-role-attachment" {
  role       = aws_iam_role.config-role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

# Config Rules
resource "aws_config_config_rule" "s3_public_access-prohibited" {
  name        = "s3-bucket-public-access-prohibited"
  description = "Checks S3 buckets do not allow public access"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_LEVEL_PUBLIC_ACCESS_PROHIBITED"
  }

  depends_on = [aws_config_configuration_recorder_status.security-config-recorder-status]
}

resource "aws_config_config_rule" "encrypted_volumes" {
  name        = "encrypted-volumes"
  description = "Checks EBS volumes are encrypted"

  source {
    owner             = "AWS"
    source_identifier = "ENCRYPTED_VOLUMES"
  }

  depends_on = [aws_config_configuration_recorder_status.security-config-recorder-status]
}

resource "aws_config_config_rule" "root_mfa" {
  name        = "root-account-mfa-enabled"
  description = "Checks root account has MFA enabled"

  source {
    owner             = "AWS"
    source_identifier = "ROOT_ACCOUNT_MFA_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder_status.security-config-recorder-status]
}

