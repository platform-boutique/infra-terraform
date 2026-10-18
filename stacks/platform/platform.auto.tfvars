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

# Who may use the cluster, besides the identity that created it (which is cluster-admin automatically).
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
