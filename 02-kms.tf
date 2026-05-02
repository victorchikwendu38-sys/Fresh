# ==============================================================
# 02-kms.tf — KMS Customer Managed Key for EBS encryption.
#
# aws_partition variable drives all ARN prefixes.
# Changing aws_partition = "aws" redeploys to commercial AWS.
# kms_deletion_window_days controls the safety window.
# ==============================================================

resource "aws_kms_key" "wiz_outpost_ebs" {
  description             = "CMK for Wiz Outpost EBS volume encryption (${var.environment_name})"
  enable_key_rotation     = true                         # FedRAMP SC-12: automatic annual rotation
  multi_region            = false                        # GovCloud: keys are region-locked
  deletion_window_in_days = var.kms_deletion_window_days # Configurable safety window

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Root account full control — required to prevent accidental lockout
      {
        Sid    = "EnableRootAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${var.aws_partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },

      # EKS nodes (WizOrchestratorNodePoolRole) decrypt + generate keys for EBS
      {
        Sid    = "AllowNodePoolRoleEBSUsage"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${var.aws_partition}:iam::${data.aws_caller_identity.current.account_id}:role/WizOrchestratorNodePoolRole"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:GenerateDataKeyWithoutPlaintext",
          "kms:DescribeKey",
          "kms:CreateGrant",
          "kms:ListGrants",
          "kms:RevokeGrant"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            # Restrict key usage to EC2 service API calls only (snapshot operations)
            "kms:ViaService" = "ec2.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      },

      # EC2 service itself (for EBS snapshot encryption/copy)
      {
        Sid    = "AllowEC2EBSSnapshotEncryption"
        Effect = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:CreateGrant",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ec2.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      },

      # EKS cluster role — read-only key metadata
      {
        Sid    = "AllowEKSRoleDescribe"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${var.aws_partition}:iam::${data.aws_caller_identity.current.account_id}:role/WizOrchestratorEKSRole"
        }
        Action   = ["kms:DescribeKey", "kms:ListGrants"]
        Resource = "*"
      },

      # CloudTrail — encrypt its own log delivery (AU-9)
      {
        Sid    = "AllowCloudTrailLogging"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action   = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.tags_common, {
    Name    = "${var.environment_name}-ebs-cmk"
    FedRAMP = "SC-28"
  })
}

resource "aws_kms_alias" "wiz_outpost_ebs" {
  name          = "alias/${var.environment_name}-ebs-cmk"
  target_key_id = aws_kms_key.wiz_outpost_ebs.key_id
}

# ---------------------------------------------------------------
