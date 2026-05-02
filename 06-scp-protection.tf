# ==============================================================
# 06-scp-protection.tf — SCP protecting Wiz orchestrator roles.
#
# aws_partition variable drives all ARN prefixes.
# wiz_outpost_account_id scopes the deny to this account only.
#
# IMPORTANT: Apply with management account credentials.
#   export AWS_PROFILE=org-management-account
#   terraform apply -target=aws_organizations_policy.wiz_role_protection
# ==============================================================

locals {
  # Compute once — reused across all four SCP statements
  wiz_role_arns = [
    "arn:${var.aws_partition}:iam::${var.wiz_outpost_account_id}:role/WizOrchestratorRole",
    "arn:${var.aws_partition}:iam::${var.wiz_outpost_account_id}:role/WizOrchestratorNodePoolRole",
    "arn:${var.aws_partition}:iam::${var.wiz_outpost_account_id}:role/WizOrchestratorEKSRole"
  ]

  cfn_exempt_arns = [
    "arn:${var.aws_partition}:iam::${var.wiz_outpost_account_id}:role/stacksets-exec-*",
    "arn:${var.aws_partition}:iam::${var.wiz_outpost_account_id}:role/AWSCloudFormationStackSetExecutionRole"
  ]
}

resource "aws_organizations_policy" "wiz_role_protection" {
  name        = "${var.environment_name}-protect-orchestrator-roles"
  description = "Prevents deletion/modification of WizOrchestrator IAM roles in the Outpost account."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DenyDeleteWizRoles"
        Effect   = "Deny"
        Action   = ["iam:DeleteRole", "iam:DeleteRolePermissionsBoundary"]
        Resource = local.wiz_role_arns
        Condition = {
          ArnNotLike = { "aws:PrincipalArn" = local.cfn_exempt_arns }
        }
      },
      {
        Sid      = "DenyDetachPoliciesFromWizRoles"
        Effect   = "Deny"
        Action   = ["iam:DetachRolePolicy", "iam:DeleteRolePolicy", "iam:PutRolePolicy"]
        Resource = local.wiz_role_arns
        Condition = {
          ArnNotLike = { "aws:PrincipalArn" = local.cfn_exempt_arns }
        }
      },
      {
        Sid      = "DenyModifyWizRoleTrustPolicy"
        Effect   = "Deny"
        Action   = ["iam:UpdateAssumeRolePolicy"]
        Resource = local.wiz_role_arns
        Condition = {
          ArnNotLike = { "aws:PrincipalArn" = local.cfn_exempt_arns }
        }
      },
      {
        Sid    = "DenyDeleteWizInstanceProfile"
        Effect = "Deny"
        Action = ["iam:DeleteInstanceProfile", "iam:RemoveRoleFromInstanceProfile"]
        Resource = [
          "arn:${var.aws_partition}:iam::${var.wiz_outpost_account_id}:instance-profile/WizOrchestratorNodePoolRole"
        ]
        Condition = {
          ArnNotLike = { "aws:PrincipalArn" = local.cfn_exempt_arns }
        }
      }
    ]
  })

  tags = merge(var.tags_common, {
    Name    = "${var.environment_name}-protect-orchestrator-roles"
    FedRAMP = "AC-3"
  })
}

resource "aws_organizations_policy_attachment" "wiz_role_protection" {
  policy_id = aws_organizations_policy.wiz_role_protection.id
  target_id = var.wiz_outpost_account_id
}

# ---------------------------------------------------------------
