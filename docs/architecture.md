# Architecture

## Network

| | Zone a | Zone b |
|---|---|---|
| Public subnet (ALB, NAT gateway) | 10.0.0.0/24 | 10.0.1.0/24 |
| Private subnet (nodes) | 10.0.10.0/24 | 10.0.11.0/24 |

Each private subnet routes outbound traffic through the NAT gateway of its own zone, so the loss of a zone does not cut the other one off.
The subnets are carved out of the VPC CIDR with `cidrsubnet`; the module only accepts a VPC CIDR between /8 and /16, so that every subnet is a /24.
The default security group allows nothing.

## Cluster, and why there are three modules for it

The community EKS module cannot create the cluster, Cilium and the nodes in one go:

1. **`eks-cluster`**: the control plane with *no* add-ons. EKS does not install the AWS VPC CNI, kube-proxy or CoreDNS here.
2. **`cilium`**: the Gateway API CRDs, then Cilium. It has to come before the nodes: a managed node group only becomes active when its
   nodes are Ready, and a node is not Ready until a CNI runs. Argo CD cannot do this job, because it needs nodes.
3. **`eks-nodes`**: the Spot node group, CoreDNS and the EBS CSI driver (both need nodes).

## Cilium

| Setting | Value | Why |
|---|---|---|
| Routing | tunnel (VXLAN, UDP 8472) | pods need no VPC addresses; the VPC stays small |
| Pod CIDR | 10.244.0.0/16, a /24 per node | must not overlap the VPC (10.0.0.0/16) or services (172.20.0.0/16) |
| kube-proxy | replaced | Cilium implements Services; it reaches the API server by its DNS name |
| Gateway API | on, `hostNetwork` | no Service of type LoadBalancer, see [the ALB and the Gateway](alb-and-gateway.md) |
| Hubble | on (relay, UI) | flow visibility; the portal's Network view reads it |
| Operator | 2 replicas | highly available |

Mutual authentication (SPIFFE/SPIRE) is not enabled yet: its bring-up has an ordering step (restart Cilium once the SPIRE server is up)
that belongs in GitOps, not in Terraform. Until then workloads must not require it
(`networkPolicy.cilium.authentication: disabled`, as the lean kind profile does).

## Nodes

Managed node group `workers`, Amazon Linux 2023, **Spot**, two nodes, 100 GiB gp3 encrypted root volume, one Auto Scaling group over
both private subnets. Instance types (all 4 vCPU / 16 GiB): m6i, m6a, m5, m5a, m7i, m7a `.xlarge`; Spot takes whichever is cheapest
and available. Session Manager (no SSH) gives a shell. A Spot interruption replaces the node; the ALB registration follows
automatically, because the target group is attached to the Auto Scaling group.

Pod limit: the AWS AMI derives it from the instance's network interfaces (58 on `m5.xlarge`). It is not needed for Cilium's overlay;
raise it with a kubelet setting if the cluster ever runs out of pod slots.

## Access

EKS access entries, no `aws-auth` ConfigMap. The identity that runs Terraform is cluster-admin; add others with `admin_principal_arns`.
The public API endpoint is restricted to `api_allowed_cidrs`; the private endpoint is on for the nodes. Secrets are encrypted with a
customer-managed KMS key. The control plane logs (all five types) go to CloudWatch for 30 days.
