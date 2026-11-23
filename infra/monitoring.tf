# CloudWatch: logs, a custom metric from the logs, alarms and one dashboard.

# Where both servers' app logs land (one stream per instance).
resource "aws_cloudwatch_log_group" "app" {
  name              = local.log_group_name
  retention_in_days = 7
}

# Turn log lines into a number: every "verdict=phishing" line in app.py's log adds 1.
resource "aws_cloudwatch_log_metric_filter" "phishing_detected" {
  name           = "${var.project_name}-phishing-detected"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "\"verdict=phishing\""

  metric_transformation {
    name          = "PhishingDetected"
    namespace     = "PhishingDetector"
    value         = "1"
    default_value = "0"
  }
}

# ---------- Alarms (state is visible in the CloudWatch console) ----------

# A server failed its health check for 2 minutes in a row.
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.project_name}-unhealthy-hosts"
  alarm_description   = "At least one app server is failing the ALB health check"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
    TargetGroup  = aws_lb_target_group.app.arn_suffix
  }
}

# The app returned more than 5 server errors (HTTP 5xx) in 5 minutes.
resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  alarm_name          = "${var.project_name}-5xx-errors"
  alarm_description   = "The app is returning server errors"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
  }
}

# Many phishing emails in a short time may mean an active campaign.
resource "aws_cloudwatch_metric_alarm" "phishing_spike" {
  alarm_name          = "${var.project_name}-phishing-spike"
  alarm_description   = "5 or more phishing emails detected within 5 minutes"
  namespace           = "PhishingDetector"
  metric_name         = "PhishingDetected"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
}

# The database is working too hard.
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.project_name}-rds-cpu-high"
  alarm_description   = "RDS CPU above 80% for 10 minutes"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }
}

# ---------- Dashboard: the whole system on one screen ----------

locals {
  # Helper to keep each graph definition short.
  widget = {
    type   = "metric"
    width  = 12
    height = 6
  }
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = var.project_name

  dashboard_body = jsonencode({
    widgets = [
      merge(local.widget, { x = 0, y = 0, properties = {
        title   = "ALB requests per minute"
        region  = var.aws_region
        stat    = "Sum"
        period  = 60
        metrics = [["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.app.arn_suffix]]
      } }),
      merge(local.widget, { x = 12, y = 0, properties = {
        title  = "Healthy vs unhealthy servers"
        region = var.aws_region
        stat   = "Maximum"
        period = 60
        metrics = [
          ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", aws_lb_target_group.app.arn_suffix, "LoadBalancer", aws_lb.app.arn_suffix],
          ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", aws_lb_target_group.app.arn_suffix, "LoadBalancer", aws_lb.app.arn_suffix],
        ]
      } }),
      merge(local.widget, { x = 0, y = 6, properties = {
        title   = "Phishing emails detected"
        region  = var.aws_region
        stat    = "Sum"
        period  = 300
        metrics = [["PhishingDetector", "PhishingDetected"]]
      } }),
      merge(local.widget, { x = 12, y = 6, properties = {
        title  = "CPU: app servers and database"
        region = var.aws_region
        stat   = "Average"
        period = 300
        metrics = concat(
          [for i in aws_instance.app : ["AWS/EC2", "CPUUtilization", "InstanceId", i.id]],
          [["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.main.identifier]]
        )
      } }),
      # Which requests succeeded and which failed, and whose fault a failure was:
      # Target 4XX/5XX = our app answered with an error, ELB 5XX = the ALB could not reach a healthy server.
      merge(local.widget, { x = 0, y = 12, properties = {
        title  = "Requests: success vs errors"
        region = var.aws_region
        stat   = "Sum"
        period = 60
        metrics = [
          ["AWS/ApplicationELB", "HTTPCode_Target_2XX_Count", "LoadBalancer", aws_lb.app.arn_suffix, { label = "2XX success", color = "#2ca02c" }],
          ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", aws_lb.app.arn_suffix, { label = "4XX client error", color = "#ff7f0e" }],
          ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_lb.app.arn_suffix, { label = "5XX app error", color = "#d62728" }],
          ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", aws_lb.app.arn_suffix, { label = "5XX from ALB (no healthy server)", color = "#9467bd" }],
        ]
      } }),
      # Memory and disk come from the CloudWatch agent (namespace CWAgent), one line per server.
      merge(local.widget, { x = 12, y = 12, properties = {
        title  = "Memory and disk used % (per server)"
        region = var.aws_region
        period = 300
        metrics = [
          [{ expression = "SEARCH('{CWAgent,InstanceId} MetricName=\"mem_used_percent\"', 'Average', 300)", id = "mem", label = "Memory" }],
          [{ expression = "SEARCH('{CWAgent,InstanceId,fstype,path} MetricName=\"disk_used_percent\"', 'Average', 300)", id = "disk", label = "Disk /" }],
        ]
      } }),
      # ElastiCache reports hits and misses by itself (namespace AWS/ElastiCache), no app code needed.
      # Redis reports per node; our single node is always "0001".
      # Hit = page served from the cache; miss = had to ask the database (first view, or right after a new check).
      merge(local.widget, { x = 0, y = 18, width = 24, properties = {
        title  = "Cache hits vs misses (ElastiCache)"
        region = var.aws_region
        stat   = "Sum"
        period = 60
        metrics = [
          ["AWS/ElastiCache", "CacheHits", "CacheClusterId", aws_elasticache_cluster.main.cluster_id, "CacheNodeId", "0001", { label = "Hits (served from cache)", color = "#2ca02c" }],
          ["AWS/ElastiCache", "CacheMisses", "CacheClusterId", aws_elasticache_cluster.main.cluster_id, "CacheNodeId", "0001", { label = "Misses (went to the database)", color = "#ff7f0e" }],
        ]
      } }),
    ]
  })
}
