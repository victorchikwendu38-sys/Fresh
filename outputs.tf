# ==============================================================
# outputs.tf — All Terraform outputs for the Wiz Outpost deployment.
#
# Outputs are grouped by the resource file they originate from.
# After a successful apply, run:
#   terraform output
# to print all values, or:
#   terraform output <name>
# to retrieve a specific value for use in scripts or downstream
# configuration (e.g. pasting the EKS cluster name into gov.wiz.io).
#
# Sensitive outputs (marked sensitive = true) are redacted in
# console output but accessible via:
#   terraform output -raw <name>
# ==============================================================


# ---------------------------------------------------------------
# 01-vpc.tf — VPC & Networking
# ---------------------------------------------------------------

output "vpc_id" {
  description = "ID of the Wiz-Outpost-VPC. Reference this when peering or attaching a Transit Gateway."
  value       = aws_vpc.wiz_outpost.id
}

output "vpc_cidr" {
  description = "CIDR block of the Wiz-Outpost-VPC."
  value       = aws_vpc.wiz_outpost.cidr_block
}

output "private_subnet_1_id" {
  description = "ID of private subnet 1 (AZ-1). EKS worker nodes are placed here."
  value       = aws_subnet.private_1.id
}

output "private_subnet_2_id" {
  description = "ID of private subnet 2 (AZ-2). EKS worker nodes are placed here."
  value       = aws_subnet.private_2.id
}

output "eks_node_sg_id" {
  description = "Security group ID attached to EKS worker nodes. Reference this if adding additional ingress rules."
  value       = aws_security_group.eks_nodes.id
}

output "vpce_sg_id" {
  description = "Security group ID for VPC Interface Endpoints."
  value       = aws_security_group.vpce.id
}


# ---------------------------------------------------------------
# 02-kms.tf — KMS Customer Managed Key
# ---------------------------------------------------------------

output "cmk_arn" {
  description = "ARN of the KMS CMK used for EBS volume encryption. Paste this into any additional resource that needs to encrypt data with the same key."
  value       = aws_kms_key.wiz_outpost_ebs.arn
}

output "cmk_id" {
  description = "Key ID of the KMS CMK. Use this when referencing the key in AWS console or CLI commands."
  value       = aws_kms_key.wiz_outpost_ebs.key_id
}


# ---------------------------------------------------------------
# 03-iam-roles.tf — IAM Roles & Instance Profile
# ---------------------------------------------------------------

output "wiz_orchestrator_role_arn" {
  description = "ARN of WizOrchestratorRole. Paste this into gov.wiz.io when configuring the Outpost connector."
  value       = aws_iam_role.wiz_orchestrator.arn
}

output "wiz_node_pool_role_arn" {
  description = "ARN of WizOrchestratorNodePoolRole. Worn by every EKS worker node as its EC2 instance identity."
  value       = aws_iam_role.wiz_node_pool.arn
}

output "wiz_eks_role_arn" {
  description = "ARN of WizOrchestratorEKSRole. Assumed by the EKS control plane to manage VPC resources."
  value       = aws_iam_role.wiz_eks.arn
}

output "instance_profile_arn" {
  description = "ARN of the EC2 Instance Profile that wraps WizOrchestratorNodePoolRole for EC2 attachment."
  value       = aws_iam_instance_profile.wiz_node_pool.arn
}


# ---------------------------------------------------------------
# 04-eks-cluster.tf — EKS Cluster
# ---------------------------------------------------------------

output "eks_cluster_name" {
  description = "Name of the EKS cluster. Used in kubectl commands and when registering the cluster in gov.wiz.io."
  value       = aws_eks_cluster.wiz_outpost.name
}

output "eks_cluster_arn" {
  description = "ARN of the EKS cluster."
  value       = aws_eks_cluster.wiz_outpost.arn
}

output "eks_cluster_endpoint" {
  description = "Private API server endpoint URL. Only reachable from within the VPC (endpointPublicAccess = false)."
  value       = aws_eks_cluster.wiz_outpost.endpoint
}

output "eks_oidc_issuer" {
  description = "OIDC issuer URL for the EKS cluster. Used if configuring IAM Roles for Service Accounts (IRSA)."
  value       = aws_eks_cluster.wiz_outpost.identity[0].oidc[0].issuer
}


# ---------------------------------------------------------------
# 05-launch-template-nodegroup.tf — Node Pool
# ---------------------------------------------------------------

output "launch_template_id" {
  description = "ID of the EC2 Launch Template used to provision Wiz STIG AMI worker nodes."
  value       = aws_launch_template.wiz_node.id
}

output "asg_name" {
  description = "Name of the Auto Scaling Group managing the Wiz worker node pool."
  value       = aws_autoscaling_group.wiz_nodes.name
}


# ---------------------------------------------------------------
# 06-scp-protection.tf — SCP
# ---------------------------------------------------------------

output "scp_id" {
  description = "ID of the AWS Organizations SCP that protects the three WizOrchestrator roles from deletion or modification."
  value       = aws_organizations_policy.wiz_role_protection.id
}


# ---------------------------------------------------------------
# 07-cloudtrail.tf — Audit Logging
# ---------------------------------------------------------------

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail trail capturing all management and data events in the Outpost account."
  value       = aws_cloudtrail.wiz_outpost.arn
}

output "cloudtrail_bucket" {
  description = "Name of the S3 bucket storing CloudTrail logs. Logs are KMS-encrypted and retained per FedRAMP AU-11."
  value       = aws_s3_bucket.cloudtrail_logs.id
}
