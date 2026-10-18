# infra-terraform

Terraform for the platform-demo AWS environment: a highly available VPC, an EKS cluster with Cilium as an overlay network, two Spot
worker nodes, an ALB that Terraform owns, and HTTPS for the domain `platform-demo.click`. **Every AWS resource is created and destroyed by Terraform; Kubernetes creates none.**

```
internet --:443--> ALB (TLS ends here; port 80 redirects; public /24 subnets, 2 zones) --:8080--> nodes (private /24 subnets, 2 zones, Spot) --> Cilium Gateway --> Services
                                                                  \-- 2 NAT gateways (one per zone) for everything outbound
```

| Path | What |
|---|---|
| `bootstrap/` | Run once: the S3 bucket for remote state (versioned, encrypted, TLS-only, native locking). |
| `envs/foundation/` | What outlives the platform: the ACM certificate for the domain. Applied once; never destroyed with the platform. |
| `envs/platform/` | The stack: composes the modules below. This is where you run `plan` and `apply`. |
| `modules/network` | VPC, public and private /24 subnets per zone, one NAT gateway per zone. |
| `modules/eks-cluster` | The EKS control plane. No add-ons, no nodes. |
| `modules/cilium` | Gateway API CRDs and Cilium (overlay, kube-proxy replacement, Gateway API on the host network). |
| `modules/eks-nodes` | Spot managed node group, CoreDNS and the EBS CSI driver. |
| `modules/alb` | The ALB, its target group and the security group rules, attached to the node group. |
| `modules/certificate` | Public ACM certificate for the domain and `*.domain`, validated through DNS (free with an ALB). |
| `modules/dns` | Alias records `argocd`, `backstage`, `grafana`, `dex`, `hubble`, `shop` under the domain, all pointing at the ALB. |
| `modules/secrets-access` | Read-only IAM role for the External Secrets Operator on `/platform-demo/*` in Parameter Store. |
| `docs/` | Architecture, the ALB/Gateway contract, operations (rendered in the developer portal). |

## What you need to provide

1. **AWS access** to one account, with permissions to create VPCs, EKS, IAM roles, KMS keys, load balancers and S3 buckets (an
   administrator role for the first build). Log in with SSO: `aws configure sso`, `aws sso login --profile <name>`, `export AWS_PROFILE=<name>`.
2. **A registered domain** (Route 53 -> Registered domains, about $3 a year for `.click`) whose hosted zone exists (AWS creates it at registration). Terraform looks the zone up and creates only the records in it.
3. **Your public IP** (`curl -s https://checkip.amazonaws.com`) as a `/32`: it is the only address allowed to reach the Kubernetes API and the ALB.
4. **On your machine (only for working locally):** `terraform` >= 1.10 (tested with 1.16.6), the **AWS CLI v2** (Terraform's Helm/kubectl providers authenticate with `aws eks get-token`), and `kubectl`.

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

The UIs are at `https://argocd.platform-demo.click` and so on (`terraform output urls`). The ALB answers `503` until a Gateway listens on port 8080 (docs/alb-and-gateway.md).

## Destroy it

`terraform destroy` removes everything it created. Two things it cannot see are anything you or Argo CD created *in* the cluster that
lives outside it, in particular EBS volumes behind PersistentVolumeClaims. Delete the workloads (and their PVCs) first, then check
(docs/operations.md, "Destroy").

## Decisions

- **Registry modules for the commodity parts** (VPC, EKS) pinned to exact versions; local modules for composition and for what is ours (ALB).
- **Cilium is installed by Terraform** because nodes do not become Ready without a CNI and Argo CD needs nodes. Everything after that is GitOps.
- **No AWS VPC CNI and no kube-proxy.** Pods use an overlay (VXLAN, 10.244.0.0/16), so the VPC only holds nodes and load balancers.
- **Spot nodes, 4 vCPU / 16 GiB**, six interchangeable instance types for availability.
- **HTTPS with a free certificate:** the ALB terminates TLS with an ACM certificate for `platform-demo.click` and `*.platform-demo.click`; port 80 only redirects. The certificate lives in `envs/foundation`, so a destroy of the platform keeps it. The ALB admits only your address.
