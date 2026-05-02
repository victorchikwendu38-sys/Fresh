# ==============================================================
# 01-vpc.tf — Wiz-Outpost-VPC, subnets, NAT Gateways,
#              route tables, security groups, VPC endpoints.
#
# All configurable values come from variables.tf.
# AZs, CIDRs, environment name, region — all parameterised.
# ==============================================================

# ---------------------------------------------------------------
# VPC
# ---------------------------------------------------------------
resource "aws_vpc" "wiz_outpost" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true   # Required for VPC endpoint DNS resolution
  enable_dns_hostnames = true   # Required for EKS node hostname registration

  tags = merge(var.tags_common, {
    Name = "Wiz-Outpost-VPC"
  })
}

# ---------------------------------------------------------------
# INTERNET GATEWAY  (NAT Gateways live here — nodes do NOT)
# ---------------------------------------------------------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wiz_outpost.id

  tags = merge(var.tags_common, {
    Name = "${var.environment_name}-igw"
  })
}

# ---------------------------------------------------------------
# PUBLIC SUBNETS  (one per AZ — only NAT Gateways go here)
# ---------------------------------------------------------------
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.wiz_outpost.id
  cidr_block              = var.public_subnet_1_cidr
  availability_zone       = var.az_1           # Explicit AZ from variables.tf
  map_public_ip_on_launch = true

  tags = merge(var.tags_common, {
    Name                     = "${var.environment_name}-public-subnet-1"
    "kubernetes.io/role/elb" = "1"
  })
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.wiz_outpost.id
  cidr_block              = var.public_subnet_2_cidr
  availability_zone       = var.az_2           # Explicit AZ from variables.tf
  map_public_ip_on_launch = true

  tags = merge(var.tags_common, {
    Name                     = "${var.environment_name}-public-subnet-2"
    "kubernetes.io/role/elb" = "1"
  })
}

# ---------------------------------------------------------------
# PRIVATE SUBNETS  (EKS worker nodes live here — no public IPs)
# ---------------------------------------------------------------
resource "aws_subnet" "private_1" {
  vpc_id                  = aws_vpc.wiz_outpost.id
  cidr_block              = var.private_subnet_1_cidr
  availability_zone       = var.az_1
  map_public_ip_on_launch = false

  tags = merge(var.tags_common, {
    Name                                            = "${var.environment_name}-private-subnet-1"
    "kubernetes.io/role/internal-elb"               = "1"
    "kubernetes.io/cluster/${var.environment_name}" = "shared"
  })
}

resource "aws_subnet" "private_2" {
  vpc_id                  = aws_vpc.wiz_outpost.id
  cidr_block              = var.private_subnet_2_cidr
  availability_zone       = var.az_2
  map_public_ip_on_launch = false

  tags = merge(var.tags_common, {
    Name                                            = "${var.environment_name}-private-subnet-2"
    "kubernetes.io/role/internal-elb"               = "1"
    "kubernetes.io/cluster/${var.environment_name}" = "shared"
  })
}

# ---------------------------------------------------------------
# ELASTIC IPs + NAT GATEWAYS  (one per AZ for high availability)
# Private nodes route outbound traffic (gov.wiz.io) via NAT.
# ---------------------------------------------------------------
resource "aws_eip" "nat_1" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]

  tags = merge(var.tags_common, {
    Name = "${var.environment_name}-nat-eip-1"
  })
}

resource "aws_eip" "nat_2" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]

  tags = merge(var.tags_common, {
    Name = "${var.environment_name}-nat-eip-2"
  })
}

resource "aws_nat_gateway" "nat_1" {
  allocation_id = aws_eip.nat_1.id
  subnet_id     = aws_subnet.public_1.id

  tags = merge(var.tags_common, {
    Name = "${var.environment_name}-nat-1"
  })
}

resource "aws_nat_gateway" "nat_2" {
  allocation_id = aws_eip.nat_2.id
  subnet_id     = aws_subnet.public_2.id

  tags = merge(var.tags_common, {
    Name = "${var.environment_name}-nat-2"
  })
}

# ---------------------------------------------------------------
# ROUTE TABLES
# ---------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wiz_outpost.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(var.tags_common, {
    Name = "${var.environment_name}-public-rt"
  })
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private_1" {
  vpc_id = aws_vpc.wiz_outpost.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_1.id
  }

  tags = merge(var.tags_common, {
    Name = "${var.environment_name}-private-rt-1"
  })
}

resource "aws_route_table" "private_2" {
  vpc_id = aws_vpc.wiz_outpost.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_2.id
  }

  tags = merge(var.tags_common, {
    Name = "${var.environment_name}-private-rt-2"
  })
}

resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private_1.id
}

resource "aws_route_table_association" "private_2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private_2.id
}

# ---------------------------------------------------------------
# SECURITY GROUP — EKS Worker Nodes
# ---------------------------------------------------------------
resource "aws_security_group" "eks_nodes" {
  name        = "${var.environment_name}-eks-node-sg"
  description = "Wiz Outpost EKS worker nodes: HTTPS out + intra-cluster traffic."
  vpc_id      = aws_vpc.wiz_outpost.id

  # Intra-cluster traffic (self-referencing)
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "Intra-cluster traffic between nodes"
  }

  # HTTPS outbound — gov.wiz.io metadata reporting + AWS service APIs
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS outbound — gov.wiz.io + AWS APIs via NAT"
  }

  # DNS UDP
  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "DNS UDP outbound"
  }

  # DNS TCP
  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "DNS TCP outbound"
  }

  # NTP — required for TLS certificate validation
  egress {
    from_port   = 123
    to_port     = 123
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "NTP time sync"
  }

  tags = merge(var.tags_common, {
    Name = "${var.environment_name}-eks-node-sg"
  })
}

# ---------------------------------------------------------------
# SECURITY GROUP — VPC Endpoints
# ---------------------------------------------------------------
resource "aws_security_group" "vpce" {
  name        = "${var.environment_name}-vpce-sg"
  description = "Interface VPC Endpoints: HTTPS ingress from EKS nodes only."
  vpc_id      = aws_vpc.wiz_outpost.id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
    description     = "HTTPS from EKS nodes to VPC endpoints"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound (endpoints are AWS-managed)"
  }

  tags = merge(var.tags_common, {
    Name = "${var.environment_name}-vpce-sg"
  })
}

# ---------------------------------------------------------------
# VPC ENDPOINTS — keep AWS API traffic inside the VPC
# Region is derived from data.aws_region.current.name (providers.tf)
# so this block works in any region without modification.
# ---------------------------------------------------------------

# S3 Gateway endpoint (free — no SG, no hourly charge)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.wiz_outpost.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [
    aws_route_table.private_1.id,
    aws_route_table.private_2.id,
  ]

  tags = merge(var.tags_common, {
    Name = "${var.environment_name}-s3-endpoint"
  })
}

# Interface endpoints — one resource block covers all 8 services
locals {
  interface_endpoints = {
    ec2         = "com.amazonaws.${data.aws_region.current.name}.ec2"
    ecr_api     = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
    ecr_dkr     = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
    kms         = "com.amazonaws.${data.aws_region.current.name}.kms"
    ssm         = "com.amazonaws.${data.aws_region.current.name}.ssm"
    ssmmessages = "com.amazonaws.${data.aws_region.current.name}.ssmmessages"
    sts         = "com.amazonaws.${data.aws_region.current.name}.sts"
    logs        = "com.amazonaws.${data.aws_region.current.name}.logs"
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoints

  vpc_id              = aws_vpc.wiz_outpost.id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_1.id, aws_subnet.private_2.id]
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = merge(var.tags_common, {
    Name = "${var.environment_name}-${each.key}-endpoint"
  })
}

# ---------------------------------------------------------------
