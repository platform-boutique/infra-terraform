# Every value of the environment is set in platform.auto.tfvars (committed). Only what belongs to a person goes in local.auto.tfvars.

variable "region" {
  description = "AWS region."
  type        = string
}

variable "name" {
  description = "Name of the platform: cluster, VPC and load balancer (at most 28 characters)."
  type        = string
}

variable "azs" {
  description = "Availability zones (high availability: two, one NAT gateway and one subnet pair each)."
  type        = list(string)
}

variable "vpc_cidr" {
  description = "CIDR of the VPC; the subnets are /24 blocks of it."
  type        = string
}

variable "service_cidr" {
  description = "CIDR of Kubernetes Services. Must not overlap the VPC or the pod CIDR."
  type        = string
}

variable "pod_cidr" {
  description = "CIDR the pods get their addresses from (Cilium's overlay: not routed in the VPC). Must not overlap the VPC or the service CIDR."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version of the cluster: the newest EKS version the pinned Cilium release supports (Cilium 1.20 documents 1.33 to 1.36; EKS also offers 1.37)."
  type        = string
}

variable "cilium_version" {
  description = "Version of the cilium/cilium Helm chart. Keep it in step with kind/up.sh of the Helm repository."
  type        = string
}

variable "gateway_api_version" {
  description = "Version of the Gateway API CRDs (standard channel). Keep it in step with kind/up.sh of the Helm repository."
  type        = string
}

variable "gateway_crds_sha256" {
  description = "SHA-256 of standard-install.yaml of that Gateway API release: the download is refused if it differs."
  type        = string
}

variable "domain_name" {
  description = "The registered domain (Route 53 -> Registered domains). Its hosted zone and its certificate (stacks/foundation) must exist."
  type        = string
}

variable "hostnames" {
  description = "Host names under the domain that point at the load balancer, one per platform UI."
  type        = list(string)
}

variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach the public Kubernetes API endpoint. Every request is still authenticated by IAM; 0.0.0.0/0 is what lets a GitHub runner (new address every run) and a laptop (address changes) in, with a plan that does not depend on either."
  type        = list(string)
}

variable "alb_allowed_cidrs" {
  description = "CIDRs allowed to reach the ALB on ports 80 and 443: your own address as /32. Not committed: set it in local.auto.tfvars, and as the repository variable ALB_ALLOWED_CIDRS for the pipeline."
  type        = list(string)
}

variable "admin_role_names" {
  description = "IAM roles that get cluster-admin (the pipeline's apply role). Names, not ARNs: the account is the current one."
  type        = list(string)
}

variable "admin_user_names" {
  description = "IAM users that get cluster-admin (the person who runs kubectl from a laptop)."
  type        = list(string)
}

variable "viewer_role_names" {
  description = "IAM roles that may read everything in the cluster (the pipeline's plan role: Terraform refreshes its Helm releases and manifests)."
  type        = list(string)
}

variable "log_retention_days" {
  description = "Retention of the control plane logs in CloudWatch."
  type        = number
}

variable "node_instance_types" {
  description = "Instance types of the Spot worker nodes. All 4 vCPU / 16 GiB, in several families so Spot can pick whichever is cheapest and available."
  type        = list(string)
}

variable "node_capacity_type" {
  description = "SPOT or ON_DEMAND."
  type        = string
}

variable "node_count" {
  description = "Number of worker nodes."
  type        = number
}

variable "node_disk_size_gib" {
  description = "Root volume of each node."
  type        = number
}

variable "gateway_port" {
  description = "Port the Cilium Gateway listeners bind on every node; the ALB forwards to it. The Gateway's listener must use the same port."
  type        = number
}

variable "secrets_parameter_prefix" {
  description = "Parameter Store path of the platform's secrets (created by hand in the console, see docs/secrets.md)."
  type        = string
}

# ==================================================================================================================================
# The database
# ==================================================================================================================================
variable "database_engine_version" {
  description = "PostgreSQL version of the RDS instance (17.x; RDS applies later minor versions by itself)."
  type        = string
}

variable "database_instance_class" {
  description = "RDS instance class."
  type        = string
}

variable "database_allocated_storage_gib" {
  description = "Initial size of the database's gp3 volume (at least 20)."
  type        = number
}

variable "database_max_allocated_storage_gib" {
  description = "Storage autoscaling limit of the database; 0 turns autoscaling off."
  type        = number
}

variable "database_name" {
  description = "Name of the database Backstage uses."
  type        = string
}

variable "database_username" {
  description = "Master user of the database. Its password is generated and kept by RDS in Secrets Manager."
  type        = string
}

variable "database_backup_retention_days" {
  description = "Days the database's automated backups are kept."
  type        = number
}

variable "database_deletion_protection" {
  description = "Refuse to delete the database. False while the platform is ephemeral and destroyed on purpose; a production environment sets true."
  type        = bool
}

variable "database_skip_final_snapshot" {
  description = "Skip the database's final snapshot on deletion. True while the platform is ephemeral; a production environment sets false."
  type        = bool
}

# ==================================================================================================================================
# gVisor (sandboxed runtime on every node)
# ==================================================================================================================================
variable "gvisor_release" {
  description = "gVisor release installed on every node (gs://gvisor/releases/release/<release>/x86_64/)."
  type        = string
}

variable "gvisor_sha512" {
  description = "SHA-512 of that release's gvisor.tar.bz2, as published next to it: the node refuses a download that differs."
  type        = string
}

variable "gvisor_platform" {
  description = "gVisor platform: systrap works on ordinary EC2 instances (no KVM); kvm needs bare metal or nested virtualization."
  type        = string
}
