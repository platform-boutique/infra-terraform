# infra-terraform

Terraform for the platform-demo AWS environment: a highly available VPC, an EKS cluster with Cilium as an overlay network, two Spot
worker nodes, and an ALB that Terraform owns. **Every AWS resource is created and destroyed by Terraform; Kubernetes creates none.**

```
internet --:80--> ALB (public /24 subnets, 2 zones) --:8080--> nodes (private /24 subnets, 2 zones, Spot) --> Cilium Gateway --> Services
                                                                  \-- 2 NAT gateways (one per zone) for everything outbound
```

| Path | What |
|---|---|
| `bootstrap/` | Run once: the S3 bucket for remote state (versioned, encrypted, TLS-only, native locking). |
| `envs/platform/` | The stack: composes the modules below. This is where you run `plan` and `apply`. |
| `modules/network` | VPC, public and private /24 subnets per zone, one NAT gateway per zone. |
| `modules/eks-cluster` | The EKS control plane. No add-ons, no nodes. |
| `modules/cilium` | Gateway API CRDs and Cilium (overlay, kube-proxy replacement, Gateway API on the host network). |
| `modules/eks-nodes` | Spot managed node group, CoreDNS and the EBS CSI driver. |
| `modules/alb` | The ALB, its target group and the security group rules, attached to the node group. |
| `modules/secrets-access` | Read-only IAM role for the External Secrets Operator on `/platform-demo/*` in Parameter Store. |
| `docs/` | Architecture, the ALB/Gateway contract, operations (rendered in the developer portal). |

## What you need to provide

1. **AWS access** to one account, with permissions to create VPCs, EKS, IAM roles, KMS keys, load balancers and S3 buckets (an
   administrator role for the first build). Log in with SSO: `aws configure sso`, `aws sso login --profile <name>`, `export AWS_PROFILE=<name>`.
2. **Your public IP** (`curl -s https://checkip.amazonaws.com`) as a `/32`: it is the only address allowed to reach the Kubernetes API and the ALB.
3. **On your machine:** `terraform` >= 1.10 (tested with 1.16.6), the **AWS CLI v2** (Terraform's Helm/kubectl providers authenticate with `aws eks get-token`), and `kubectl`.

Credentials never go into this repository (it is public): they live in `~/.aws/credentials`, outside it (docs/operations.md). Secrets such as
the GitHub OAuth App's are typed once into Parameter Store (docs/secrets.md).

## Build it (from the pipeline, or by hand)

The pipeline (`docs/pipeline.md`) does all of this from GitHub Actions: **Bootstrap** once, then **Deploy** (approval), **Destroy** when you want the cost to stop.
By hand:

```bash
# 1. State bucket (once)
cd bootstrap && terraform init && terraform apply
terraform output -raw backend_hcl > ../envs/platform/backend.hcl

# 2. The platform
cd ../envs/platform
cp terraform.tfvars.example terraform.tfvars        # put your address in it
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan
terraform apply tfplan                              # about 20 minutes

# 3. Use it
$(terraform output -raw kubeconfig_command)
kubectl get nodes
terraform output alb_url
```

The ALB answers `503` until a Gateway listens on port 8080 (docs/alb-and-gateway.md).

## Destroy it

`terraform destroy` removes everything it created. Two things it cannot see are anything you or Argo CD created *in* the cluster that
lives outside it, in particular EBS volumes behind PersistentVolumeClaims. Delete the workloads (and their PVCs) first, then check
(docs/operations.md, "Destroy").

## Decisions

- **Registry modules for the commodity parts** (VPC, EKS) pinned to exact versions; local modules for composition and for what is ours (ALB).
- **Cilium is installed by Terraform** because nodes do not become Ready without a CNI and Argo CD needs nodes. Everything after that is GitOps.
- **No AWS VPC CNI and no kube-proxy.** Pods use an overlay (VXLAN, 10.244.0.0/16), so the VPC only holds nodes and load balancers.
- **Spot nodes, 4 vCPU / 16 GiB**, six interchangeable instance types for availability.
- **No domain yet:** the ALB listens on HTTP/80 and is reachable from your address only. Add a domain, an ACM certificate and an HTTPS listener later.
