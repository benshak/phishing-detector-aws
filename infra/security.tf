# Security groups: a chain of trust.
#   Internet --80--> ALB --8000--> EC2 --5432--> RDS
# Each layer accepts traffic only from the layer before it.

# ALB: the only thing open to the internet, and only on HTTP port 80.
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Allow HTTP from the internet to the load balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Forward to the app servers"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-alb-sg" }
}

# EC2: app port 8000 only from the ALB's security group. No SSH (port 22);
# we connect with SSM Session Manager instead.
resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "Allow app traffic only from the load balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Gunicorn from the ALB only"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Outbound: install packages, reach RDS, CloudWatch and SSM"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-app-sg" }
}

# RDS: PostgreSQL port 5432 only from the app servers' security group.
resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "Allow PostgreSQL only from the app servers"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from the app servers only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  tags = { Name = "${var.project_name}-db-sg" }
}
