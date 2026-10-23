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

# ---- BEGIN section: Cilium security, storage class, Argo CD bootstrap (feat/spire-and-argocd-bootstrap) --------------------------

variable "cilium_mutual_authentication_enabled" {
  description = "Install SPIRE with Cilium and enable mutual authentication (SPIFFE). Beta, deprecated in Cilium 1.20. After the first build GitOps restarts Cilium once the SPIRE server is Ready."
  type        = bool
}

variable "spire_data_size" {
  description = "Size of the SPIRE server's gp3 volume."
  type        = string
}

variable "cilium_encryption_enabled" {
  description = "Transparent WireGuard encryption between the nodes (UDP 51871, a kernel with WireGuard). Switch off if the Cilium agents cannot create the cilium_wg0 device."
  type        = bool
}

variable "cilium_node_encryption_enabled" {
  description = "Also encrypt node-to-node traffic, which covers the Gateway's host-network Envoy (beta in Cilium). Only effective with cilium_encryption_enabled."
  type        = bool
}

variable "storage_class_name" {
  description = "Name of the default StorageClass Terraform creates (gp3 on the EBS CSI driver). The SPIRE server's claim names it explicitly; charts that set no class get it as the default."
  type        = string
}

variable "argocd_chart_version" {
  description = "Version of the argo/argo-cd chart for the bootstrap install: the same as targetRevision in gitops/apps/application-argocd.yaml of the Helm repository. Only read when the release is created; Argo CD upgrades itself from Git afterwards."
  type        = string
}

variable "argocd_admin_enabled" {
  description = "Keep Argo CD's built-in admin account (and its initial password Secret) during the bootstrap, until Git switches it off. false: nobody has a password; break-glass is `argocd --core`. Only read when the release is created."
  type        = bool
}

variable "gitops_repo_url" {
  description = "Git repository of the root Application (the Helm repository, gitops/apps)."
  type        = string
}

variable "gitops_revision" {
  description = "Branch, tag or commit the root Application follows."
  type        = string
}

variable "gitops_path" {
  description = "Directory of that repository the root Application syncs."
  type        = string
}

variable "external_secrets_service_account" {
  description = "namespace/name of the External Secrets Operator's service account: created by Terraform with the IAM role annotation (the chart in Git runs with serviceAccount.create=false), and the only account the role trusts."
  type        = string
}

# ---- END section ------------------------------------------------------------------------------------------------------------------
