# ==============================================================
# 07-cloudtrail.tf — CloudTrail audit logging.
#
# All retention periods and lifecycle transition days come from
# variables.tf. aws_partition drives the S3 DataResource ARN.
# ==============================================================

resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket        = "${var.environment_name}-cloudtrail-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = false   # Never auto-delete audit logs

  tags = merge(var.tags_common, {
    Name    = "${var.environment_name}-cloudtrail-logs"
    FedRAMP = "AU-9"
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.wiz_outpost_ebs.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  versioning_configuration { status = "Enabled" }
}

# Lifecycle — controlled entirely by variables.tf
resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  rule {
    id     = "WizAuditLogRetention"
    status = "Enabled"

    transition {
      days          = var.cloudtrail_s3_transition_ia_days      # Default 90
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = var.cloudtrail_s3_transition_glacier_days  # Default 365
      storage_class = "GLACIER"
    }
    expiration {
      days = var.cloudtrail_s3_expiration_days                   # Default 1095 (3 yr)
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail_logs.arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      },
      # Deny non-SSL access — FedRAMP SC-8
      {
        Sid       = "DenyNonSSL"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [
          aws_s3_bucket.cloudtrail_logs.arn,
          "${aws_s3_bucket.cloudtrail_logs.arn}/*"
        ]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/${var.environment_name}"
  retention_in_days = var.cloudtrail_log_retention_days   # Configurable, default 365

  tags = merge(var.tags_common, {
    Name    = "${var.environment_name}-cloudtrail-cw-logs"
    FedRAMP = "AU-11"
  })
}

resource "aws_iam_role" "cloudtrail_cw" {
  name = "${var.environment_name}-cloudtrail-cw-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags_common, {
    Name = "${var.environment_name}-cloudtrail-cw-role"
  })
}

resource "aws_iam_role_policy" "cloudtrail_cw" {
  role = aws_iam_role.cloudtrail_cw.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
    }]
  })
}

resource "aws_cloudtrail" "wiz_outpost" {
  name                          = "${var.environment_name}-audit-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true   # FedRAMP AU-9: detect log tampering
  kms_key_id                    = aws_kms_key.wiz_outpost_ebs.arn
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_cw.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true
    data_resource {
      type   = "AWS::S3::Object"
      # aws_partition variable drives the ARN — works in commercial + GovCloud
      values = ["arn:${var.aws_partition}:s3:::"]
    }
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail]

  tags = merge(var.tags_common, {
    Name    = "${var.environment_name}-audit-trail"
    FedRAMP = "AU-2"
  })
}

# ---------------------------------------------------------------
