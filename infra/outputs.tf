# Printed at the end of "terraform apply" (and any time with "terraform output").

output "app_url" {
  description = "Open this in the browser (give it 3-5 minutes after apply)"
  value       = "http://${aws_lb.app.dns_name}"
}

output "instance_ids" {
  description = "The two app servers"
  value       = aws_instance.app[*].id
}

output "rds_endpoint" {
  description = "Database address (reachable only from inside the VPC)"
  value       = aws_db_instance.main.address
}

output "redis_endpoint" {
  description = "Cache address (reachable only from inside the VPC)"
  value       = aws_elasticache_cluster.main.cache_nodes[0].address
}

output "log_group" {
  description = "CloudWatch log group with the app logs"
  value       = aws_cloudwatch_log_group.app.name
}

output "dashboard_url" {
  description = "CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards/dashboard/${aws_cloudwatch_dashboard.main.dashboard_name}"
}
