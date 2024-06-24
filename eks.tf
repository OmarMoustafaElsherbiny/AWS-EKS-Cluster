# resource "aws_eks_cluster" "this" {
#   name = "${local.general_tags.env}-${local.eks_name}-eks"
# }




### IAM Roles that eks assumes to manage resources (nodes) on your behalf
## Policy that gives the action to assume the role for EKS service
resource "aws_iam_role" "eks" {
  name = "${local.general_tags.env}-${local.eks_name}-eks-cluster"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "eks.amazonaws.com"
      }
    }
  ]
}
POLICY
}

## Attaching managed EKSCluster Policy to the IAM role that will be assumed by the EKS service (control plane) to manage cluster
resource "aws_iam_role_policy_attachment" "eks" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role = aws_iam_role.eks.name
}

resource "aws_eks_cluster" "eks" {
  name = "${local.general_tags.env}-${local.eks_name}"
  version = local.eks_version
  role_arn = aws_iam_role.eks.arn

  vpc_config {
    endpoint_private_access = false
    endpoint_public_access = true
    subnet_ids = [
      module.two_tier_vpc.private_subnets["0"].id,
      module.two_tier_vpc.private_subnets["1"].id
    ]
  }

  access_config {
    authentication_mode = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [ aws_iam_role_policy_attachment.eks ]
}


##################### WORKER NODES #####################

# This allows (effect) EC2 service (Principal service) The action to assume the role (action)

resource "aws_iam_role" "nodes" {
  name = "${local.general_tags.env}-${local.eks_name}-eks-nodes"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      }
    }
  ]
}
POLICY  
}

# Now contains AssumeRoleForPodIdentity for the Pod Identity Agent
resource "aws_iam_role_policy_attachment" "amazon_eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role = aws_iam_role.nodes.name
}

resource "aws_iam_role_policy_attachment" "amazon_eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role = aws_iam_role.nodes.name
}

resource "aws_iam_role_policy_attachment" "amazon_ec2_container_registry_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role = aws_iam_role.nodes.name
}

# Behind the scenes its managed as an EC2 autoscaler group

resource "aws_eks_node_group" "general" {
  cluster_name = aws_eks_cluster.eks.name
  version = local.eks_version
  node_group_name = "general"
  node_role_arn = aws_iam_role.nodes.arn

  subnet_ids = [
    module.two_tier_vpc.private_subnets["0"].id,
    module.two_tier_vpc.private_subnets["1"].id
  ]
  capacity_type = "ON_DEMAND"
  instance_types = [ "t3.large" ]

  scaling_config {
    desired_size = 1
    max_size = 3
    min_size = 0
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    role = "general"
  }

  depends_on = [ 
    aws_iam_role_policy_attachment.amazon_eks_worker_node_policy,
    aws_iam_role_policy_attachment.amazon_eks_cni_policy,
    aws_iam_role_policy_attachment.amazon_ec2_container_registry_read_only 
  ]

  # Allow external changes without terraform plan difference
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}