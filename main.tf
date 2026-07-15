terraform {
   required_providers {
       aws = {
            source  = "hashicorp/aws"
            version = "~>5.0"
          }
        }
}

provider "aws" {
    region = "eu-west-3" 
  }


data "aws_ami" "amazon_linux" {
       most_recent = true
       owners      = ["amazon"]
       
       filter {
         name  = "name"
         values = ["al2023-ami-2023.*-x86_64"]
      }
      filter {
          name   = "virtualization-type"
          values = ["hvm"]
  }  
}


#creation de l'instance EC2


resource "aws_vpc" "vpc_projet" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames  =  true
  
  tags = {
   Name = "VPC-monprojet-Devops"
  }
}


resource "aws_subnet" "subnet_public" {
   vpc_id                 = aws_vpc.vpc_projet.id 
   cidr_block             = "10.0.1.0/24"
   map_public_ip_on_launch = false
 
   tags = {
    Name = "subnet-public-projet"
  }
}


data "aws_iam_policy_document" "mon_serveur_assume_role" {
  version = "2012-10-17"

  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "mon_role" {
    name		   = "mon_serveur_role"
    assume_role_policy     = data.aws_iam_policy_document.mon_serveur_assume_role.json
  
}

resource "aws_iam_role_policy_attachment" "attachement_s3" {
  role       = aws_iam_role.mon_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_iam_instance_profile" "mon_profil" {
  name = "mon_serveur_profile"
  role = aws_iam_role.mon_role.name
}


resource "aws_instance" "mon_premier_serveur" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.tailles_instance

  # On ajoute la liaison indispensable ici :
  subnet_id     = aws_subnet.subnet_public.id

  ebs_optimized = true

  metadata_options {
     http_tokens  = "required"
    }
  iam_instance_profile = aws_iam_instance_profile.mon_profil.name
  root_block_device {
     encrypted = true
  }
  monitoring     = true
  tags = {
    Name = "serveur-terraform-Test"
  }
}

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.vpc_projet.id

 
  ingress = []
  egress  = []
}
# Création du groupe de log
resource "aws_kms_key" "logs_key" {
  description             = "Clé pour chiffrer les logs CloudWatch"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}
resource "aws_cloudwatch_log_group" "vpc_logs" {
  name              = "/aws/vpc/projet-flow-logs"
  retention_in_days = 365            # Correction CKV_AWS_338 et CKV_AWS_66 (1 an)
 # kms_key_id        = aws_kms_key.logs_key.arn           # Utilise le chiffrement AWS par défaut (ou ta propre clé KMS)
}

# Activation du Flow Log sur ton VPC
resource "aws_flow_log" "vpc_flow_log" {
  iam_role_arn    = aws_iam_role.mon_role.arn # On réutilise ton rôle IAM existant
  log_destination = aws_cloudwatch_log_group.vpc_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.vpc_projet.id
}
