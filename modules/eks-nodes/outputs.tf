output "autoscaling_group_names" {
  description = "Auto Scaling groups of the node group by node group name (a map, so its keys are known when planning): the ALB module attaches its target group to them."
  value = {
    workers = module.node_group.node_group_autoscaling_group_names[0]
  }
}

output "node_role_arn" {
  description = "IAM role of the nodes."
  value       = module.node_group.iam_role_arn
}
