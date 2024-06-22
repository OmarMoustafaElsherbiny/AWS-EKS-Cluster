################################################################################
# VPC
################################################################################
resource "aws_vpc" "this" {

  # Create VPC or not
  count = var.create_vpc ? 1 : 0

  # The VPC CIDR block. default is 10.0.0.0/16 
  cidr_block = var.cidr

  # The instance tenancy (not guaranteed on the same rack)
  instance_tenancy     = var.instance_tenancy

  # Enable DNS hostnames
  enable_dns_hostnames = var.enable_dns_hostnames

  # Enable DNS resolution support
  enable_dns_support   = var.enable_dns_support

  # Map/object/dict of tags to assign to the resource.
  tags = merge(
    { "Name" = var.name },
    var.tags,
    var.vpc_tags,
  )
}

################################################################################
# Internet Gateway
################################################################################

resource "aws_internet_gateway" "this" {

  # Create Internet Gateway or not
  count = var.create_igw ? 1 : 0

  # ID of the VPC that the IGW will attach to.
  vpc_id = aws_vpc.this[0].id

  # Map/object/dict of tags to assign to the resource.
  tags = merge(
    { "Name" = "${var.name}-igw" },
    var.tags,
    var.igw_tags,
  )
}

################################################################################
# Public Subnets
################################################################################

locals {
  public_subnets = { for i in range(length(var.public_subnets)) : i => {
    az = var.azs[i % length(var.azs)]
    cidr = var.public_subnets[i]
  } }
}

resource "aws_subnet" "public" {

  # Map that contains the cidr block and the az it belongs to, using cidr as it's key
  for_each = length(var.public_subnets) > 0 ? local.public_subnets : {}

  # Availability zone the subnet should be created in.
  availability_zone = each.value.az

  # The CIDR block for the subnet.
  cidr_block = each.value.cidr

  # The VPC ID the subnet belongs to.
  vpc_id = aws_vpc.this[0].id

  # Enable public IP address
  map_public_ip_on_launch = var.public_subnet_map_public_ip_on_launch 

  # Map/object/dict of tags to assign to the resource.
  tags = merge(
    { "Name" = "${var.name}-${each.value.cidr}-${each.value.az}" },
    var.public_subnet_tags,
    var.tags
  )
}


resource "aws_route_table" "public" {
  for_each = length(var.public_subnets) > 0 ? local.public_subnets : {}

  vpc_id = aws_vpc.this[0].id

  tags = merge(
    {
      "Name" = format(
        "${var.name}-%s-%s-public-rt",
        each.value.az, each.value.cidr,
      ) 
    },
    var.tags,
    var.public_route_table_tags,
  )
}


resource "aws_route_table_association" "public" {
  for_each = length(var.public_subnets) > 0 ? local.public_subnets : {}

  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public[each.key].id
}


resource "aws_route" "public_internet_gateway" {
  for_each = length(var.public_subnets) > 0 ? local.public_subnets : {}

  route_table_id         = aws_route_table.public[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}


################################################################################
# Private Subnets
################################################################################

locals {
  private_subents = { for i in range(length(var.private_subnets)) : i => {
    az = var.azs[i % length(var.azs)]
    cidr = var.private_subnets[i]
  } }
}

resource "aws_subnet" "private" {

  # Map that contains the cidr block and the az it belongs to, using cidr as it's key
  for_each = length(var.private_subnets) > 0 ? local.private_subents : {}

  # Availability zone the subnet should be created in.
  availability_zone = each.value.az

  # The CIDR block for the subnet.
  cidr_block = each.value.cidr

  # The VPC ID the subnet belongs to.
  vpc_id = aws_vpc.this[0].id

  # Map/object/dict of tags to assign to the resource.
  tags = merge(
    { "Name" = "${var.name}-${each.value.cidr}-${each.value.az}" },
    var.private_subnet_tags,
    var.tags
  ) 
}

resource "aws_route_table" "private" {
  for_each = length(var.private_subnets) > 0 ? local.private_subents : {}

  vpc_id = aws_vpc.this[0].id

  tags = merge(
    {
      "Name" = format(
        "${var.name}-%s-%s-private-rt",
        each.value.az, each.value.cidr,
      ) 
    },
    var.tags,
    var.private_route_table_tags,
  )
}

resource "aws_route_table_association" "private" {
  for_each = length(var.private_subnets) > 0 ? local.private_subents : {}

  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}

################################################################################
# EC2 instance Conncect Endpoint
################################################################################

resource "aws_ec2_instance_connect_endpoint" "this" {
  count = var.create_ec2_endpoint ? 1 : 0

  # Place the endpoint in the first private subnet
  subnet_id = aws_subnet.private[0].id
  tags = merge(
    { "Name" = format("${var.name}-ec2-instance-connect-endpoint-%s-%s", 
    aws_subnet.private["0"].availability_zone, 
    aws_subnet.private["0"].cidr_block) 
    },
    var.tags,
    var.ec2_endpoint_tags
  )
}


################################################################################
# NAT Gateway and EIP 
################################################################################


# TODO: aws_eip.nat_eip is empty tuple if create_public_nat_gateway is false, we want to to not create all the NAT resources and create the rest without throwing an erro

resource "aws_eip" "nat_eip" {

  # Create an EIP for each AZ
  count = var.create_public_nat_gateway ? length(var.azs) : 0

  # EIP used in VPCs
  domain = "vpc"

  # Map of tags to assign to the resource.
  tags = merge(
    { "Name" = "${var.name}-Public NAT EIP-${count.index + 1}" },
    var.nat_eip_tags,
    var.tags
  )
}

locals {
  # Creates a map from a for expression to a map of subnet_id and eip_id and filtered by az
  # public subnets and elastic ips are created before hand
  # assuming the public subnets are created with availability zone FIFO order, it garantees that return subnet will be with a unique AZ
  availability_zone_public_subnet = { for i in range(length(var.azs)): 
      i => { subnet_id = aws_subnet.public["${i}"].id, eip_id = aws_eip.nat_eip[i].id } if aws_subnet.public["${i}"].availability_zone == var.azs[i] }
}

resource "aws_nat_gateway" "this" {

  # Create a NAT gateway for each AZ or not
  for_each = var.create_public_nat_gateway ? local.availability_zone_public_subnet : {}

  # EIP assigned to the NAT gateway
  allocation_id = each.value.eip_id

  # subnet the NAT gateway should be placed in
  subnet_id     = each.value.subnet_id

  # Map of tags to assign to the resource.
  tags = merge(
    { "Name" = "${var.name}-Public NAT-${each.key}" },
    var.nat_gateway_tags,
    var.tags
  ) 
}
locals {
  # Map that contains AZ, cidr, nat gateway id and route table id for each private subnet
  # Modulo is used to make sure the loop doesn't go out of bounds and distribute the nat gateways and azs evenly among the subnets
  private_subnets = { for i in range(length(var.private_subnets)) : i => {
    az = var.azs[i % length(var.azs)]
    cidr = var.private_subnets[i]
    nat_gateway_id = aws_nat_gateway.this["${i % length(var.azs)}"].id
    route_table_id = aws_route_table.private["${i}"].id
  }}
  # 1st iteration:
  # az = "us-east-1a"
  # cidr = "10.0.101.0/24"
  # nat_gateway_id = aws_nat_gateway.this["0"].id
  # route_table_id = aws_route_table.private["0"].id

  # 2st iteration:
  # az = "us-east-1b"
  # cidr = "10.0.102.0/24"
  # nat_gateway_id = aws_nat_gateway.this["1"].id
  # route_table_id = aws_route_table.private["1"].id

  # 3rd iteration:
  # az = "us-east-1a"
  # cidr = "10.0.103.0/24"
  # nat_gateway_id = aws_nat_gateway.this["0"].id
  # route_table_id = aws_route_table.private["2"].id

  # 4th iteration:
  # az = "us-east-1b"
  # cidr = "10.0.104.0/24"
  # nat_gateway_id = aws_nat_gateway.this["1"].id
  # route_table_id = aws_route_table.private["3"].id
}


# Adds the natgateway route to each private route table in each AZ with their appropriate NAT gateway
resource "aws_route" "nat_gateway" {

  for_each = local.private_subnets

  route_table_id = each.value.route_table_id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = each.value.nat_gateway_id

}