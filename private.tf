locals {
  private_azs     = local.private_enabled ? { for idx, az in var.availability_zones : az => idx } : {}
  private_newbits = var.desired_newbits == 0 ? ceil(log(var.max_subnets, 2)) : var.desired_newbits
}

module "private_label" {
  source  = "cloudposse/label/null"
  version = "0.24.1"

  # Attributes will be provided from input
  # attributes = ["private"]

  context = module.this.context
}

resource "aws_subnet" "private" {
  for_each = local.private_azs

  vpc_id            = var.vpc_id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.cidr_block, local.private_newbits, var.starting_netsum + each.value)

  tags = merge(
    module.private_label.tags,
    {
      "Name" = "${module.private_label.id}${module.this.delimiter}${split("-", each.key)[0]}${substr(split("-", each.key)[1], 0, 1)}${split("-", each.key)[2]}"
      "Type" = var.type
    },
  )
}

resource "aws_network_acl" "private" {
  count = local.private_enabled && var.private_network_acl_id == "" ? 1 : 0

  vpc_id     = var.vpc_id
  subnet_ids = values(aws_subnet.private)[*].id
  dynamic "egress" {
    for_each = var.private_network_acl_egress
    content {
      action          = lookup(egress.value, "action", null)
      cidr_block      = lookup(egress.value, "cidr_block", null)
      from_port       = lookup(egress.value, "from_port", null)
      icmp_code       = lookup(egress.value, "icmp_code", null)
      icmp_type       = lookup(egress.value, "icmp_type", null)
      ipv6_cidr_block = lookup(egress.value, "ipv6_cidr_block", null)
      protocol        = lookup(egress.value, "protocol", null)
      rule_no         = lookup(egress.value, "rule_no", null)
      to_port         = lookup(egress.value, "to_port", null)
    }
  }
  dynamic "ingress" {
    for_each = var.private_network_acl_ingress
    content {
      action          = lookup(ingress.value, "action", null)
      cidr_block      = lookup(ingress.value, "cidr_block", null)
      from_port       = lookup(ingress.value, "from_port", null)
      icmp_code       = lookup(ingress.value, "icmp_code", null)
      icmp_type       = lookup(ingress.value, "icmp_type", null)
      ipv6_cidr_block = lookup(ingress.value, "ipv6_cidr_block", null)
      protocol        = lookup(ingress.value, "protocol", null)
      rule_no         = lookup(ingress.value, "rule_no", null)
      to_port         = lookup(ingress.value, "to_port", null)
    }
  }
  tags       = module.private_label.tags
  depends_on = [aws_subnet.private]
}

resource "aws_route_table" "private" {
  for_each = local.private_azs

  vpc_id = var.vpc_id

  tags = merge(
    module.private_label.tags,
    {
      "Name" = "${var.namespace}${module.this.delimiter}${var.environment}${module.this.delimiter}${var.route_table_attribute}${module.this.delimiter}rt${module.this.delimiter}${split("-", each.key)[0]}${substr(split("-", each.key)[1], 0, 1)}${split("-", each.key)[2]}"
      "Type" = var.type
    },
  )
}

resource "aws_route_table_association" "private" {
  for_each = local.private_azs

  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private[each.key].id
  depends_on = [
    aws_subnet.private,
    aws_route_table.private,
  ]
}

resource "aws_route" "default" {
  for_each = var.az_ngw_ids

  route_table_id         = aws_route_table.private[each.key].id
  nat_gateway_id         = each.value
  destination_cidr_block = "0.0.0.0/0"
  depends_on             = [aws_route_table.private]
}
