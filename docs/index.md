# Terraform: the AWS environment

A highly available platform foundation in `us-east-1`, zones `a` and `b`:

- **Network:** one VPC (10.0.0.0/16), per zone one public and one private /24 subnet and one NAT gateway.
  Only the load balancer (and the NAT gateways) sit in the public subnets.
- **Cluster:** EKS 1.35 with Cilium as an overlay network (no AWS VPC CNI, no kube-proxy), two Spot nodes with 16 GiB RAM,
  CoreDNS and the EBS CSI driver.
- **Front door:** an ALB, owned by Terraform, forwarding to the Gateway's port on the nodes.

Everything in AWS is a Terraform resource, so `terraform destroy` leaves nothing behind that you would have to delete in the console.
The pages: [Architecture](architecture.md), [The ALB and the Gateway](alb-and-gateway.md), [Operations](operations.md).
