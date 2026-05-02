# ==============================================================
# providers.tf — AWS provider configuration.
#
# The provider reads aws_region from variables.tf so the entire
# deployment retargets a different region by changing one value.
# ==============================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Apply common tags to every resource that supports tags.
  # Individual resources merge their own tags on top of these.
  default_tags {
    tags = var.tags_common
  }
}

# ---------------------------------------------------------------
# SHARED DATA SOURCES
# Used across multiple .tf files — declared once here.
# ---------------------------------------------------------------

# Resolves the account ID of the currently-authenticated caller.
# Used in ARN construction throughout IAM and KMS policies.
data "aws_caller_identity" "current" {}

# Resolves the current region name (matches var.aws_region).
# Used in ARN construction and service endpoint names.
data "aws_region" "current" {}
