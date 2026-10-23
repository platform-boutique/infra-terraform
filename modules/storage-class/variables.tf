variable "name" {
  description = "Name of the StorageClass to create (gp3). Charts and the SPIRE server's claim refer to it by this name."
  type        = string
}

variable "make_default" {
  description = "Make it the cluster's default class (claims without storageClassName use it)."
  type        = bool
}

variable "demote_legacy_class" {
  description = "Remove the default flag from EKS's own gp2 class so that this one is the only default. Set false if the cluster has no such class (the step fails when the class is missing)."
  type        = bool
}

variable "legacy_class_name" {
  description = "Name of the class EKS creates as default."
  type        = string
}
