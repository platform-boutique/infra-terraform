#!/usr/bin/env bash
# Deletes the EBS volumes the EBS CSI driver created for PersistentVolumeClaims and that no instance uses any more
# (the usual leftover of a destroyed cluster). Lists them first and asks.
set -euo pipefail

ids="$(aws ec2 describe-volumes --filters Name=tag:ebs.csi.aws.com/cluster,Values=true Name=status,Values=available --query 'Volumes[].VolumeId' --output text)"
[ -n "$ids" ] || { echo "No unattached volumes from the EBS CSI driver."; exit 0; }
echo "Unattached volumes: $ids"
read -r -p "Delete them? [type yes] " answer
[ "$answer" = "yes" ] || { echo "Nothing was deleted."; exit 1; }
for v in $ids; do aws ec2 delete-volume --volume-id "$v" && echo "deleted $v"; done
