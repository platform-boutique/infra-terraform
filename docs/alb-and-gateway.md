# The ALB and the Gateway

The requirement: every AWS resource must be managed by Terraform, so nobody has to clean up load balancers in the console. A Gateway API
`Gateway` on EKS normally makes a *controller* create a load balancer. Here it does not, by design:

```text
Terraform:   ALB :80  ->  target group (instances, :8080)  ->  Auto Scaling group of the nodes     (security group rules included)
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

## Limits of "no domain"

- The ALB serves **HTTP only** on port 80 (an ACM certificate needs a domain), and only to `alb_allowed_cidrs`.
- The platform's routes are **host-based** (`argocd.<domain>`, `backstage.<domain>` ...). Reaching them through the ALB's own DNS name
  does not match any route. Until there is a domain: map the host names to the ALB's addresses in your hosts file
  (`dig +short <alb dns name>`; the addresses change occasionally), or send the `Host` header yourself. With a domain it is one
  Route53 record per name (or a wildcard) pointing at the ALB.
- The `platform-gateway` chart always renders an HTTPS listener with a certificate Secret. Without TLS that listener has to be optional
  for this environment.

## Guarding against load balancers made behind Terraform's back

Anyone can still create a Service of type `LoadBalancer` in the cluster, and EKS would then create a Classic Load Balancer for it, which
Terraform does not know about and which blocks `terraform destroy` of the VPC. A Kyverno policy that denies Services of type
`LoadBalancer` in every namespace closes this; see the Helm repository's policies.
