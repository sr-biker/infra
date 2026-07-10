variable "name" {
  type    = string
  default = "infra-prod-rds"
}

variable "vpc_cidr" {
  type    = string
  default = "10.1.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.1.0.0/24", "10.1.1.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "Private-with-egress tier; unused (no NAT gateway is created, matching the source CDK stack's nat_gateways=0), kept for topology parity."
  default     = ["10.1.10.0/24", "10.1.11.0/24"]
}

variable "isolated_subnet_cidrs" {
  type        = list(string)
  description = "Isolated tier the RDS instance actually runs in."
  default     = ["10.1.20.0/28", "10.1.20.16/28"]
}

variable "instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "engine_version" {
  type    = string
  default = "17"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "max_allocated_storage" {
  type    = number
  default = 100
}

variable "database_name" {
  type    = string
  default = "appdb"
}

variable "master_username" {
  type    = string
  default = "dbadmin"
}

variable "monitoring_interval" {
  type    = number
  default = 15
}

variable "stop_schedule_expression" {
  type        = string
  description = "Stop the DB on this schedule (default: 11pm ET / 04:00 UTC, Tue-Sat, i.e. after Mon-Fri nights)."
  default     = "cron(0 4 ? * TUE-SAT *)"
}

variable "start_schedule_expression" {
  type        = string
  description = "Start the DB on this schedule (default: 8am ET / 13:00 UTC, weekdays)."
  default     = "cron(0 13 ? * MON-FRI *)"
}
