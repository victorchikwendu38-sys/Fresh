# ==============================================================
# 04-eks-cluster.tf — EKS cluster with fully private API endpoint.
#
# kubernetes_version and eks_log_retention_days from variables.tf.
# ==============================================================

resource "aws_cloudwatch_log_group" "eks_control_plane" {
  name              = "/aws/eks/${var.environment_name}/cluster"
  retention_in_days = var.eks_log_retention_days   # Configurable, FedRAMP AU-11 min = 365

  tags = merge(var.tags_common, {
    Name    = "${var.environment_name}-eks-control-plane-logs"
    FedRAMP = "AU-11"
  })
}

resource "aws_eks_cluster" "wiz_outpost" {
  name     = var.environment_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.wiz_eks.arn

  vpc_config {
    subnet_ids              = [aws_subnet.private_1.id, aws_subnet.private_2.id]
    security_group_ids      = [aws_security_group.eks_nodes.id]
    endpoint_public_access  = false   # FedRAMP SC-8: no internet access to API server
    endpoint_private_access = true    # Only reachable within the VPC
  }

  # All control plane log types → CloudWatch (FedRAMP AU-2)
  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  # Envelope encryption of K8s Secrets with CMK (FedRAMP SC-28)
  encryption_config {
    provider {
      key_arn = aws_kms_key.wiz_outpost_ebs.arn
    }
    resources = ["secrets"]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_controller,
    aws_cloudwatch_log_group.eks_control_plane,
  ]

  tags = merge(var.tags_common, {
    Name = "${var.environment_name}-cluster"
  })
}

# ---------------------------------------------------------------
