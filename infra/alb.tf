# Application Load Balancer: one public address that spreads requests across both servers
# and stops sending traffic to a server that fails its health check.

resource "aws_lb" "app" {
  name               = "${var.project_name}-alb"
  load_balancer_type = "application"
  internal           = false # internet-facing
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = { Name = "${var.project_name}-alb" }
}

# The group of servers the ALB forwards to, and how it checks they are alive.
resource "aws_lb_target_group" "app" {
  name     = "${var.project_name}-tg"
  port     = 8000
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/health" # the endpoint in app.py that returns "ok"
    matcher             = "200"
    interval            = 15 # seconds between checks
    timeout             = 5
    healthy_threshold   = 2 # 2 passes in a row -> healthy
    unhealthy_threshold = 2 # 2 failures in a row -> stop sending traffic
  }

  # Wait only 30s for open requests when a server leaves (faster destroy).
  deregistration_delay = 30
}

# Put both servers into the target group.
resource "aws_lb_target_group_attachment" "app" {
  count            = 2
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.app[count.index].id
  port             = 8000
}

# Listen on port 80 and forward everything to the target group.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
