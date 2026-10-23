# The platform's environment. Loaded automatically by Terraform, locally and in the pipeline: one place for every choice.
# (Your own address does not belong here: local.auto.tfvars, see docs/operations.md.)

region = "us-east-1"
name   = "platform-demo"

# Network: two zones, a /24 public and private subnet and a NAT gateway in each. Pods use an overlay, so they take no VPC addresses.
azs          = ["us-east-1a", "us-east-1b"]
vpc_cidr     = "10.0.0.0/16"
service_cidr = "172.20.0.0/16"
pod_cidr     = "10.244.0.0/16"

# Versions that must fit together: Cilium 1.20 documents Kubernetes 1.33 to 1.36 (EKS also offers 1.37).
kubernetes_version  = "1.36"
cilium_version      = "1.20.3"
gateway_api_version = "v1.6.3"
gateway_crds_sha256 = "356c2b8e286a964dc20995435659ad1095386329974793af10bbfe3eff977fe5"

# Addresses
domain_name = "platform-demo.click"
hostnames   = ["argocd", "backstage", "grafana", "dex", "hubble", "shop"]

# The API endpoint is public and IAM-authenticated (accepted risk, .trivyignore.yaml).
api_allowed_cidrs = ["0.0.0.0/0"]

# Who may use the cluster. Explicit: whoever creates it gets nothing extra.
admin_role_names  = ["platform-demo-github-apply"]
admin_user_names  = ["terraform-platform"]
viewer_role_names = ["platform-demo-github-plan"]

log_retention_days = 30

# Nodes: Spot, 4 vCPU / 16 GiB, several families so Spot can pick whichever is cheapest and available.
node_instance_types = ["m6i.xlarge", "m6a.xlarge", "m5.xlarge", "m5a.xlarge", "m7i.xlarge", "m7a.xlarge"]
node_capacity_type  = "SPOT"
node_count          = 2
node_disk_size_gib  = 100

# The ALB forwards to this port on every node, where the Cilium Gateway listens (plain HTTP: TLS ends at the ALB).
gateway_port = 8080

secrets_parameter_prefix = "/platform-demo"

# ----------------------------------------------------------------------------------------------------------------------------------
# The database: Multi-AZ RDS for PostgreSQL (not Aurora) for Backstage, in the private subnets, reachable only from the nodes.
# The environment is ephemeral and destroyed on purpose, so it has no deletion protection and takes no final snapshot. A production
# environment sets database_deletion_protection = true and database_skip_final_snapshot = false (docs/secrets.md).
database_engine_version            = "17.11"
database_instance_class            = "db.t4g.small"
database_allocated_storage_gib     = 20
database_max_allocated_storage_gib = 50
database_name                      = "backstage"
database_username                  = "backstage"
database_backup_retention_days     = 7
database_deletion_protection       = false
database_skip_final_snapshot       = true

# ----------------------------------------------------------------------------------------------------------------------------------
# gVisor on every node (docs/gvisor.md). The release is pinned; the node verifies the SHA-512 gVisor publishes next to the tarball
# (https://storage.googleapis.com/gvisor/releases/release/<release>/x86_64/gvisor.tar.bz2.sha512) and refuses a download that differs.
# To update: pick a release, download its .sha512 file, compare it with the tarball, and change both values together.
# systrap works on ordinary (non-metal) EC2 instances; kvm would need bare metal.
gvisor_release  = "20261019.0"
gvisor_sha512   = "7cbc2aeeee809dcccfb40e612504a1b76f2c119790cee59e482f7b35428cccc4f71705e7e322442d07d1f7d29b5d9e72e31319fc3088d6dcbec9fc7c1f0d8881"
gvisor_platform = "systrap"

# ---- BEGIN section: Cilium security, storage class, Argo CD bootstrap ------------------------------

# Cilium: SPIFFE/SPIRE mutual authentication (beta; GitOps restarts Cilium once the SPIRE server is Ready) and WireGuard encryption.
# If the first Deploy leaves the nodes NotReady, set cilium_encryption_enabled = false first (kernel without WireGuard), then
# cilium_mutual_authentication_enabled = false, and see docs/architecture.md.
cilium_mutual_authentication_enabled = true
spire_data_size                      = "1Gi"
cilium_encryption_enabled            = true
cilium_node_encryption_enabled       = true

# The default StorageClass (encrypted gp3). EKS's own gp2 stops being the default.
storage_class_name = "gp3"

# Argo CD is installed once by Terraform with minimal values, then manages itself from Git. Keep the chart version equal to the one in
# gitops/layers/platform/application-argocd.yaml of the Helm repository. No admin account: sign in with GitHub through Dex; `argocd --core` is break-glass.
argocd_chart_version = "10.10.0"
argocd_admin_enabled = false

# The root Application: where Git takes over. The External Secrets service account is created here (it carries the IAM role's ARN, which
# must never be in Git); the External Secrets chart in Git uses it with serviceAccount.create=false and name=external-secrets.
gitops_repo_url                  = "https://github.com/platform-boutique/platform-demo-helm.git"
gitops_revision                  = "main"
gitops_path                      = "gitops/apps"
external_secrets_service_account = "external-secrets/external-secrets"

# ---- END section ------------------------------------------------------------------------------------------------------------------
