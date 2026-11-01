variable "aws_region" {
  type    = string
  default = "ap-southeast-2"
}
variable "instance_type" {
  type    = string
  default = "t3.small"
}
variable "admin_cidrs" {
  type        = list(string)
  description = "Operator public IPv4 addresses in CIDR form"
}
variable "public_key_path" {
  type        = string
  description = "Path to the operator SSH public key"
}
