################################################################################
# Developer User and Policy that is linked to my-viewer group in the EKS cluster
################################################################################
resource "aws_iam_user" "developer" {
  name = "developer"
}

# The IAM User that will be binded to my-viewer group in the EKS cluster that has viewer role permission
resource "aws_iam_policy" "developer_eks" {
  name = "AmazonEKSDeveloperPolicy"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster",
        "eks:ListClusters"
      ],
      "Resource": "*"
    }
  ]
}
POLICY
}

resource "aws_iam_user_policy_attachment" "developer_eks" {
  policy_arn = aws_iam_policy.developer_eks.arn
  user = aws_iam_user.developer.name
}

resource "aws_eks_access_entry" "developer" {
  cluster_name = aws_eks_cluster.eks.name
  principal_arn = aws_iam_user.developer.arn
  # The name of the group that the role was bound to in the k8s cluster
  kubernetes_groups = ["my-viewer"]
}


################################################################################
# EKS Admin Role and Policy (This role will be assumed by the manager user as an example)
################################################################################
data "aws_caller_identity" "current" {}


resource "aws_iam_role" "eks_admin" {
  name = "${local.general_tags.env}-${local.eks_name}-eks-admin"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Principal": {
      "AWS": "arn:aws: iam::${data.aws_caller_identity.current.account_id}:root"
      }
    }
  ]
}
POLICY
}

resource "aws_iam_policy" "eks_admin" {
  name = "AmazonEKSAdminPolicy"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "eks:*"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "iam:PassRole"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": "eks.amazonaws.com"
        }
      }
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "eks_admin" {
  policy_arn = aws_iam_policy.eks_admin.arn
  role = aws_iam_role.eks_admin.name
}

################################################################################
# IAM manager User and Policy (This role will be assumed by the manager user as an example)
################################################################################

resource "aws_iam_user" "manager" {
  name = "manager"
}

resource "aws_iam_policy" "manager" {
  name = "AmazonEKSAssumeAdminPolicy"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "${aws_iam_role.eks_admin.arn}"
    }
  ]
}
POLICY
}

resource "aws_iam_user_policy_attachment" "manager" {
  policy_arn = aws_iam_policy.manager.arn
  user = aws_iam_user.manager.name
}

# Best practice: use IAM roles due to temporary credentials
resource "aws_eks_access_entry" "manager" {
  cluster_name = aws_eks_cluster.eks.name
  principal_arn = aws_iam_role.eks_admin.arn
  kubernetes_groups = ["my-admin"]
  
}