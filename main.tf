terraform {
  required_version = ">= 1.5.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.55"
    }
  }
}

locals {  
  region = "us-east-1"
  zone1 = "us-east-1a"
  zone2 = "us-east-1b"
  eks_name = "my-eks-cluster"
  eks_version = "1.29"

  public_subnets_eks_tags = {
    "kubernetes.io/role/elb" = "1"
    "kubernetes.io/cluster/${local.general_tags["env"]}-${local.eks_name}" = "owned"
  }

  private_subnet_eks_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    "kubernetes.io/cluster/${local.general_tags["env"]}-${local.eks_name}" = "owned"
  }

  general_tags = {
    Project     = "EKS cluster"
    env = "staging"
    ManagedBy   = "Terraform"
  }
}

provider "aws" {
  region = local.region 
}

module "two_tier_vpc" {
  source = "./modules/vpc"

  name = "my-vpc"
  cidr = "10.0.0.0/16"

  azs             = [local.zone1, local.zone2]
  public_subnets = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnets = ["10.0.101.0/24", "10.0.102.0/24"]

  public_subnet_map_public_ip_on_launch = true

  create_public_nat_gateway = true

  tags = local.general_tags

  private_subnet_tags = local.private_subnet_eks_tags

  public_subnet_tags = local.public_subnets_eks_tags
}

module "eks_cluster" {
  source = "./modules/eks"

  name = "${local.general_tags["env"]}-${local.eks_name}"
  k8s_version = local.eks_version

  eks_cluster_subnets_id = [
    module.two_tier_vpc.private_subnets["0"].id,
    module.two_tier_vpc.private_subnets["1"].id
  ]
}