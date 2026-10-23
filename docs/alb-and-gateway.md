# The ALB and the Gateway

The requirement: every AWS resource must be managed by Terraform, so nobody has to clean up load balancers in the console. A Gateway API
`Gateway` on EKS normally makes a *controller* create a load balancer. Here it does not, by design:

```text
Terraform:   ALB :443 (TLS ends here, ACM certificate; :80 redirects)  ->  target group (instances, :8080)  ->  Auto Scaling group of the nodes     (security group rules included)
Kubernetes:  Cilium Envoy listens on :8080 on every node (hostNetwork)  ->  Gateway / HTTPRoute  ->  Services
```

- Cilium runs the Gateway API in **host-network mode**: the listener ports are bound on the nodes themselves, and Cilium creates no
  Service of type `LoadBalancer`. No cloud controller has anything to provision.
- The ALB, its listener, its target group, the security groups and the attachment to the nodes' Auto Scaling group are all in
  `modules/alb`. Replaced Spot nodes are registered and deregistered by the Auto Scaling group.
- Targets are **instances**, not pods: with Cilium as an overlay, pod addresses are not routable in the VPC.

## What the Gateway has to do

Listen on the port Terraform forwards to: `gateway_port`, 8080 by default (ports below 1024 need privileges Cilium's Envoy does not
have; each Gateway needs its own port). In the Helm repository's `platform-gateway` chart that is `listeners.http: 8080`.

The target group's health check accepts any answer below 500 (Envoy answers 404 where no route matches). Until a Gateway exists nothing
listens on 8080, the targets are unhealthy and the ALB answers `503`.

## Domain and TLS

- The ALB serves **HTTPS** on 443 with the ACM certificate for `platform-demo.click` and `*.platform-demo.click` (`stacks/foundation`); port 80 only
  redirects to HTTPS. Both ports admit only `alb_allowed_cidrs`. TLS ends at the ALB; from there to the nodes it is plain HTTP inside the VPC,
  so the Cilium Gateway needs only an **HTTP** listener on `gateway_port` (no certificate Secret in the cluster).
- Every UI has a host name (`argocd.`, `backstage.`, `grafana.`, `dex.`, `hubble.`, `shop.platform-demo.click`): an alias record in the
  domain's hosted zone pointing at the ALB (`modules/dns`). The platform's routes are host-based, so they match.
- The hosted zone and the certificate are looked up, never created by the platform stack, so `terraform destroy` of the platform leaves
  the domain, the zone ($0.50 a month) and the certificate (free) alone.
- The `platform-gateway` chart still always renders an HTTPS listener with a certificate Secret; for this environment that listener
  has to be optional (TLS is the ALB's job).

## Guarding against load balancers made behind Terraform's back

Anyone can still create a Service of type `LoadBalancer` in the cluster, and EKS would then create a Classic Load Balancer for it, which
Terraform does not know about and which blocks `terraform destroy` of the VPC. A Kyverno policy that denies Services of type
`LoadBalancer` in every namespace closes this; see the Helm repository's policies.

## Pods reach the platform's own host names through the ALB

Argo CD and Backstage talk to Dex at its public address, `https://dex.<domain>`. From a pod that goes out through a NAT gateway and back in through the ALB, so the ALB's security group also admits the NAT gateways' public addresses on port 443 (`internal_cidrs` of `modules/alb`, filled from `module.network.nat_public_ips`), not only your own address. Without that, single sign-on cannot work.
