# ==============================================================
# 05-launch-template-nodegroup.tf — EC2 Launch Template with
#   Wiz STIG AMI + self-managed Auto Scaling Group.
#
# All node sizing, AMI ID, volume, IMDS, and ASG values
# come from variables.tf — nothing is hardcoded here.
# ==============================================================

resource "aws_launch_template" "wiz_node" {
  name          = "${var.environment_name}-wiz-node-lt"
  image_id      = var.wiz_stig_ami_id        # Wiz STIG AMI from Marketplace
  instance_type = var.node_instance_type     # e.g. m5.2xlarge

  # No SSH key pair — Session Manager is used instead (FedRAMP IA-2)

  # Instance Profile loads WizOrchestratorNodePoolRole at boot
  iam_instance_profile {
    name = aws_iam_instance_profile.wiz_node_pool.name
  }

  # FedRAMP IA-2 / SC-8: enforce IMDSv2, prevent container credential theft
  metadata_options {
    http_tokens                 = "required"          # IMDSv2 mandatory
    http_put_response_hop_limit = var.imds_hop_limit  # 1 = host OS only
    http_endpoint               = "enabled"
  }

  # Root EBS volume — encrypted with CMK, size from variables.tf
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.node_volume_size_gb
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = aws_kms_key.wiz_outpost_ebs.arn
      delete_on_termination = true
    }
  }

  # Network interface — private subnet, no public IP
  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.eks_nodes.id]
  }

  # Bootstrap script — joins node to EKS cluster on first boot
  user_data = base64encode(<<-EOT
    #!/bin/bash
    set -ex
    yum install -y aws-cfn-bootstrap
    /etc/eks/bootstrap.sh ${var.environment_name} \
      --kubelet-extra-args \
      "--node-labels=role=wiz-scanner,env=${var.environment_name} \
      --register-with-taints=wiz-scanner=true:NoSchedule"
  EOT
  )

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags_common, {
      Name                                            = "${var.environment_name}-wiz-node"
      "kubernetes.io/cluster/${var.environment_name}" = "owned"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.tags_common, {
      Name      = "${var.environment_name}-wiz-node-volume"
      Encrypted = "true"
    })
  }

  tags = merge(var.tags_common, {
    Name = "${var.environment_name}-wiz-node-lt"
  })
}

# ---------------------------------------------------------------
# SELF-MANAGED AUTO SCALING GROUP
# Self-managed (not EKS managed) because we use a custom AMI.
# EKS managed node groups cannot accept a custom AMI.
# ---------------------------------------------------------------
resource "aws_autoscaling_group" "wiz_nodes" {
  name             = "${var.environment_name}-wiz-node-asg"
  min_size         = var.node_group_min_size
  max_size         = var.node_group_max_size
  desired_capacity = var.node_group_desired_size

  # Span both private subnets across two AZs for HA
  vpc_zone_identifier = [
    aws_subnet.private_1.id,
    aws_subnet.private_2.id,
  ]

  launch_template {
    id      = aws_launch_template.wiz_node.id
    version = aws_launch_template.wiz_node.latest_version
  }

  health_check_type         = "EC2"
  health_check_grace_period = var.node_health_check_grace_period

  tag {
    key                 = "Name"
    value               = "${var.environment_name}-wiz-node"
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.environment_name}"
    value               = "owned"
    propagate_at_launch = true
  }

  tag {
    key                 = "Purpose"
    value               = "WizOutpost"
    propagate_at_launch = true
  }

  depends_on = [aws_eks_cluster.wiz_outpost]
}

# ---------------------------------------------------------------
