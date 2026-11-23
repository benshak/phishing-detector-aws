# ElastiCache (Redis): a shared in-memory cache in front of RDS (assignment bonus).
# The app keeps the history table here, so most page views never touch the database.
# The app works without it: if Redis is down, db.py reads straight from RDS.

# Redis port 6379 only from the app servers, the same chain of trust as RDS.
resource "aws_security_group" "cache" {
  name        = "${var.project_name}-cache-sg"
  description = "Allow Redis only from the app servers"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Redis from the app servers only"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  tags = { Name = "${var.project_name}-cache-sg" }
}

# Which subnets the cache may live in: the private ones, like RDS (no internet access).
resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.project_name}-cache-subnets"
  subnet_ids = aws_subnet.private[*].id
}

# One small Redis node. Both servers connect to it, so they share one cache.
resource "aws_elasticache_cluster" "main" {
  cluster_id           = "${var.project_name}-cache"
  engine               = "redis"
  engine_version       = "7.1"
  parameter_group_name = "default.redis7"
  node_type            = var.cache_node_type
  num_cache_nodes      = 1
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.cache.id]

  # A cache holds copies only; nothing to back up.
  snapshot_retention_limit = 0

  tags = { Name = "${var.project_name}-cache" }
}
