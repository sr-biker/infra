output "alb_arn" {
  value = module.alb.alb_arn
}

output "alb_dns_name" {
  value = module.alb.alb_dns_name
}

output "listener_arn" {
  value = module.alb.listener_arn
}

output "alb_security_group_id" {
  value = module.alb.alb_security_group_id
}
