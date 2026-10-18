#!/usr/bin/env bash
# Refreshes the vendored Gateway API CRDs (modules/cilium/charts/gateway-api-crds) to a release and prints what to put in
# stacks/platform/platform.auto.tfvars. Usage: scripts/update-gateway-api-crds.sh v1.6.3
set -euo pipefail

version="${1:?usage: $0 <gateway-api version, for example v1.6.3>}"
chart="$(dirname "$0")/../modules/cilium/charts/gateway-api-crds"
file="$chart/templates/standard-install.yaml"

curl -fsSL -o "$file" "https://github.com/kubernetes-sigs/gateway-api/releases/download/${version}/standard-install.yaml"
sed -i -E "s/^version: .*/version: ${version#v}/; s/^appVersion: .*/appVersion: ${version}/" "$chart/Chart.yaml"
echo "Review the diff, then set in stacks/platform/platform.auto.tfvars:"
echo "  gateway_api_version     = \"${version}\""
echo "  gateway_crds_sha256 = \"$(sha256sum "$file" | cut -d' ' -f1)\""
