#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_dir"

bash -n github-actions-runner
if command -v shellcheck >/dev/null 2>&1; then
    shellcheck github-actions-runner
fi

grep -Fq -- '--rootless' k3s-rootless.service
grep -Fq 'Delegate=yes' k3s-rootless.service
grep -Fq 'CPUWeight=10' k3s-rootless.service
grep -Fq 'minRunners: 0' arc-runner-values.yaml
grep -Fq 'maxRunners: 6' arc-runner-values.yaml
grep -Fq 'path: /dev/kvm' arc-runner-values.yaml
! grep -Eq '^[[:space:]]+cpu:' arc-runner-values.yaml || [[ "$(grep -Ec '^[[:space:]]+cpu: 100m$' arc-runner-values.yaml)" == 1 ]]
! grep -Fq 'podman' Makefile
