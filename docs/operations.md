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
3. Actions -> **Deploy**, read the plan on the run page, approve. About 20 minutes: network 2, control plane 10, nodes 5, add-ons 3.

Order of creation: network, control plane, Gateway API CRDs, Cilium (with SPIRE and WireGuard), nodes (they become Ready because Cilium runs
on them), CoreDNS, EBS CSI, the gp3 StorageClass, Argo CD with the root Application, ALB, DNS. If the node group fails to become active, look
at Cilium first: `kubectl -n kube-system get pods -l k8s-app=cilium` and `kubectl -n kube-system logs ds/cilium`. A node group that stays
`CREATING` with Cilium pods crash-looping on `wireguard` means the kernel lacks WireGuard: set `cilium_encryption_enabled = false`
(see [Architecture](architecture.md#risks-of-the-first-deploy-with-these-settings)).

### What a freshly built cluster looks like

Terraform is done after about 20 minutes, but the cluster is not: Git still has to deploy everything else.

| Minutes after the apply | What you see |
|---|---|
| 0 | `argocd` namespace with Argo CD running, Application `platform-root` appears; `cilium-spire` has the SPIRE server and agents running; the PVC of the SPIRE server is `Bound` to a gp3 volume |
| 1-3 | `platform-root` syncs the projects, the ApplicationSets and the Application `argocd` (Argo CD re-applies its own full configuration; a short restart of its pods is normal) |
| 3-10 | the post-sync Job restarts Cilium (agents and operator roll one after the other: pods keep their connections, new connections wait a moment), then Kyverno, the External Secrets Operator, the Gateway and the routes arrive |
| until then | `https://argocd.platform-demo.click` answers `503` from the ALB (no Gateway yet, all targets unhealthy), and the Dex sign-in does not work until the OAuth App secrets in Parameter Store have been turned into Secrets by the operator |

Watch it with `kubectl -n argocd get applications` (or `argocd app list --core`). To check mutual authentication after the restart:
`kubectl -n kube-system exec ds/cilium -- cilium-dbg status | grep -i -A3 'Encryption\|Authentication'` shows WireGuard and the SPIRE
connection; `kubectl -n cilium-spire get pods,pvc` shows the SPIRE server and its volume.

### Getting into Argo CD

There is no local account, so nobody has a password. Terraform's bootstrap install disables `admin` just as Git does
(`argocd_admin_enabled = false`); the least risky option, because no credential ever exists that could leak or be forgotten.

1. **Normal**: `https://argocd.platform-demo.click` -> "Log in via Dex" -> GitHub. Members of `platform-boutique:maintainers` administer.
   This works when the Gateway, Dex and the External Secrets Operator are up and the secrets in [Secrets](secrets.md) exist.
2. **Break-glass, no Dex, no password**: Argo CD's CLI in core mode uses your own cluster-admin identity against the Kubernetes API:

   ```bash
   $(terraform output -raw kubeconfig_command)
   kubectl config set-context --current --namespace=argocd
   argocd app list --core
   argocd app sync platform-root --core        # or: kubectl -n argocd annotate application platform-root argocd.argoproj.io/refresh=hard --overwrite
   ```

   Needs your IAM user in `admin_user_names` (or the apply role). Nothing is exposed and nothing is changed in the cluster to do it.
3. **Only if you really need the UI before Dex works**: set `argocd_admin_enabled = true` *before the first Deploy*. The bootstrap install then
   keeps the admin account until Git switches it off (a few minutes) and `argocd-initial-admin-secret` holds the password; delete that Secret
   afterwards. The setting is ignored once the release exists (the release is bootstrap-only), and Git's configuration wins anyway.
   `terraform output argocd_initial_access` repeats this.

Argo CD is never exposed with a LoadBalancer or an Ingress; the only way in from outside is the ALB and the Gateway.

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
- **Argo CD itself, or anything Git deploys:** change the Helm repository, not Terraform. The Argo CD release of Terraform is bootstrap-only
  (`ignore_changes` on its values and version), so `argocd_chart_version` is only read on a new cluster; keep it equal to the version in
  `gitops/apps/application-argocd.yaml`. Where the root Application points (`gitops_repo_url`, `gitops_revision`, `gitops_path`) is Terraform's.
- **Turning off WireGuard / SPIRE:** `cilium_encryption_enabled`, `cilium_node_encryption_enabled`, `cilium_mutual_authentication_enabled`
  in the tfvars. Cilium's pods roll; with encryption on a running cluster expect a short interruption of cross-node traffic.
- **Providers:** Dependabot proposes updates to the lock files; the exact versions are in each stack's `versions.tf`.

## Destroy

Actions -> **Destroy** (reason, type `destroy platform-demo`), read the list on the run page, approve.
The workflow empties the cluster first (`scripts/destroy-prepare.sh`), destroys, and lists what is left on the run page. Emptying means,
in this order: the root Application and the self-managing `argocd` Application lose their finalizers (so Argo CD does not prune itself),
the ApplicationSets and then all Applications are deleted and Argo CD prunes what it deployed (Kyverno, External Secrets, monitoring,
the shop and their PersistentVolumeClaims); Kyverno's webhooks and stuck External Secrets objects are removed; the SPIRE server is stopped; every
remaining PersistentVolumeClaim is deleted and the script waits for the EBS CSI driver to delete the volumes behind them (the `gp3`
class reclaims with `Delete`); Services of type LoadBalancer, if any, are deleted. Every step has a time limit and falls back to removing
finalizers, so the destroy cannot hang on Argo CD. Then Terraform uninstalls the Argo CD releases and destroys everything else, the RDS
instance included. If the list reports EBS volumes of the EBS CSI driver, run `scripts/delete-leftover-volumes.sh`. The EKS secrets key stays "scheduled for deletion" for 7 days; that is normal and free.
`stacks/bootstrap` and `stacks/foundation` are never destroyed with the platform.

## Costs while it runs

Two NAT gateways, the EKS control plane, the ALB and two `m`-class Spot instances plus EBS volumes: about $0.35-0.40 per hour. Destroy it
when it is not in use; a rebuild takes about 20 minutes. Always on: the state bucket and keys (cents), the hosted zone ($0.50 a month).
