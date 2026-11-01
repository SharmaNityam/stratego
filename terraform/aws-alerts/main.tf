terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}
provider "aws" { region = "ap-southeast-2" }
resource "aws_sns_topic" "alerts" {
  name = "stratego-alerts"
  tags = { Project = "stratego" }
}
resource "aws_iam_role" "publisher" {
  name = "stratego-alert-publisher"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}
resource "aws_iam_role_policy" "publish" {
  name = "stratego-sns-publish"
  role = aws_iam_role.publisher.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sns:Publish", Resource = aws_sns_topic.alerts.arn }]
  })
}
resource "aws_iam_instance_profile" "publisher" {
  name = "stratego-alert-publisher"
  role = aws_iam_role.publisher.name
}
