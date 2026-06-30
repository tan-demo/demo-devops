variable "name" {
  type        = string
  description = "Name prefix applied to the VPC and every child resource."
}

variable "cidr" {
  type        = string
  description = "IPv4 CIDR block for the VPC."
  default     = "10.100.0.0/16"
}

variable "azs" {
  type        = list(string)
  description = "Availability zones to spread subnets across (one private + one public per AZ)."
}

variable "subnet_newbits" {
  type        = number
  description = "Bits added to the VPC prefix when carving each subnet via cidrsubnet()."
  default     = 8
}

variable "public_subnet_offset" {
  type        = number
  description = "Netnum offset for public subnets so they never overlap the private range."
  default     = 128
}

variable "enable_nat_gateway" {
  type    = bool
  default = true
}

variable "single_nat_gateway" {
  type        = bool
  description = "Share one NAT gateway across all AZs (cheaper, non-HA). Disable for prod."
  default     = true
}

variable "one_nat_gateway_per_az" {
  type    = bool
  default = false
}

variable "enable_database_subnets" {
  type        = bool
  description = "Carve a dedicated database subnet tier (one per AZ)."
  default     = false
}

variable "database_subnet_offset" {
  type        = number
  description = "Netnum offset for database subnets so they sit in their own range."
  default     = 64
}

variable "create_database_subnet_group" {
  type    = bool
  default = true
}

variable "create_database_subnet_route_table" {
  type    = bool
  default = true
}

variable "database_subnet_tags" {
  type    = map(string)
  default = {}
}

variable "enable_dns_hostnames" {
  type    = bool
  default = true
}

variable "enable_dns_support" {
  type    = bool
  default = true
}

variable "map_public_ip_on_launch" {
  type    = bool
  default = false
}

variable "create_igw" {
  type    = bool
  default = true
}

variable "instance_tenancy" {
  type    = string
  default = "default"
}

variable "private_subnet_tags" {
  type        = map(string)
  description = "Extra tags for private subnets (e.g. Karpenter/internal-ELB discovery)."
  default     = {}
}

variable "public_subnet_tags" {
  type    = map(string)
  default = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
