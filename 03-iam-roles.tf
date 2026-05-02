# ==============================================================
# 03-iam-roles.tf — Three WizOrchestrator IAM roles,
#                   EC2 instance profile, inline scanning policy.
#
# aws_partition variable drives all arn:PARTITION: strings.
# Swap aws_partition = "aws" to redeploy against commercial AWS.
# ==============================================================

# ---------------------------------------------------------------
# Local: compute the ARN partition prefix once, use everywhere
# ---------------------------------------------------------------
locals {
  iam_arn_prefix = "arn:${var.aws_partition}:iam"
  account_id     = data.aws_caller_identity.current.account_id
  region         = data.aws_region.current.name
}

# ================================================================
# ROLE 1: WizOrchestratorRole
# Assumed by gov.wiz.io to deploy/manage the Outpost in this account.
# ================================================================
resource "aws_iam_role" "wiz_orchestrator" {
  name        = "WizOrchestratorRole"
  description = "Assumed by Wiz GovCloud control plane to orchestrate the Outpost EKS cluster."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "${local.iam_arn_prefix}::${var.wiz_gov_tenant_account_id}:root"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = { "sts:ExternalId" = var.wiz_external_id }
      }
    }]
  })

  inline_policy {
    name = "WizOrchestratorPolicy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid    = "EKSOrchestration"
          Effect = "Allow"
          Action = [
            "eks:CreateCluster", "eks:DeleteCluster", "eks:DescribeCluster",
            "eks:ListClusters", "eks:UpdateClusterConfig", "eks:UpdateClusterVersion",
            "eks:CreateNodegroup", "eks:DeleteNodegroup", "eks:DescribeNodegroup",
            "eks:UpdateNodegroupConfig", "eks:TagResource", "eks:UntagResource",
            "eks:CreateAddon", "eks:DescribeAddon", "eks:DeleteAddon"
          ]
          Resource = "*"
        },
        {
          Sid    = "PassRolesToAWS"
          Effect = "Allow"
          Action = "iam:PassRole"
          Resource = [
            "${local.iam_arn_prefix}::${local.account_id}:role/WizOrchestratorNodePoolRole",
            "${local.iam_arn_prefix}::${local.account_id}:role/WizOrchestratorEKSRole"
          ]
        },
        {
          Sid    = "NetworkingReadOnly"
          Effect = "Allow"
          Action = [
            "ec2:DescribeSubnets", "ec2:DescribeVpcs", "ec2:DescribeSecurityGroups",
            "ec2:DescribeInstances", "ec2:DescribeInstanceTypes",
            "ec2:DescribeAvailabilityZones", "ec2:DescribeLaunchTemplates",
            "ec2:DescribeLaunchTemplateVersions"
          ]
          Resource = "*"
        },
        {
          Sid    = "LaunchTemplateManagement"
          Effect = "Allow"
          Action = [
            "ec2:CreateLaunchTemplate", "ec2:CreateLaunchTemplateVersion",
            "ec2:DeleteLaunchTemplate", "ec2:ModifyLaunchTemplate"
          ]
          Resource = "*"
        },
        {
          Sid    = "AutoScalingManagement"
          Effect = "Allow"
          Action = [
            "autoscaling:CreateAutoScalingGroup", "autoscaling:DeleteAutoScalingGroup",
            "autoscaling:DescribeAutoScalingGroups", "autoscaling:UpdateAutoScalingGroup",
            "autoscaling:CreateOrUpdateTags"
          ]
          Resource = "*"
        },
        {
          Sid    = "SecurityGroupManagement"
          Effect = "Allow"
          Action = [
            "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
            "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
            "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
            "ec2:CreateTags"
          ]
          Resource = "*"
        },
        {
          Sid    = "LogsSetup"
          Effect = "Allow"
          Action = [
            "logs:CreateLogGroup", "logs:CreateLogDelivery",
            "logs:PutLogEvents", "logs:DescribeLogGroups"
          ]
          Resource = "*"
        },
        {
          Sid    = "SecretsAccess"
          Effect = "Allow"
          Action = [
            "secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret",
            "ssm:GetParameter", "ssm:GetParameters"
          ]
          Resource = [
            "arn:${var.aws_partition}:secretsmanager:${local.region}:${local.account_id}:secret:wiz-*",
            "arn:${var.aws_partition}:ssm:${local.region}:${local.account_id}:parameter/wiz/*"
          ]
        }
      ]
    })
  }

  tags = merge(var.tags_common, {
    Name = "WizOrchestratorRole"
  })
}

# ================================================================
# ROLE 2: WizOrchestratorNodePoolRole
# Identity worn by every EC2 worker node in the EKS node pool.
# ================================================================
resource "aws_iam_role" "wiz_node_pool" {
  name        = "WizOrchestratorNodePoolRole"
  description = "Instance role for Wiz Outpost EKS worker nodes."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags_common, {
    Name = "WizOrchestratorNodePoolRole"
  })
}

# Managed policy attachments — partition-aware ARNs
resource "aws_iam_role_policy_attachment" "node_pool_eks_worker" {
  role       = aws_iam_role.wiz_node_pool.name
  policy_arn = "${local.iam_arn_prefix}::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_pool_cni" {
  role       = aws_iam_role.wiz_node_pool.name
  policy_arn = "${local.iam_arn_prefix}::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_pool_ecr" {
  role       = aws_iam_role.wiz_node_pool.name
  policy_arn = "${local.iam_arn_prefix}::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_pool_ssm" {
  role       = aws_iam_role.wiz_node_pool.name
  policy_arn = "${local.iam_arn_prefix}::aws:policy/AmazonSSMManagedInstanceCore"
}

# Inline workload scanning policy
resource "aws_iam_role_policy" "wiz_workload_scanning" {
  name = "WizWorkloadScanningPolicy"
  role = aws_iam_role.wiz_node_pool.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EBSSnapshotScanning"
        Effect = "Allow"
        Action = [
          "ec2:CreateSnapshot", "ec2:CopySnapshot", "ec2:DescribeSnapshots",
          "ec2:DeleteSnapshot", "ec2:DescribeVolumes", "ec2:DescribeInstances",
          "ec2:DescribeImages", "ec2:DescribeTags"
        ]
        Resource = "*"
      },
      {
        Sid    = "KMSForEncryptedVolumes"
        Effect = "Allow"
        Action = [
          "kms:CreateGrant", "kms:Decrypt", "kms:DescribeKey",
          "kms:GenerateDataKey", "kms:ReEncryptFrom", "kms:ReEncryptTo"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ec2.${local.region}.amazonaws.com"
          }
        }
      },
      {
        Sid    = "CloudWatchMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      }
    ]
  })
}

# EC2 Instance Profile — wraps role for EC2 attachment at boot
resource "aws_iam_instance_profile" "wiz_node_pool" {
  name = "WizOrchestratorNodePoolRole"
  role = aws_iam_role.wiz_node_pool.name
}

# ================================================================
# ROLE 3: WizOrchestratorEKSRole
# Worn by the EKS cluster control plane to manage VPC resources.
# ================================================================
resource "aws_iam_role" "wiz_eks" {
  name        = "WizOrchestratorEKSRole"
  description = "Service role for the Wiz Outpost EKS cluster."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags_common, {
    Name = "WizOrchestratorEKSRole"
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.wiz_eks.name
  policy_arn = "${local.iam_arn_prefix}::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_vpc_controller" {
  role       = aws_iam_role.wiz_eks.name
  policy_arn = "${local.iam_arn_prefix}::aws:policy/AmazonEKSVPCResourceController"
}

# ---------------------------------------------------------------
