variable "name" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "alb_security_group_id" {
  type = string
}

variable "alb_listener_arn" {
  type = string
}

variable "stage_name" {
  type    = string
  default = "$default"
}
