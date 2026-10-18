# One alias record per host name, all pointing at the load balancer. Alias records are free and follow the load balancer's addresses.
# The hosted zone itself is not created here (see stacks/platform): it belongs to the registered domain and outlives every deployment.

resource "aws_route53_record" "host" {
  for_each = toset(var.hostnames)

  zone_id = var.zone_id
  name    = "${each.value}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}
