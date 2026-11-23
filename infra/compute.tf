# Two EC2 app servers, one in each zone, set up automatically on first boot.

# Latest Amazon Linux 2023 image, looked up from AWS's public SSM parameter.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
}

# ---------- IAM: what the servers themselves are allowed to do ----------

# Lets EC2 "wear" this role.
resource "aws_iam_role" "app" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Send logs to CloudWatch.
resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Open a shell on the server from the AWS console (Session Manager), without SSH.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# The "badge holder" that attaches the role to an instance.
resource "aws_iam_instance_profile" "app" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.app.name
}

# ---------- User data: everything the server needs on first boot ----------

locals {
  # App files copied onto each server (tests and samples are not needed there).
  app_files = ["app.py", "db.py", "cache.py", "detector.py", "templates/index.html", "requirements.txt"]

  log_group_name = "/${var.project_name}/app"
}

# cloud-init runs on first boot: it writes the files, then runs setup.sh.
# gzip keeps it under the 16 KB user data limit.
data "cloudinit_config" "app" {
  gzip          = true
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content = yamlencode({
      write_files = concat(
        # The application code, read from ../app on your computer.
        [for f in local.app_files : {
          path    = "/opt/phishing/${f}"
          content = replace(file("${path.module}/../app/${f}"), "\r\n", "\n")
        }],
        [
          # Database and cache settings that db.py and cache.py read. 0600 = only root can read (holds the password).
          {
            path        = "/etc/phishing/app.env"
            permissions = "0600"
            content = join("\n", [
              "DB_HOST=${aws_db_instance.main.address}",
              "DB_PORT=${aws_db_instance.main.port}",
              "DB_NAME=${var.db_name}",
              "DB_USER=${var.db_username}",
              "DB_PASSWORD=${var.db_password}",
              "REDIS_HOST=${aws_elasticache_cluster.main.cache_nodes[0].address}",
              "REDIS_PORT=${aws_elasticache_cluster.main.port}",
              "",
            ])
          },
          # systemd service: runs gunicorn and restarts it if it crashes.
          {
            path    = "/etc/systemd/system/phishing.service"
            content = replace(file("${path.module}/templates/phishing.service"), "\r\n", "\n")
          },
          # CloudWatch agent: ship the app log file to a log group (one stream per server),
          # and report memory and disk usage, which EC2 cannot see from outside the server.
          {
            path = "/opt/aws/amazon-cloudwatch-agent/etc/config.json"
            content = jsonencode({
              metrics = {
                namespace         = "CWAgent"
                append_dimensions = { InstanceId = "$${aws:InstanceId}" }
                metrics_collected = {
                  mem = {
                    measurement                 = ["mem_used_percent"]
                    metrics_collection_interval = 60
                  }
                  disk = {
                    measurement                 = ["used_percent"]
                    resources                   = ["/"]
                    drop_device                 = true
                    metrics_collection_interval = 60
                  }
                }
              }
              logs = {
                logs_collected = {
                  files = {
                    collect_list = [{
                      file_path       = "/var/log/phishing/app.log"
                      log_group_name  = local.log_group_name
                      log_stream_name = "{instance_id}"
                    }]
                  }
                }
              }
            })
          },
        ]
      )
    })
  }

  part {
    content_type = "text/x-shellscript"
    content      = replace(file("${path.module}/templates/setup.sh"), "\r\n", "\n")
  }
}

# ---------- The two servers ----------

resource "aws_instance" "app" {
  count                  = 2
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[count.index].id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.app.name

  user_data_base64 = data.cloudinit_config.app.rendered
  # Changed app code or settings -> build fresh servers instead of keeping stale ones.
  user_data_replace_on_change = true

  # IMDSv2 only: protects the server's temporary AWS credentials from SSRF tricks.
  metadata_options {
    http_tokens = "required"
  }

  # The log group must exist before the agent starts writing to it.
  depends_on = [aws_cloudwatch_log_group.app]

  tags = { Name = "${var.project_name}-app-${count.index + 1}" }
}
