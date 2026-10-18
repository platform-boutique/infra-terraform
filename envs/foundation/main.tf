# What outlives the platform. The platform is built and destroyed to save cost; the certificate for its domain is free, takes minutes to
# validate and has no reason to be thrown away each time, so it lives here, in a stack that the Destroy workflow never touches.
# Apply it once (Actions -> Foundation) after registering the domain, before the first Deploy.

# The hosted zone belongs to the registered domain: AWS created it at registration and pointed the domain's name servers at it. It is looked up,
# never created, so that no apply or destroy can replace it (a new zone would have new name servers).
data "aws_route53_zone" "this" {
  name         = var.domain_name
  private_zone = false
}

module "certificate" {
  source = "../../modules/certificate"

  domain_name = var.domain_name
  zone_id     = data.aws_route53_zone.this.zone_id
}
