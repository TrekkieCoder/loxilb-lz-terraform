data "tls_certificate" "eks" {
  #url = aws_eks_cluster.demo.identity[0].oidc[0].issuer
  url = "https://${module.eks_blueprints.eks_oidc_issuer_url}"
}

data "aws_iam_openid_connect_provider" "eks" {
  url             = "https://${module.eks_blueprints.eks_oidc_issuer_url}"
}
