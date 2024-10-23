# Configure the AWS Provider

locals {
  eks_loxilb_arn = "arn:aws:iam::829322364554:role/eks-loxilb"
  new_role_yaml = <<-EOF
    - groups:
      - system:masters
      rolearn: "arn:aws:iam::829322364554:role/eks-loxilb"
      username: loxilb
    EOF
}

#provider "aws" {
#  region = var.region
#}

data "aws_eks_cluster" "this" {
  name = "demo"
}

data "aws_eks_cluster_auth" "this" {
  name = "demo"
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

resource "kubernetes_service_account" "loxilb" {
  metadata {
    name      = "loxilb"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.eks_loxilb.arn
    }
  }
}

resource "kubernetes_cluster_role" "loxilb" {
  metadata {
    name = "loxilb"
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["*"]
  }
}

resource "kubernetes_cluster_role_binding" "loxilb" {
  metadata {
    name = "loxilb"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "loxilb"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "loxilb"
    namespace = "kube-system"
  }
}

data "kubernetes_config_map" "aws_auth" {
  metadata {
    name = "aws-auth"
    namespace = "kube-system"
  }
}

resource "kubernetes_config_map_v1_data" "aws_auth" {
  force = true

  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    # Convert to list, make distinict to remove duplicates, and convert to yaml as mapRoles is a yaml string.
    # replace() remove double quotes on "strings" in yaml output.
    # distinct() only apply the change once, not append every run.
    mapRoles = replace(yamlencode(distinct(concat(yamldecode(data.kubernetes_config_map.aws_auth.data.mapRoles), yamldecode(local.new_role_yaml)))), "\"", "")
  }

  lifecycle {
    ignore_changes = []
    //prevent_destroy = true
  }
}
