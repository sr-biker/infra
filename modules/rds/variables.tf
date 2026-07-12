variable "name" {
  type    = string
  default = "infra-prod-rds"
}

variable "vpc_id" {
  type        = string
  description = "VPC to deploy RDS into -- the k8s stack's VPC, not a separate one. No VPC peering/cross-VPC routing needed this way."
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnets (within vpc_id) for the DB subnet group."
}

variable "node_security_group_id" {
  type        = string
  description = "k8s node security group -- the only thing allowed to reach RDS on 5432."
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

variable "master_secret_name" {
  type        = string
  default     = "/rds/postgres/credentials"
  description = "Existing Secrets Manager secret (username+password JSON) used as the master credential, instead of letting RDS generate/manage its own. Ported from the source CDK stack's secret of the same name/shape."
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
