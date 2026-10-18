# Operations

## Credentials

Terraform, the AWS CLI and the providers read the standard credential chain, so nothing in this repository holds a key: put the
access key of an administrator in `~/.aws/credentials` (profile `default`, or any name plus `export AWS_PROFILE=<name>`) and the region
in `~/.aws/config`. Never put it in a `.tf` or `.tfvars` file: the repository is public. Use it only for `scripts/bootstrap.sh` and local
work; the pipeline uses its OIDC roles. Turn on MFA for that user, or use IAM Identity Center (SSO).

## First build

1. `scripts/bootstrap.sh` (once): the state bucket, the OIDC provider and the two roles. It shows the plan and asks. Then set the
   repository variables it prints ([Pipeline](pipeline.md)).
2. Actions -> **Foundation** (the certificate; needs the registered domain's hosted zone).
3. Actions -> **Deploy plan**, then **Deploy apply**. About 20 minutes: network 2, control plane 10, nodes 5, add-ons 3.

Order of creation: network, control plane, Gateway API CRDs, Cilium, nodes (they become Ready because Cilium runs on them), CoreDNS,
EBS CSI, ALB, DNS. If the node group fails to become active, look at Cilium first:
`kubectl -n kube-system get pods -l k8s-app=cilium` and `kubectl -n kube-system logs ds/cilium`.

## Working locally

```bash
cd stacks/platform
terraform init -backend-config="bucket=$(../../scripts/state-bucket.sh)" -backend-config="region=us-east-1"
echo 'alb_allowed_cidrs = ["203.0.113.7/32"]' > local.auto.tfvars     # your address: curl -s https://checkip.amazonaws.com
terraform plan
$(terraform output -raw kubeconfig_command) && kubectl get nodes
```

Your user gets cluster-admin if it is listed in `admin_user_names` in `platform.auto.tfvars`.

## Changing things

- **Your IP changed:** update the repository variable `ALB_ALLOWED_CIDRS` (and your `local.auto.tfvars`), then plan and apply.
- **More nodes / other instance types / Kubernetes version:** edit `stacks/platform/platform.auto.tfvars`, open a pull request. Keep the
  instance types at 4 vCPU / 16 GiB; upgrade Kubernetes one minor version at a time, and only to a version Cilium documents.
- **Gateway API version:** `scripts/update-gateway-api-crds.sh vX.Y.Z`, then put the printed version and checksum in the tfvars.
- **Providers:** Dependabot proposes updates to the lock files; the exact versions are in each stack's `versions.tf`.

## Destroy

Actions -> **Destroy plan** (reason, type `destroy platform-demo`), read the list, then **Destroy apply** with the plan id and approve.
The workflow empties the cluster first, destroys, and lists what is left on the run page. If it reports EBS volumes of the EBS CSI driver,
run `scripts/delete-leftover-volumes.sh`. The EKS secrets key stays "scheduled for deletion" for 7 days; that is normal and free.
`stacks/bootstrap` and `stacks/foundation` are never destroyed with the platform.

## Costs while it runs

Two NAT gateways, the EKS control plane, the ALB and two `m`-class Spot instances plus EBS volumes: about $0.35-0.40 per hour. Destroy it
when it is not in use; a rebuild takes about 20 minutes. Always on: the state bucket and keys (cents), the hosted zone ($0.50 a month).
