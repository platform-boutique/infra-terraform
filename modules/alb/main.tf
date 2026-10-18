# The platform's front door, owned by Terraform.
#
#   internet --80--> ALB (public subnets) --gateway_port--> every node (Cilium Envoy, hostNetwork) --> HTTPRoutes --> Services
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
  description       = "HTTP from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = 80
  to_port           = 80
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

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gateway.arn
  }

  tags = var.tags
}

resource "aws_autoscaling_attachment" "gateway" {
  for_each = var.autoscaling_group_names

  autoscaling_group_name = each.value
  lb_target_group_arn    = aws_lb_target_group.gateway.arn
}
