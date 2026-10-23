# infra-terraform

Terraform for the platform-demo AWS environment: a highly available VPC, an EKS cluster with Cilium as an overlay network, two Spot
worker nodes (with gVisor as a second runtime), a Multi-AZ PostgreSQL database, an ALB that Terraform owns, and HTTPS for `platform-demo.click`. **Every AWS resource is created and destroyed by Terraform; Kubernetes creates none.**

```
internet --:443--> ALB (TLS ends here; port 80 redirects; public /24 subnets, 2 zones) --:8080--> nodes (private /24 subnets, 2 zones, Spot) --> Cilium Gateway --> Services
                                                                  \-- 2 NAT gateways (one per zone) for everything outbound
```

| Path | What |
|---|---|
| `stacks/bootstrap` | What everything stands on, never destroyed: the state bucket and GitHub's OIDC provider with the pipeline's two roles. Applied by a person with `scripts/bootstrap.sh`. |
| `stacks/foundation` | What outlives the platform: the ACM certificate for the domain. |
| `stacks/platform` | The platform: composes the modules below. Built and destroyed through the pipeline. |
| `modules/` | `network`, `eks-cluster`, `cilium`, `eks-nodes`, `alb`, `certificate`, `dns`, `database`, `secrets-access` (each explained in [Architecture](docs/architecture.md)). |
| `scripts/` | `bootstrap.sh`, `state-bucket.sh`, the destroy helpers, `update-gateway-api-crds.sh`. |
| `docs/` | The documentation, rendered in the developer portal. |

All values of the environment are in one committed file per stack (`stacks/<stack>/<stack>.auto.tfvars`). Only your own address goes in
`stacks/platform/local.auto.tfvars`, which Git ignores.

## Quick start

1. **Once, by hand** (an administrator's AWS credentials in `~/.aws/credentials`): `scripts/bootstrap.sh`, then set the repository
   variables it prints.
2. **Actions -> Foundation** (once): the certificate.
3. **Actions -> Deploy**: read the plan on the run page, then approve. About 20 minutes.
4. **Actions -> Destroy** (type the confirmation, read the plan, approve) when the cost should stop.

Details: [Pipeline](docs/pipeline.md) and [Operations](docs/operations.md). Credentials and secrets never go into this repository (it is public).
