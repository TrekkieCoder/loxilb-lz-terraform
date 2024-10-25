# IAM role for eks

resource "aws_iam_role" "demo" {
  name = "eks-cluster-demo1"
  tags = {
    tag-key = "eks-cluster-demo1"
  }

  assume_role_policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": [
                    "eks.amazonaws.com"
                ]
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
POLICY
}

# eks policy attachment

resource "aws_iam_role_policy_attachment" "demo-AmazonEKSClusterPolicy" {
  role       = aws_iam_role.demo.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# bare minimum requirement of eks
/*
resource "aws_eks_cluster" "demo" {
  name     = "demo"
  role_arn = aws_iam_role.demo.arn

  vpc_config {
    subnet_ids = [
      aws_subnet.private-us-east-1a.id,
      aws_subnet.private-us-east-1b.id,
      aws_subnet.public-us-east-1a.id,
      aws_subnet.public-us-east-1b.id
      #aws_subnet.public-us-east-1-atl-2a.id,
      #aws_subnet.private-us-east-1-atl-2a.id,
    ]
  }

  depends_on = [aws_iam_role_policy_attachment.demo-AmazonEKSClusterPolicy]
}
*/

module "eks_blueprints" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints?ref=v4.32.1"

  #   tenant      = local.tenant
  #   environment = local.environment
  #   zone        = local.zone

  cluster_name = "demo1"

  # EKS Cluster VPC and Subnet mandatory config
  vpc_id             = aws_vpc.k8svpc.id
  private_subnet_ids = [ aws_subnet.private-us-east-1a.id,
 												 aws_subnet.private-us-east-1b.id
											 ]

  public_subnet_ids = [ aws_subnet.public-us-east-1a.id,
  											 aws_subnet.public-us-east-1b.id
										 ]


  # EKS CONTROL PLANE VARIABLES
  cluster_version = "1.31"

  # EKS Managed Nodes in AZ
  managed_node_groups = {
    mg_5 = {
      node_group_name = "managed-ondemand"
      instance_types  = ["t3.medium"]
      min_size        = 1
      max_size        = 1
      desired_size    = 1
      subnet_ids      = [ aws_subnet.private-us-east-1a.id,
                          aws_subnet.private-us-east-1b.id,
                          aws_subnet.public-us-east-1b.id   
                        ]
    }
  }

  # EKS LOCAL ZONE NODE GROUP
  self_managed_node_groups = {
    self_mg_loxilb = {
      node_group_name    = "self-managed-ondemand"
      instance_type      = "c6i.large"
      capacity_type      = ""                # Optional Use this only for SPOT capacity as capacity_type = "spot"
      launch_template_os = "amazonlinux2eks" # amazonlinux2eks  or bottlerocket or windows
      # launch_template_os = "bottlerocket" # amazonlinux2eks  or bottlerocket or windows
      block_device_mappings = [
        {
          device_name = "/dev/xvda"
          volume_type = "gp2"
          volume_size = "20"
        },
      ]
      enable_monitoring = false
      # AUTOSCALING
      max_size = "2"
      # EFS CSI Drvier required two nodes so that installing helm chart will not stuck
      min_size = "2"

      subnet_ids = [#aws_subnet.public-us-east-1-atl-2a.id,
										aws_subnet.private-us-east-1-atl-2a.id
                   ]
    },
  }

  cluster_security_group_additional_rules = {
      ingress_nodes = {
      description                = "Allow all connections from nodes"
      protocol                   = "-1"
      from_port                  = 0
      to_port                    = 0
      type                       = "ingress"
      source_node_security_group = true
    }
  }

  #----------------------------------------------------------------------------------------------------------#
  # Securaity groups used in this module created by the upstream modules terraform-aws-eks (https://github.com/terraform-aws-modules/terraform-aws-eks).
  #   Upstrem module implemented Security groups based on the best practices doc https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html.
  #   So, by default the security groups are restrictive. Users needs to enable rules for specific ports required for App requirement or Add-ons
  #   See the notes below for each rule used in these examples
  #----------------------------------------------------------------------------------------------------------#
  node_security_group_additional_rules = {
    # Extend node-to-node security group rules. Recommended and required for the Add-ons
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    # Recommended outbound traffic for Node groups
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
    # Allows Control Plane Nodes to talk to Worker nodes on all ports. Added this to simplify the example and further avoid issues with Add-ons communication with Control plane.
    # This can be restricted further to specific port based on the requirement for each Add-on e.g., metrics-server 4443, spark-operator 8080, karpenter 8443 etc.
    # Change this according to your security requirements if needed
    ingress_cluster_to_node_all_traffic = {
      description                   = "Cluster API to Nodegroup all traffic"
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }
}

output "eks_endpoint" {
	value = module.eks_blueprints.eks_cluster_endpoint
  #value = aws_eks_cluster.demo.endpoint
}

output "eks_ca_cert" {
  value = module.eks_blueprints.eks_cluster_certificate_authority_data
}

provider "kubernetes" {
  host                   = module.eks_blueprints.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_blueprints.eks_cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks_blueprints.eks_cluster_id]
  }

}

resource "null_resource" "kubeconfig" {
  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --region us-east-1 --name ${module.eks_blueprints.eks_cluster_id}"
  }

  depends_on = [
    module.eks_blueprints
  ]
}
