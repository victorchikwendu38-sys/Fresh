# ==============================================================
# variables.tf — Single source of truth for the entire
#                Wiz Outpost Terraform deployment.
#
# HOW TO USE:
#   1. Copy terraform.tfvars.example → terraform.tfvars
#   2. Fill in every REQUIRED value (no default marked)
#   3. Override any OPTIONAL value if the default doesn't suit
#   4. Run: terraform init && terraform plan && terraform apply
#
# To deploy in a different region / partition (e.g. commercial AWS):
#   Change aws_region    = "us-east-1"
#   Change aws_partition = "aws"
#   Change az_1 / az_2   to match that region's AZ names
# ==============================================================


# ---------------------------------------------------------------
# SECTION 1 — AWS Provider & Account Identity
# ---------------------------------------------------------------

variable "aws_region" {
  type        = string
  default     = "us-gov-west-1"
  description = <<-EOT
    AWS region to deploy all resources into.
    GovCloud options : us-gov-west-1 | us-gov-east-1
    Commercial options: us-east-1 | us-west-2 | eu-west-1 | etc.
  EOT
}

variable "aws_partition" {
  type        = string
  default     = "aws-us-gov"
  description = <<-EOT
    AWS partition used to construct IAM ARNs and policy resources.
    GovCloud  : aws-us-gov
    Commercial: aws
    Change this whenever you change aws_region to a non-GovCloud region.
    All arn:PARTITION: strings in every policy are derived from this variable.
  EOT
  validation {
    condition     = contains(["aws-us-gov", "aws", "aws-cn"], var.aws_partition)
    error_message = "aws_partition must be one of: aws-us-gov, aws, aws-cn."
  }
}

variable "az_1" {
  type        = string
  default     = "us-gov-west-1a"
  description = <<-EOT
    First Availability Zone for private subnet 1 and public subnet 1.
    Must belong to aws_region. Examples:
      us-gov-west-1  → us-gov-west-1a
      us-gov-east-1  → us-gov-east-1a
      us-east-1      → us-east-1a
  EOT
}

variable "az_2" {
  type        = string
  default     = "us-gov-west-1b"
  description = <<-EOT
    Second Availability Zone for private subnet 2 and public subnet 2.
    Must be different from az_1. Examples:
      us-gov-west-1  → us-gov-west-1b
      us-gov-east-1  → us-gov-east-1b
      us-east-1      → us-east-1b
  EOT
}

variable "wiz_outpost_account_id" {
  type        = string
  description = <<-EOT
    REQUIRED. The 12-digit AWS account ID of this dedicated Wiz Outpost account.
    Used in SCP resource ARNs to scope the deny rules to this account.
    Example: "123456789012"
  EOT
  validation {
    condition     = can(regex("^[0-9]{12}$", var.wiz_outpost_account_id))
    error_message = "wiz_outpost_account_id must be exactly 12 digits."
  }
}


# ---------------------------------------------------------------
# SECTION 2 — Naming & Tagging
# ---------------------------------------------------------------

variable "environment_name" {
  type        = string
  default     = "wiz-outpost"
  description = <<-EOT
    Short name prefix applied to every resource (VPC, subnets, roles, EKS
    cluster, ASG, CloudTrail trail, etc.).
    Use lowercase letters, numbers, and hyphens only.
    Changing this is the primary way to run multiple Outpost deployments
    in the same account (e.g. "wiz-outpost-prod" vs "wiz-outpost-dev").
  EOT
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment_name))
    error_message = "environment_name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "tags_common" {
  type        = map(string)
  default     = {
    ManagedBy   = "Terraform"
    Purpose     = "WizOutpost"
    Compliance  = "FedRAMP-High"
  }
  description = <<-EOT
    Tags applied to every resource. Merge or override as needed.
    These are merged with resource-specific tags via merge(var.tags_common, {...}).
  EOT
}


# ---------------------------------------------------------------
# SECTION 3 — VPC & Networking
# ---------------------------------------------------------------

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = <<-EOT
    CIDR block for the Wiz-Outpost-VPC.
    Must not overlap with any other VPCs you intend to peer or connect via
    Transit Gateway. Change if 10.0.0.0/16 conflicts with your network.
  EOT
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "private_subnet_1_cidr" {
  type        = string
  default     = "10.0.1.0/24"
  description = "CIDR for private subnet in AZ-1. EKS worker nodes live here."
}

variable "private_subnet_2_cidr" {
  type        = string
  default     = "10.0.2.0/24"
  description = "CIDR for private subnet in AZ-2. EKS worker nodes live here."
}

variable "public_subnet_1_cidr" {
  type        = string
  default     = "10.0.100.0/24"
  description = "CIDR for public subnet in AZ-1. NAT Gateway lives here — no worker nodes."
}

variable "public_subnet_2_cidr" {
  type        = string
  default     = "10.0.101.0/24"
  description = "CIDR for public subnet in AZ-2. NAT Gateway lives here — no worker nodes."
}


# ---------------------------------------------------------------
# SECTION 4 — Wiz Tenant Credentials
#             (obtain both values from gov.wiz.io)
# ---------------------------------------------------------------

variable "wiz_gov_tenant_account_id" {
  type        = string
  description = <<-EOT
    REQUIRED. The 12-digit AWS account ID of the Wiz GovCloud tenant.
    This is NOT your account — it is Wiz's own AWS account that will
    call sts:AssumeRole on WizOrchestratorRole.
    Obtain from your Wiz federal account team or from
    gov.wiz.io → Settings → Connectors → Deploy Outpost.
  EOT
  validation {
    condition     = can(regex("^[0-9]{12}$", var.wiz_gov_tenant_account_id))
    error_message = "wiz_gov_tenant_account_id must be exactly 12 digits."
  }
}

variable "wiz_external_id" {
  type        = string
  sensitive   = true
  description = <<-EOT
    REQUIRED. The External ID Wiz generates for your tenant.
    Treat this as a secret — do not commit it to source control.
    Obtain from gov.wiz.io → Settings → Connectors → Deploy Outpost.
    Store in AWS Secrets Manager or your CI/CD secrets store,
    then reference it here via TF_VAR_wiz_external_id or a secret backend.
  EOT
}


# ---------------------------------------------------------------
# SECTION 5 — EKS Cluster
# ---------------------------------------------------------------

variable "kubernetes_version" {
  type        = string
  default     = "1.30"
  description = <<-EOT
    Kubernetes version for the EKS cluster.
    Check AWS EKS documentation for currently supported versions.
    Supported examples: "1.29" | "1.30" | "1.31"
    Note: Once deployed, upgrading requires a terraform apply with
    the new version value — EKS performs a rolling control-plane upgrade.
  EOT
  validation {
    condition     = can(regex("^1\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must be in format '1.XX' (e.g. '1.30')."
  }
}

variable "eks_log_retention_days" {
  type        = number
  default     = 365
  description = <<-EOT
    CloudWatch log retention in days for EKS control plane logs.
    FedRAMP AU-11 minimum is 365 days (1 year).
    Valid values: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400,
                  545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653.
  EOT
}


# ---------------------------------------------------------------
# SECTION 6 — KMS Key
# ---------------------------------------------------------------

variable "kms_deletion_window_days" {
  type        = number
  default     = 30
  description = <<-EOT
    Number of days AWS waits before permanently deleting the KMS CMK
    after a DeleteKey request. Range: 7–30.
    30 days is recommended for production — gives maximum recovery window.
    Lower this (minimum 7) only in short-lived test environments.
  EOT
  validation {
    condition     = var.kms_deletion_window_days >= 7 && var.kms_deletion_window_days <= 30
    error_message = "kms_deletion_window_days must be between 7 and 30."
  }
}


# ---------------------------------------------------------------
# SECTION 7 — EC2 Node Pool & Launch Template
# ---------------------------------------------------------------

variable "wiz_stig_ami_id" {
  type        = string
  description = <<-EOT
    REQUIRED. AMI ID of the Wiz STIG-hardened image subscribed to in AWS Marketplace.
    This value is region-specific — the same AMI product has a different
    ID in us-gov-west-1 vs us-gov-east-1 vs us-east-1.

    Retrieve the correct ID for your region with:
      aws ec2 describe-images \
        --owners aws-marketplace \
        --filters "Name=name,Values=*wiz*stig*" "Name=state,Values=available" \
        --region <YOUR_REGION> \
        --query 'sort_by(Images,&CreationDate)[-1].ImageId' \
        --output text

    Current latest version: 1.33.20260420
    Example value: "ami-0abc1234def567890"
  EOT
  validation {
    condition     = can(regex("^ami-[0-9a-f]{8,17}$", var.wiz_stig_ami_id))
    error_message = "wiz_stig_ami_id must be a valid AMI ID (e.g. ami-0abc1234def567890)."
  }
}

variable "node_instance_type" {
  type        = string
  default     = "m5.2xlarge"
  description = <<-EOT
    EC2 instance type for Wiz scanning worker nodes.
    Recommendations:
      m5.2xlarge  (8 vCPU / 32 GB)  — minimum recommended for disk scanning
      m5.4xlarge  (16 vCPU / 64 GB) — for high-volume environments
      m5.8xlarge  (32 vCPU / 128 GB)— for very large workload footprints
    Note: For GovCloud, confirm instance type availability:
      aws ec2 describe-instance-type-offerings --region us-gov-west-1
  EOT
}

variable "node_volume_size_gb" {
  type        = number
  default     = 100
  description = <<-EOT
    Root EBS volume size in GB for each EKS worker node.
    Wiz recommends 100 GB minimum. Increase if scanning very large disk images.
  EOT
  validation {
    condition     = var.node_volume_size_gb >= 50 && var.node_volume_size_gb <= 500
    error_message = "node_volume_size_gb must be between 50 and 500."
  }
}

variable "node_group_min_size" {
  type        = number
  default     = 2
  description = <<-EOT
    Minimum number of EC2 nodes in the Auto Scaling Group.
    Keep at 2+ for HA across two AZs.
  EOT
}

variable "node_group_max_size" {
  type        = number
  default     = 10
  description = <<-EOT
    Maximum number of EC2 nodes the Auto Scaling Group can scale to.
    Governs maximum scanning parallelism and cost ceiling.
  EOT
}

variable "node_group_desired_size" {
  type        = number
  default     = 2
  description = "Initial desired node count at deployment time."
}

variable "node_health_check_grace_period" {
  type        = number
  default     = 300
  description = <<-EOT
    Seconds to wait after a new node launches before the ASG starts
    health checks. Must be long enough for the EKS bootstrap script
    to complete and the node to register with the cluster.
    Default 300 (5 min) is sufficient for the Wiz STIG AMI.
  EOT
}

variable "imds_hop_limit" {
  type        = number
  default     = 1
  description = <<-EOT
    EC2 Instance Metadata Service hop limit.
    1 = only the host OS can reach IMDS (FedRAMP compliant — prevents
        container workloads from accessing node credentials via SSRF).
    Do not increase above 1 in production.
  EOT
  validation {
    condition     = var.imds_hop_limit >= 1 && var.imds_hop_limit <= 2
    error_message = "imds_hop_limit must be 1 (recommended) or 2."
  }
}


# ---------------------------------------------------------------
# SECTION 8 — CloudTrail & Audit Log Retention
# ---------------------------------------------------------------

variable "cloudtrail_log_retention_days" {
  type        = number
  default     = 365
  description = <<-EOT
    CloudWatch log group retention in days for CloudTrail events.
    FedRAMP AU-11 minimum: 365 days.
  EOT
}

variable "cloudtrail_s3_transition_ia_days" {
  type        = number
  default     = 90
  description = <<-EOT
    Days after which CloudTrail S3 objects transition to STANDARD_IA storage.
    Reduces cost for logs older than 90 days.
  EOT
}

variable "cloudtrail_s3_transition_glacier_days" {
  type        = number
  default     = 365
  description = <<-EOT
    Days after which CloudTrail S3 objects transition to GLACIER.
    Glacier is cheapest for long-term audit archive.
  EOT
}

variable "cloudtrail_s3_expiration_days" {
  type        = number
  default     = 1095
  description = <<-EOT
    Days after which CloudTrail S3 objects are permanently deleted.
    Default 1095 = 3 years, meeting FedRAMP AU-11 requirement.
    Do not set below 1095 in a FedRAMP environment.
  EOT
  validation {
    condition     = var.cloudtrail_s3_expiration_days >= 1095
    error_message = "cloudtrail_s3_expiration_days must be at least 1095 (3 years) for FedRAMP compliance."
  }
}
