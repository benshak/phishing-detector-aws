#!/bin/bash
# Runs once, as root, on the server's first boot (after cloud-init wrote the files).
# Its output is in /var/log/cloud-init-output.log on the server.
set -euxo pipefail

# Python 3.11 and the CloudWatch agent from the Amazon Linux repositories.
dnf install -y python3.11 python3.11-pip amazon-cloudwatch-agent

# A user with no login shell, so the app does not run as root.
id phishing || useradd --system --no-create-home --shell /sbin/nologin phishing

# Isolated Python environment with the pinned versions from requirements.txt.
python3.11 -m venv /opt/phishing/venv
/opt/phishing/venv/bin/pip install --no-cache-dir -r /opt/phishing/requirements.txt

mkdir -p /var/log/phishing
chown -R phishing:phishing /opt/phishing /var/log/phishing

# Start the app now and on every reboot.
systemctl daemon-reload
systemctl enable --now phishing

# Start shipping /var/log/phishing/app.log to CloudWatch Logs.
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json
