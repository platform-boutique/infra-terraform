# The platform's front door, owned by Terraform.
#
#   internet --443 (80 redirects)--> ALB (public subnets, TLS ends here) --gateway_port--> every node (Cilium Envoy, hostNetwork) --> HTTPRoutes --> Services
#
# Nothing in Kubernetes creates or changes anything here. The Gateway only has to listen on gateway_port (a fixed number), so no
# controller creates load balancers, target groups or security group rules behind Terraform's back, and `terraform destroy`
# removes everything. The ALB's target group is attached to the nodes' Auto Scaling group, so nodes that Spot replaces are registered
# and deregistered automatically.
#
# Targets are instances, not pods: with Cilium as an overlay the pod addresses are not routable in the VPC.

resource "aws_security_group" "alb" {
  name_prefix = "${var.name}-alb-"
  description = "ALB of ${var.name}"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-alb" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  for_each = toset(var.allowed_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "HTTP (redirected to HTTPS) from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  for_each = toset(var.allowed_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# The platform itself, through the NAT gateways (see var.internal_cidrs). count, not for_each: the addresses are known only after apply.
resource "aws_vpc_security_group_ingress_rule" "https_internal" {
  count = length(var.internal_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from the platform's own NAT gateway ${count.index}"
  cidr_ipv4         = var.internal_cidrs[count.index]
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# The ALB may only talk to the nodes, on the gateway port.
resource "aws_vpc_security_group_egress_rule" "to_nodes" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Gateway port on the nodes"
  referenced_security_group_id = var.node_security_group_id
  from_port                    = var.gateway_port
  to_port                      = var.gateway_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "nodes_from_alb" {
  security_group_id            = var.node_security_group_id
  description                  = "Gateway port from the ALB"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.gateway_port
  to_port                      = var.gateway_port
  ip_protocol                  = "tcp"
}

resource "aws_lb" "this" {
  #checkov:skip=CKV_AWS_91:No access-log bucket in this test environment (it would be one more resource to keep and destroy); add one with the domain and a long-lived platform.
  #checkov:skip=CKV_AWS_150:Created and destroyed on demand to save cost; deletion_protection is a variable to switch on once the platform is long-lived.
  #checkov:skip=CKV2_AWS_28:Reachable only from allowed_cidrs (the maintainer's address); a WAF is not worth its cost in a test environment.
  name               = var.name
  load_balancer_type = "application"
  internal           = false
  ip_address_type    = "ipv4"

  security_groups = [aws_security_group.alb.id]
  subnets         = var.subnet_ids

  drop_invalid_header_fields = true
  enable_deletion_protection = var.deletion_protection

  tags = var.tags
}

resource "aws_lb_target_group" "gateway" {
  #checkov:skip=CKV_AWS_378:HTTP between the ALB and the nodes inside the VPC: TLS ends at the ALB, and the Cilium Gateway listens on plain HTTP.
  name        = "${var.name}-gw"
  vpc_id      = var.vpc_id
  target_type = "instance"
  protocol    = "HTTP"
  port        = var.gateway_port

  deregistration_delay = 30

  # Envoy answers every request, with 404 where no route matches: any response below 500 means the node is serving. 5xx or no
  # answer (nothing listens yet, for example before the first Gateway exists) means it is not.
  health_check {
    protocol            = "HTTP"
    port                = "traffic-port"
    path                = "/"
    matcher             = "200-499"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = var.tags
}

# Port 80 only redirects: nothing is served in clear text.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = var.tags
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gateway.arn
  }

  tags = var.tags
}

resource "aws_autoscaling_attachment" "gateway" {
  #checkov:skip=CKV2_AWS_15:The Auto Scaling group belongs to the EKS managed node group, which sets its own health checks; it cannot be changed from here.
  for_each = var.autoscaling_group_names

  autoscaling_group_name = each.value
  lb_target_group_arn    = aws_lb_target_group.gateway.arn
}
