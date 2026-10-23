# A Multi-AZ RDS for PostgreSQL instance (not Aurora) for Backstage's catalog, in the private subnets.
#
#   pods (Cilium overlay) --leave through the node--> node security group --5432--> database security group --> RDS (primary + standby in a second zone)
#
# - Reachable only from the nodes' security group, never from the internet (publicly_accessible = false, private subnets, no route in).
# - TLS is required (rds.force_ssl in the parameter group); the storage, the backups and the master user secret are encrypted with
#   one customer-managed key made here.
# - The master password is generated and kept by RDS in Secrets Manager (manage_master_user_password): it is never in a variable,
#   in the plan or in the state. RDS rotates it by itself every 7 days, so whoever reads the secret must read it again (External
#   Secrets refreshes, a Reloader restarts the pods; see docs/secrets.md). Its ARN is an output; modules/secrets-access lets the
#   External Secrets role read exactly that secret.
# - The NON-secret connection details (host, port, database, user) are written as plain Parameter Store String parameters, the contract
#   with GitOps: nothing in Git has to know the generated host name. They vanish with the platform.
#
# The environment is ephemeral and destroyed on purpose, so deletion_protection and skip_final_snapshot are variables (off / skipped in
# platform.auto.tfvars). A production environment sets deletion_protection = true and skip_final_snapshot = false.

locals {
  # postgres17.11 -> postgres17: the parameter group family follows the major version.
  parameter_group_family = "postgres${split(".", var.engine_version)[0]}"
}

# --- Encryption key ----------------------------------------------------------------------------------------------------------
# One key for the volume, the automated backups and the master user secret. The default key policy delegates to IAM, so the External
# Secrets role (modules/secrets-access) gets kms:Decrypt through its own IAM policy, restricted to Secrets Manager.
resource "aws_kms_key" "this" {
  #checkov:skip=CKV2_AWS_64:The default key policy is intended: it delegates to IAM (account root), and the only other principals (the RDS service, the External Secrets role) get access through their own IAM policies, scoped by kms:ViaService.
  description             = "${var.identifier} database: storage, backups and master user secret"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  tags = var.tags
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.identifier}"
  target_key_id = aws_kms_key.this.key_id
}

# --- Network -----------------------------------------------------------------------------------------------------------------
resource "aws_db_subnet_group" "this" {
  name        = var.identifier
  description = "Private subnets of ${var.identifier}"
  subnet_ids  = var.subnet_ids

  tags = var.tags
}

resource "aws_security_group" "this" {
  name_prefix = "${var.identifier}-db-"
  description = "Database ${var.identifier}: PostgreSQL from the nodes only"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.identifier}-db" })

  lifecycle {
    create_before_destroy = true
  }
}

# Pods use an overlay and leave through the node (source NAT), so the source is the node security group. There is no egress rule: a
# database opens no connection of its own (RDS maintenance, backups and failover do not use the security group).
resource "aws_vpc_security_group_ingress_rule" "postgres_from_nodes" {
  security_group_id            = aws_security_group.this.id
  description                  = "PostgreSQL from the nodes"
  referenced_security_group_id = var.client_security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

# --- Parameters --------------------------------------------------------------------------------------------------------------
resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.identifier}-"
  description = "${var.identifier}: TLS required, DDL and slow statements logged"
  family      = local.parameter_group_family

  # Clients that do not use TLS are refused. (Dynamic parameter: no reboot.)
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  # Schema changes and statements slower than a second go to the PostgreSQL log, which is exported to CloudWatch.
  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# --- Logs --------------------------------------------------------------------------------------------------------------------
# RDS would create this group itself, with no expiry and left behind after a destroy. Creating it first gives it a retention and lets
# Terraform remove it.
resource "aws_cloudwatch_log_group" "postgresql" {
  #checkov:skip=CKV_AWS_158:The PostgreSQL log holds error messages and DDL, not data; the default CloudWatch encryption is enough for a test environment.
  #checkov:skip=CKV_AWS_338:Retention is a variable (30 days in platform.auto.tfvars); one year is not worth its cost for an ephemeral platform.
  name              = "/aws/rds/instance/${var.identifier}/postgresql"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# --- The instance ------------------------------------------------------------------------------------------------------------
resource "aws_db_instance" "this" {
  #checkov:skip=CKV_AWS_118:Enhanced monitoring (a second IAM role and a per-second metrics stream) is not worth its cost here; CloudWatch's standard RDS metrics stay on.
  #checkov:skip=CKV_AWS_353:Performance Insights is off: the free 7-day tier is not needed for a catalog database in a test environment. Switch it on (with the key above) when the load needs a closer look.
  #checkov:skip=CKV_AWS_354:Performance Insights is off, so there is nothing to encrypt.
  #checkov:skip=CKV_AWS_293:Created and destroyed on demand to save cost; deletion_protection is a variable to switch on once the platform is long-lived.
  identifier = var.identifier

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  # gp3, encrypted with the key above, growing by itself up to max_allocated_storage_gib.
  storage_type          = "gp3"
  allocated_storage     = var.allocated_storage_gib
  max_allocated_storage = var.max_allocated_storage_gib > 0 ? var.max_allocated_storage_gib : null
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.this.arn

  db_name  = var.database_name
  username = var.master_username

  # RDS creates the password, stores it in Secrets Manager (encrypted with the same key) and rotates it every 7 days. It never
  # appears here, in the plan or in the state.
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.this.arn

  # A standby in the second zone with synchronous replication and automatic failover.
  multi_az = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  publicly_accessible    = false
  parameter_group_name   = aws_db_parameter_group.this.name

  # Database users can also authenticate with an IAM token (harmless; nothing uses it yet).
  iam_database_authentication_enabled = true

  backup_retention_period    = var.backup_retention_days
  copy_tags_to_snapshot      = true
  auto_minor_version_upgrade = true

  # Performance Insights and enhanced monitoring are off (see the skips above).
  performance_insights_enabled = false
  monitoring_interval          = 0

  enabled_cloudwatch_logs_exports = ["postgresql"]

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.identifier}-final"

  tags = var.tags

  lifecycle {
    # Minor versions are applied by RDS (auto_minor_version_upgrade): do not plan a downgrade back to engine_version.
    ignore_changes = [engine_version]
  }

  depends_on = [aws_cloudwatch_log_group.postgresql]
}

# --- Connection details for GitOps -------------------------------------------------------------------------------------------
# Plain String parameters: host, port, database and user are not secret, so their state exposure does not matter and they disappear
# with the platform (unlike the hand-made SecureString parameters of docs/secrets.md). The password is NOT here: it stays in the
# Secrets Manager secret RDS manages (output master_user_secret_arn).
locals {
  connection_parameters = {
    host     = aws_db_instance.this.address
    port     = tostring(aws_db_instance.this.port)
    database = aws_db_instance.this.db_name
    username = aws_db_instance.this.username
  }
}

resource "aws_ssm_parameter" "connection" {
  #checkov:skip=CKV2_AWS_34:Host, port, database name and user name are not secret (the password lives only in the RDS-managed Secrets Manager secret); a String parameter keeps them readable by the plan role.
  for_each = toset(["host", "port", "database", "username"])

  name        = "${var.connection_parameter_path}/${each.key}"
  description = "${var.identifier}: ${each.key} of the database (not a secret)"
  type        = "String"
  value       = local.connection_parameters[each.key]

  tags = var.tags
}
