# Inputs. Values with a default can be left alone; db_password must be set
# in terraform.tfvars (which is git-ignored) so it never reaches GitHub.

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-north-1"
}

variable "project_name" {
  description = "Prefix for resource names and the Project tag"
  type        = string
  default     = "phishing-detector"
}

variable "instance_type" {
  description = "EC2 size for the two app servers (free tier eligible)"
  type        = string
  default     = "t3.micro"
}

variable "db_instance_class" {
  description = "RDS size (free tier eligible)"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Name of the PostgreSQL database the app uses"
  type        = string
  default     = "phishing"
}

variable "db_username" {
  description = "Master user of the RDS database"
  type        = string
  default     = "phishadmin"
}

variable "db_password" {
  description = "Master password of the RDS database (set in terraform.tfvars)"
  type        = string
  # sensitive = Terraform hides the value in plan/apply output.
  sensitive = true

  validation {
    # Letters and digits only, so it is safe inside the server's env file.
    condition     = can(regex("^[A-Za-z0-9]{12,40}$", var.db_password))
    error_message = "Use 12-40 letters and digits only for db_password."
  }
}

variable "cache_node_type" {
  description = "ElastiCache node size (smallest general-purpose node)"
  type        = string
  default     = "cache.t3.micro"
}
