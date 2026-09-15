# GuardDuty - designate the security account as delegated admin. Must be
# applied before terraform/security-account's aws_guardduty_organization_configuration,
# which relies on this account already being the delegated admin.
resource "aws_guardduty_organization_admin_account" "guardduty_admin" {
  admin_account_id = var.security_account_id
}

# CloudTrail - Organization trail, created from the management account so it
# automatically covers every account in every OU (workloads and security),
# and delivers to the log archive bucket owned by the security account.
resource "aws_cloudtrail" "org_trail" {
  name                          = "poc-aws-security-org-trail"
  s3_bucket_name                = "poc-aws-security-cloudtrail-${var.security_account_id}"
  include_global_service_events = true
  is_multi_region_trail         = true
  is_organization_trail         = true
  enable_log_file_validation    = true

  tags = {
    Project     = "poc-aws-security"
    Environment = "org"
  }
}

# SCP - Deny disabling CloudTrail
resource "aws_organizations_policy" "deny_disable_cloudtrail" {
  name        = "DenyDisableCloudTrail"
  description = "Prevents disabling CloudTrail"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenyDisableCloudTrail"
      Effect = "Deny"
      Action = [
        "cloudtrail:DeleteTrail",
        "cloudtrail:StopLogging",
        "cloudtrail:UpdateTrail"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_organizations_policy_attachment" "deny_disable_cloudtrail_workloads" {
  policy_id = aws_organizations_policy.deny_disable_cloudtrail.id
  target_id = var.workloads_ou_id
}

resource "aws_organizations_policy_attachment" "deny_disable_cloudtrail_security" {
  policy_id = aws_organizations_policy.deny_disable_cloudtrail.id
  target_id = var.security_ou_id
}

# SCP - Deny public S3 buckets
resource "aws_organizations_policy" "deny_public_s3" {
  name        = "DenyPublicS3"
  description = "Prevents creating public S3 buckets"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenyPublicS3"
      Effect = "Deny"
      Action = [
        "s3:PutBucketPublicAccessBlock",
        "s3:DeletePublicAccessBlock"
      ]
      Resource = "*"
      Condition = {
        StringEquals = {
          "s3:publicAccessBlockConfiguration/BlockPublicAcls"       = "false"
          "s3:publicAccessBlockConfiguration/BlockPublicPolicy"     = "false"
          "s3:publicAccessBlockConfiguration/IgnorePublicAcls"      = "false"
          "s3:publicAccessBlockConfiguration/RestrictPublicBuckets" = "false"
        }
      }
    }]
  })
}

resource "aws_organizations_policy_attachment" "deny_public_s3_workloads" {
  policy_id = aws_organizations_policy.deny_public_s3.id
  target_id = var.workloads_ou_id
}

resource "aws_organizations_policy_attachment" "deny_public_s3_security" {
  policy_id = aws_organizations_policy.deny_public_s3.id
  target_id = var.security_ou_id
}

# SCP - Deny leaving AWS Organizations
resource "aws_organizations_policy" "deny_leave_org" {
  name        = "DenyLeaveOrganization"
  description = "Prevents member accounts from leaving the organization"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "DenyLeaveOrg"
      Effect   = "Deny"
      Action   = "organizations:LeaveOrganization"
      Resource = "*"
    }]
  })
}

resource "aws_organizations_policy_attachment" "deny_leave_org_workloads" {
  policy_id = aws_organizations_policy.deny_leave_org.id
  target_id = var.workloads_ou_id
}

resource "aws_organizations_policy_attachment" "deny_leave_org_security" {
  policy_id = aws_organizations_policy.deny_leave_org.id
  target_id = var.security_ou_id
}

# SCP - Deny disabling GuardDuty
resource "aws_organizations_policy" "deny_disable_guardduty" {
  name        = "DenyDisableGuardDuty"
  description = "Prevents disabling GuardDuty"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenyDisableGuardDuty"
      Effect = "Deny"
      Action = [
        "guardduty:DeleteDetector",
        "guardduty:DisassociateFromMasterAccount",
        "guardduty:StopMonitoringMembers",
        "guardduty:UpdateDetector"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_organizations_policy_attachment" "deny_disable_guardduty_workloads" {
  policy_id = aws_organizations_policy.deny_disable_guardduty.id
  target_id = var.workloads_ou_id
}

resource "aws_organizations_policy_attachment" "deny_disable_guardduty_security" {
  policy_id = aws_organizations_policy.deny_disable_guardduty.id
  target_id = var.security_ou_id
}



