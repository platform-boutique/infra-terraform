#!/usr/bin/env bash
# Runs after the platform was destroyed (whatever its result): lists what is still in the account. Informational: it warns and writes
# to the run page, it does not fail. Everything of the platform stack carries the tag Stack=platform; the volumes the EBS CSI driver
# creates for PersistentVolumeClaims are not Terraform's and carry their own tag.
set -uo pipefail

summary="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
left=0
{
  echo '### What is still in the account after the destroy'
  echo

  tagged="$(aws resourcegroupstaggingapi get-resources --tag-filters Key=Stack,Values=platform --query 'ResourceTagMappingList[].ResourceARN' --output text 2>/dev/null | tr '\t' '\n' | sed '/^$/d')"
  if [ -n "$tagged" ]; then
    left=1
    echo 'Resources still tagged Stack=platform (some disappear a few minutes after their deletion):'; echo '```'; echo "$tagged"; echo '```'
  else
    echo '- nothing tagged Stack=platform'
  fi

  vols="$(aws ec2 describe-volumes --filters Name=tag:ebs.csi.aws.com/cluster,Values=true --query 'Volumes[].[VolumeId,State,Size]' --output text 2>/dev/null)"
  if [ -n "$vols" ]; then
    left=1
    echo 'EBS volumes created by the EBS CSI driver (volume, state, GiB); delete with scripts/delete-leftover-volumes.sh:'; echo '```'; echo "$vols"; echo '```'
  else
    echo '- no EBS volumes from the EBS CSI driver'
  fi

  for kind in elb elbv2; do
    names="$(aws "$kind" describe-load-balancers --query 'LoadBalancerDescriptions[].LoadBalancerName || LoadBalancers[].LoadBalancerName' --output text 2>/dev/null)"
    [ "$names" = "None" ] && names=""
    if [ -n "$names" ]; then left=1; echo "- load balancers ($kind): $names"; else echo "- no load balancers ($kind)"; fi
  done
} >> "$summary"

[ "$left" -eq 0 ] || echo "::warning::Something of the platform is still in the account. See the run page."
exit 0
