variable "k8s_version" {
  type = string
  description = "Kubernetes version"
  default = "1.21"
}

variable "name" {
  type = string
  description = "Name to be used on all EKS resources as identifier"
  default = ""
}

variable "eks_cluster_subnets_id" {
  type = list(string)
  description = "List of subnets ids for the EKS cluster"
  default = []
}