# Operations

## Credentials

Terraform, the AWS CLI and the providers read the standard credential chain, so nothing in this repository holds a key: put the
access key of the IAM user in `~/.aws/credentials` (profile `default`, or any name plus `export AWS_PROFILE=<name>`) and the region in
`~/.aws/config`. Never put it in a `.tf`, `.tfvars` or `backend.hcl` file: the repository is public (and AWS quarantines keys it finds on GitHub).
Prefer IAM Identity Center (SSO) over long-lived keys when the account has it; delete test keys when you are done.

## First build

Order: **Bootstrap** (state bucket), **Foundation** (certificate for the domain; needs the registered domain's hosted zone), then **Deploy**.

See the README: `bootstrap/` once (state bucket), then `envs/platform/`: `init -backend-config=backend.hcl`, `plan`, `apply`.
Allow about 20 minutes: network 2, control plane 10, nodes 5, add-ons 3.

Order of creation: network, control plane, Gateway API CRDs, Cilium, nodes (they become Ready because Cilium runs on them), CoreDNS,
EBS CSI, ALB. If the node group fails to become active, look at Cilium first:
`kubectl -n kube-system get pods -l k8s-app=cilium` and `kubectl -n kube-system logs ds/cilium`.

## Changing things

- **Your IP changed:** update `api_allowed_cidrs` and `alb_allowed_cidrs`, `apply`.
- **More nodes:** `node_count`. **Other instance types:** `node_instance_types` (keep them at 4 vCPU / 16 GiB).
- **Kubernetes upgrade:** change `kubernetes_version` one minor version at a time; `plan` first. EKS stays on standard support
  (`upgrade_policy`), so a version that leaves standard support must be upgraded before the date.

## Destroy

```bash
# 1. Remove what runs in the cluster, so that nothing outside Terraform survives it: delete the Argo CD root Application (prune), then
kubectl get pvc -A          # must be empty
kubectl get svc -A | grep LoadBalancer   # must be empty

# 2. Destroy
terraform destroy

# 3. Check for leftovers
aws ec2 describe-volumes --filters Name=tag:ebs.csi.aws.com/cluster,Values=true --query 'Volumes[].VolumeId'
aws elb describe-load-balancers --query 'LoadBalancerDescriptions[].LoadBalancerName'
```

Volumes the EBS CSI driver creates for PersistentVolumeClaims carry the tag `ebs.csi.aws.com/cluster=true`, which is what this check looks for. If step 3 finds any, they were
created after step 1 or by something that bypassed the guard: delete them with `aws ec2 delete-volume`.
`bootstrap/` is never destroyed with the platform: its bucket has `prevent_destroy` and holds the state.

## Costs while it runs

Two NAT gateways, the EKS control plane, the ALB and two `m`-class Spot instances plus EBS volumes. Destroy it when it is not in use;
a rebuild takes about 20 minutes and the state bucket costs cents.
