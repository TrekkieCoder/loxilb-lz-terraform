# Configure the AWS Provider
locals {
  eks_loxilb_demo_arn = "arn:aws:iam::829322364554:role/eks-loxilb"
  new_role_yaml = <<-EOF
    - groups:
      - system:masters
      rolearn: "arn:aws:iam::829322364554:role/eks-loxilb"
      username: loxilb
    EOF
}

data "aws_eks_cluster_auth" "demo" {
  name = "demo"
}

resource "kubernetes_service_account" "loxilb" {
  metadata {
    name      = "loxilb"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = local.eks_loxilb_demo_arn
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

 depends_on = [
    #aws_eks_cluster.demo,
 ]
}

resource "null_resource" "wait_cluster" {
  provisioner "local-exec" {
    command = "sleep 20"
  }

  depends_on = [
    #module.eks_blueprints.module.aws_eks.aws_eks_cluster.this[0]
    #aws_eks_node_group.lz-worker-nodes
  ]
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

  depends_on = [
    null_resource.wait_cluster,
  ]
}

resource "null_resource" "post-kubeconfig" {
  #provisioner "local-exec" {
  #  command = "aws eks update-kubeconfig --region us-east-1 --name ${module.eks_blueprints.eks_cluster_name}"
  #}

  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --region us-east-1 --name demo1 --kubeconfig kubeconfig"
  }

  provisioner "local-exec" {
    command = "kubectl create configmap kubeconfig --from-file=kubeconfig -n kube-system"
  }

  depends_on = [
    module.eks_blueprints
  ]
}
