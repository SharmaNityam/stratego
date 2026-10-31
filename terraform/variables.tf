variable "aws_region" {
  type    = string
  default = "ap-south-1"
}
variable "instance_type" {
  type    = string
  default = "t3.medium"
}
variable "key_name" {
  type        = string
  description = "Existing EC2 key pair name"
}
variable "admin_cidr" {
  type        = string
  description = "Your public IP in CIDR notation, e.g. 203.0.113.10/32"
}
