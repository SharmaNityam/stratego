terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" { region = var.aws_region }

data "aws_vpc" "default" { default = true }
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}
resource "aws_key_pair" "stratego" {
  key_name_prefix = "stratego-ha-"
  public_key      = file(var.public_key_path)
}
resource "aws_security_group" "nodes" {
  name_prefix = "stratego-ha-nodes-"
  vpc_id      = data.aws_vpc.default.id
  description = "Stratego cluster nodes"
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.admin_cidrs
  }
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }
  ingress {
    from_port       = 30080
    to_port         = 30080
    protocol        = "tcp"
    security_groups = [aws_security_group.load_balancer.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_security_group" "load_balancer" {
  name_prefix = "stratego-ha-lb-"
  vpc_id      = data.aws_vpc.default.id
  description = "Restrict the demo application to the operator"
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.admin_cidrs
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_instance" "nodes" {
  count                       = 3
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = sort(data.aws_subnets.default.ids)[count.index]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.stratego.key_name
  vpc_security_group_ids      = [aws_security_group.nodes.id]
  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }
  metadata_options { http_tokens = "required" }
  tags = { Name = "stratego-ha-${count.index + 1}", Project = "stratego" }
}
resource "aws_lb" "stratego" {
  name               = "stratego-ha"
  load_balancer_type = "network"
  subnets            = sort(data.aws_subnets.default.ids)
  security_groups    = [aws_security_group.load_balancer.id]
  tags               = { Project = "stratego" }
}
resource "aws_lb_target_group" "stratego" {
  name_prefix = "strat-"
  port        = 30080
  protocol    = "TCP"
  vpc_id      = data.aws_vpc.default.id
  health_check {
    protocol = "HTTP"
    path     = "/healthz"
    port     = "30080"
  }
}
resource "aws_lb_target_group_attachment" "nodes" {
  count            = 3
  target_group_arn = aws_lb_target_group.stratego.arn
  target_id        = aws_instance.nodes[count.index].id
  port             = 30080
}
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.stratego.arn
  port              = 80
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.stratego.arn
  }
}
output "nodes" {
  value = [for node in aws_instance.nodes : { id = node.id, public_ip = node.public_ip, private_ip = node.private_ip, zone = node.availability_zone }]
}
output "load_balancer_dns" { value = aws_lb.stratego.dns_name }
output "target_group_arn" { value = aws_lb_target_group.stratego.arn }
