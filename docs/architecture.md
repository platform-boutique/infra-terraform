# Architecture

## Stacks

Three Terraform projects with separate state, split by how long their contents live:

| Stack | Contains | Lives | Applied by |
|---|---|---|---|
| `stacks/bootstrap` | state bucket and its KMS key, GitHub OIDC provider, the plan and apply roles | forever | a person, with `scripts/bootstrap.sh` (the pipeline's own roles live here) |
| `stacks/foundation` | the ACM certificate for the domain | forever | the Foundation workflow |
| `stacks/platform` | network, EKS, Cilium, nodes, the gp3 StorageClass, Argo CD (bootstrap), ALB, DNS records, the database, the External Secrets role | hours, then destroyed | the Deploy and Destroy workflows |

A destroy of the platform therefore cannot touch the certificate, the hosted zone, the state or the roles. Every value of the
environment is in `stacks/<stack>/<stack>.auto.tfvars`; modules have no environment defaults, so there is one place to change a size,
a zone or a version. Provider versions are pinned exactly in each stack's `versions.tf` (the modules state only a lower bound).

## Network

| | Zone a | Zone b |
|---|---|---|
| Public subnet (ALB, NAT gateway) | 10.0.0.0/24 | 10.0.1.0/24 |
| Private subnet (nodes) | 10.0.10.0/24 | 10.0.11.0/24 |

Each private subnet routes outbound traffic through the NAT gateway of its own zone, so the loss of a zone does not cut the other one off.
The subnets are carved out of the VPC CIDR with `cidrsubnet`; the module only accepts a VPC CIDR between /8 and /16, so that every subnet is a /24.
The default security group allows nothing.

## Cluster, and why there are several modules for it

The community EKS module cannot create the cluster, Cilium and the nodes in one go:

1. **`eks-cluster`**: the control plane with *no* add-ons. EKS does not install the AWS VPC CNI, kube-proxy or CoreDNS here.
2. **`cilium`**: the Gateway API CRDs (vendored unchanged in `modules/cilium/charts/gateway-api-crds`, checked against a SHA-256 and installed with the Helm provider, the only one that can plan before the cluster exists), then Cilium. It has to come before the nodes: a managed node group only becomes active when its
   nodes are Ready, and a node is not Ready until a CNI runs. Argo CD cannot do this job, because it needs nodes.
3. **`eks-nodes`**: the Spot node group, CoreDNS and the EBS CSI driver (both need nodes).
4. **`storage-class`**: the default `gp3` StorageClass, after the EBS CSI driver.
5. **`argocd-bootstrap`**: Argo CD, the root Application, two namespaces and the External Secrets service account. Then Git takes over.

## How a cluster is bootstrapped, and where Terraform stops

```text
Terraform (stacks/platform)                                                      Git (platform-demo-helm, gitops/)
---------------------------                                                      ---------------------------------
network -> eks-cluster (control plane, access entries)
        -> cilium (Gateway API CRDs, Cilium, SPIRE, WireGuard)      SPIRE server Pending: no node, no volume yet
        -> eks-nodes (Spot nodes Ready, CoreDNS, EBS CSI)           SPIRE server starts once the gp3 class exists
        -> storage-class (gp3 default, gp2 demoted)                 its claim binds
        -> argocd-bootstrap
             namespaces argocd, external-secrets
             ServiceAccount external-secrets/external-secrets (+ IAM role annotation)
             helm release "argocd"       minimal values, bootstrap only
             helm release "argocd-root"  AppProject platform-admin + Application platform-root ---> platform-root syncs gitops/apps
        -> alb, dns (independent of the above)                                                          |
                                                                                                        v
                                                       Application argocd: Argo CD re-applies its OWN full values (Dex, RBAC ...)
                                                       post-sync Job: restarts Cilium once the SPIRE server is Ready
                                                       External Secrets Operator (serviceAccount.create=false, name=external-secrets)
                                                       Kyverno and policies, Gateway and HTTPRoutes, Dex, Backstage, the shop ...
```

**What Terraform installs, and why only that.** Argo CD cannot install itself on nodes that do not exist, so the cluster, the CNI, the
nodes and the storage class come first, then Argo CD and the one object that starts everything else. Everything else (Kyverno, the
External Secrets Operator, the Gateway, the shop) is Git's. Only the Helm provider is used for this (plus one Kubernetes-provider
annotation, see Storage): it is the one that can plan before the cluster exists.

**The hand-over, and why Terraform and Argo CD do not fight.** The Helm release `argocd` is *bootstrap only*. Its values are the
minimum needed to get in (public URL, plain HTTP behind the ALB, no Dex, no notifications, a `ClusterIP` Service). After the root
Application syncs, the Application `argocd` of the Helm repository (same release name and namespace, same chart version, values from
Git) re-applies every resource of the release with the full configuration and from then on manages and upgrades Argo CD. To keep
Terraform out of the way:

- `ignore_changes = [values, version]` on the release: editing the bootstrap values or the chart version in Terraform does nothing after
  the first install. Change Argo CD in Git.
- The Helm provider only compares the release record (a Secret that Argo CD never touches, because it renders the chart itself and
  applies the result), so Argo CD's changes are not drift for Terraform.
- The chart version (`argocd_chart_version`) must equal `targetRevision` in `gitops/layers/platform/application-argocd.yaml`, or the first sync is an
  up- or downgrade.
- The AppProject `platform-admin` exists twice on purpose: Terraform's copy lets the root Application start, the copy in Git
  (`appproject-platform-admin.yaml`) is the reviewed one. Keep them identical.
- The namespaces `argocd` and `external-secrets` and the service account are Terraform's; the `CreateNamespace` /
  `managedNamespaceMetadata` of Argo CD's Applications set the same labels.
- On destroy `scripts/destroy-prepare.sh` removes the Applications first (without letting Argo CD prune itself), then Terraform
  uninstalls both releases.

**Why the External Secrets service account is created here.** Its `eks.amazonaws.com/role-arn` annotation contains the AWS account id,
which must not be in a public Git repository. The operator's chart in Git runs with `serviceAccount.create=false` and
`name=external-secrets`; `secrets_access` trusts exactly `external-secrets/external-secrets` (`external_secrets_service_account`).

**Argo CD is reached only through the Gateway.** Its Service is `ClusterIP`; there is no `LoadBalancer` and no Ingress, so Kubernetes
creates no AWS resource. `https://argocd.platform-demo.click` works once Git has created the Gateway and the HTTPRoute (`argocd` is in
`hostnames`, so the DNS record exists from the start).

**Getting in.** There is no local account: Git disables `admin`, and so does the bootstrap install (`argocd_admin_enabled = false`), so
no password exists. A person signs in with GitHub through Dex, which needs the External Secrets Operator and the OAuth App secrets
([Secrets](secrets.md)). Until then, or if Dex is broken, the break-glass path is `argocd --core`: it talks to the Kubernetes API with
the person's own IAM identity (cluster-admin through `admin_user_names`) and needs no password. See
[Operations](operations.md#getting-into-argo-cd).

## Storage

EKS ships only the legacy `gp2` StorageClass. `modules/storage-class` creates `gp3` (EBS CSI driver, encrypted, `WaitForFirstConsumer`,
expandable, reclaim `Delete`) through a tiny local Helm chart and makes it the only default. EKS owns `gp2`, so Helm cannot edit it: its
default annotation is turned off with the Kubernetes provider's `kubernetes_annotations`, the only use of that provider in the stack.
EBS volumes belong to one zone: a pod with a volume (the SPIRE server, the databases) can only restart in that zone.

Volumes the cluster creates are not Terraform resources. `scripts/destroy-prepare.sh` deletes the claims and waits for the driver to
delete the volumes; `scripts/destroy-verify.sh` lists what is left. Databases on RDS are Terraform resources and are destroyed by it.

## Cilium

| Setting | Value | Why |
|---|---|---|
| Routing | tunnel (VXLAN, UDP 8472) | pods need no VPC addresses; the VPC stays small |
| Pod CIDR | 10.244.0.0/16, a /24 per node | must not overlap the VPC (10.0.0.0/16) or services (172.20.0.0/16) |
| kube-proxy | replaced | Cilium implements Services; it reaches the API server by its DNS name |
| Gateway API | on, `hostNetwork` | no Service of type LoadBalancer, see [the ALB and the Gateway](alb-and-gateway.md) |
| Hubble | on (relay, UI) | flow visibility; the portal's Network view reads it |
| Mutual authentication | SPIFFE/SPIRE, `cilium_mutual_authentication_enabled` | policies with `authentication.mode: required`; Cilium installs the SPIRE server (gp3 volume) in `cilium-spire` |
| Encryption | WireGuard with node encryption, `cilium_encryption_enabled` | traffic between nodes; UDP 51871 is open between the nodes |
| Operator | 2 replicas | highly available |

### Mutual authentication and encryption

- **SPIRE** is Cilium's own installation (`authentication.mutual.spire.install`) with settings of its own. The
  server runs as root: the image's uid 1000 cannot bind the admin socket in the root-owned hostPath directory, `cilium-init`
  cannot register Cilium's identities through its `/proc` (that needs the same uid or `CAP_SYS_PTRACE`), and on EKS it could not write
  the root-owned EBS volume either. The container gets no extra capabilities. The CA lives on a PVC of the explicitly named `gp3` class,
  so a restart does not change the trust domain. Cilium has deprecated this feature in 1.20 (removal announced for 1.21).
- **Ordering that Terraform cannot express.** Cilium is installed before the nodes, and the SPIRE server needs a node and a volume. On a
  fresh build the SPIRE server is Pending, then starts when a node is Ready and `gp3` exists (the claim binds by itself). Nodes do not
  wait for SPIRE and traffic flows without authentication meanwhile. Cilium's agents and operator pick up their SPIFFE identity only after
  a **restart once the server is Ready**; that restart is a post-sync Job in the GitOps repository, not a Terraform step. Until it has
  run, a policy that *requires* authentication drops traffic ("no SPIFFE ID"), so workloads that need it come after that Job.
- **WireGuard** works with tunnel (VXLAN) routing (traffic is encapsulated twice, Cilium subtracts both overheads from the MTU), with
  kube-proxy replacement and with Hubble. Node encryption (beta) also covers the host-network Gateway Envoy's traffic to pods on other
  nodes; traffic from the ALB into the node comes from outside the cluster and is not encrypted by Cilium. Pods on the same node are not
  encrypted, by design. Strict mode is off (it would drop traffic during a half-finished rollout).
- **The Gateway keeps working**: Envoy listens in host-network mode, which neither SPIRE nor WireGuard changes. A policy cannot require
  mutual authentication for traffic that comes from the Gateway (the `ingress` identity has no SPIFFE ID).

### Risks of the first Deploy with these settings

None of this could be tested without building the cluster.

1. **Kernel.** WireGuard needs `CONFIG_WIREGUARD` (Linux 5.6+; the Amazon Linux 2023 AMI has a 6.x kernel, but its configuration was not
   verified on a node). If the agent cannot create `cilium_wg0` it does not start and the node group never becomes active. Set
   `cilium_encryption_enabled = false` first.
2. **SPIRE before the nodes.** If the Cilium operator blocked on SPIRE at start-up, the cluster-pool IPAM (the operator hands out pod CIDRs)
   would block with it and the cluster would deadlock. Cilium documents the connection as retried in the background, but this has not been tried
   here: `cilium_mutual_authentication_enabled = false` is the way out.
3. **Webhooks and the overlay.** The EKS control plane cannot reach pod addresses (the pod CIDR is not routed in the VPC). Every admission webhook of a
   component installed through Git (Kyverno, External Secrets, cert-manager ...) must run with `hostNetwork: true` on a port the node security
   group opens from the control plane (4443, 6443, 8443, 9443 or 10250), or the API server cannot call it.
4. **Zonal volume.** The SPIRE server's EBS volume stays in one zone; if a Spot interruption leaves no node in that zone for a while, the
   server stays Pending (agents keep working with their cached identities until these expire).
5. **Node encryption** is beta in Cilium; `cilium_node_encryption_enabled = false` keeps only pod-to-pod encryption.

## Nodes

Managed node group `workers`, Amazon Linux 2023, **Spot**, two nodes, 100 GiB gp3 encrypted root volume, one Auto Scaling group over
both private subnets. Instance types (all 4 vCPU / 16 GiB): m6i, m6a, m5, m5a, m7i, m7a `.xlarge`; Spot takes whichever is cheapest
and available. Session Manager (no SSH) gives a shell. A Spot interruption replaces the node; the ALB registration follows
automatically, because the target group is attached to the Auto Scaling group.

**Hardening.** The instance metadata service requires IMDSv2 with a hop limit of 1, so a pod cannot reach the node role's credentials
(the node's own processes still can). Pods that need AWS use IAM roles for service accounts (the EBS CSI driver, the External Secrets
role); Cilium and the Gateway run in the host network and are not affected. The EBS CSI driver may log that it cannot reach the
metadata service and falls back to the Kubernetes API for the node's zone and instance ID; it still works. The root volume is encrypted
(gp3, the account's default EBS key). Every node also gets a second container runtime, gVisor, installed and checksum-verified at boot:
[gVisor](gvisor.md).

Pod limit: the AWS AMI derives it from the instance's network interfaces (58 on `m5.xlarge`). It is not needed for Cilium's overlay;
raise it with a kubelet setting if the cluster ever runs out of pod slots.

## Access

EKS access entries, no `aws-auth` ConfigMap. Cluster-admin: the apply role (`admin_role_names`) and the users in
`admin_user_names`; the identity that creates the cluster gets nothing extra, so a laptop and the pipeline build the same cluster. The plan role may only read (Terraform refreshes the Helm releases, which live in Secrets). The public API endpoint
is open to every address (`api_allowed_cidrs`) and every request is authenticated by IAM; the private endpoint is on for the nodes.
Secrets are encrypted with a customer-managed KMS key. The control plane logs (all five types) go to CloudWatch for 30 days.

## Database

Backstage's catalog lives in a **Multi-AZ RDS for PostgreSQL** instance (not Aurora), `modules/database`, `<name>-backstage`.

| Setting | Value | Why |
|---|---|---|
| Engine | PostgreSQL 17 (`17.11`), minor upgrades automatic | the newest 17.x RDS offers; later minors are applied in the maintenance window |
| Instance, storage | `db.t4g.small`, gp3 20 GiB growing to 50, encrypted with a customer-managed KMS key | small and cheap; the same key encrypts the backups and the master password secret |
| Availability | Multi-AZ: a synchronous standby in the second zone, automatic failover | survives the loss of a zone |
| Network | DB subnet group on the private subnets, not public; 5432 only from the **nodes' security group** | pods use the Cilium overlay and leave through the node, so the node security group is the source |
| TLS | required (`rds.force_ssl = 1` in the parameter group) | clients use `sslmode=require` or stricter |
| Backups, logs | 7 days of automated backups with point-in-time recovery; the `postgresql` log exported to CloudWatch (30 days) | |
| Authentication | master user `backstage`, password generated and kept by RDS in Secrets Manager; IAM database authentication on | the password never reaches the state |
| Off | Performance Insights, enhanced monitoring | cost; accepted risks are written next to the resources (inline `#checkov:skip`) |

The environment is ephemeral and destroyed on purpose, so `database_deletion_protection = false` and `database_skip_final_snapshot = true`
in `platform.auto.tfvars`. **A production environment sets `database_deletion_protection = true` and `database_skip_final_snapshot = false`**
(the final snapshot is then named `<name>-backstage-final`; delete or rename it before recreating the database with the same name). How the
cluster gets the connection details and the password: [Secrets and the database](secrets.md).
