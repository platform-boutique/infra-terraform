provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "platform-demo"
      ManagedBy = "terraform"
      Stack     = "foundation"
    }
  }
}
