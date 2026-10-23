variable "identifier" {
  description = "Identifier of the DB instance, and the prefix of everything created for it (security group, subnet group, parameter group, KMS alias)."
  type        = string
}

variable "vpc_id" {
  description = "VPC the database lives in."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets of the DB subnet group, in at least two availability zones (Multi-AZ keeps the standby in the second one). The private subnets."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "A Multi-AZ database needs subnets in at least two availability zones."
  }
}

variable "client_security_group_id" {
  description = "The only source allowed to reach the database on 5432: the nodes' security group (pods use a Cilium overlay and leave through the node, so traffic arrives from the node's address)."
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL version, for example 17.11. Minor upgrades happen by themselves (auto_minor_version_upgrade), so changes of this value are ignored after creation: change the major version by replacing the instance."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?$", var.engine_version))
    error_message = "engine_version must look like 17 or 17.11."
  }
}

variable "instance_class" {
  description = "DB instance class, for example db.t4g.small."
  type        = string
}

variable "allocated_storage_gib" {
  description = "Initial size of the gp3 volume (at least 20)."
  type        = number

  validation {
    condition     = var.allocated_storage_gib >= 20
    error_message = "gp3 volumes of RDS PostgreSQL start at 20 GiB."
  }
}

variable "max_allocated_storage_gib" {
  description = "Storage autoscaling limit; 0 turns autoscaling off."
  type        = number
}

variable "database_name" {
  description = "Name of the database created in the instance."
  type        = string
}

variable "master_username" {
  description = "Master user. Its password is generated and kept by RDS in Secrets Manager (manage_master_user_password): it is never in a variable or in the state."
  type        = string
}

variable "backup_retention_days" {
  description = "Days automated backups are kept (1 to 35). Backups also allow point-in-time recovery."
  type        = number

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 1 and 35."
  }
}

variable "deletion_protection" {
  description = "Refuse to delete the instance. Off in the ephemeral environment (it is destroyed on purpose); a production environment sets it to true."
  type        = bool
}

variable "skip_final_snapshot" {
  description = "Skip the snapshot taken on deletion. True in the ephemeral environment; a production environment sets it to false (the snapshot is then named <identifier>-final)."
  type        = bool
}

variable "log_retention_days" {
  description = "Retention of the exported PostgreSQL log in CloudWatch."
  type        = number
}

variable "connection_parameter_path" {
  description = "Parameter Store path under which the NON-secret connection details are written as plain String parameters: <path>/host, /port, /database and /username. The password is never written there."
  type        = string

  validation {
    condition     = can(regex("^/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$", var.connection_parameter_path))
    error_message = "connection_parameter_path must be a path such as /platform-demo/rds/backstage (leading slash, no trailing slash)."
  }
}

variable "tags" {
  description = "Tags added to every resource."
  type        = map(string)
  default     = {}
}
