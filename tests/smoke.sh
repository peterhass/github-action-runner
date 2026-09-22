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
grep -Fq 'claimName: nix-cache' arc-runner-values.yaml
grep -Fq 'ACTIONS_RUNNER_HOOK_JOB_STARTED' arc-runner-values.yaml
grep -Fq 'ACTIONS_RUNNER_HOOK_JOB_COMPLETED' arc-runner-values.yaml
grep -Fq 'storage: 100Gi' nix-cache.yaml
grep -Fq 'extra-substituters = http://nix-cache.arc-runners.svc.cluster.local?trusted=true&priority=10' nix-cache.yaml
grep -Fq "nix copy --all --to 'file:///nix-cache?compression=zstd&compression-level=1'" nix-cache.yaml
grep -Fq 'systemd-inhibit' github-actions-runner
grep -Fq 'gdbus monitor --system' github-actions-runner
grep -Fq 'PrepareForSleep (false,' github-actions-runner
grep -Fq 'restart k3s-rootless.service' github-actions-runner
grep -Fq -- '--watch' github-actions-runner
grep -Fq -- '--output-watch-events' github-actions-runner
grep -Fq 'declare -A active_pods' github-actions-runner
grep -Fq -- '--what=idle' github-actions-runner
grep -Fq -- '--mode=block' github-actions-runner
grep -Fq 'actions.github.com/scale-set-name' github-actions-runner
grep -Fq 'github-actions-resume.service' Makefile
grep -Fq 'github-actions-sleep-inhibit.service' Makefile
grep -Fq 'github-actions-runner resume-watch' github-actions-resume.service
grep -Fq 'github-actions-runner sleep-inhibit' github-actions-sleep-inhibit.service
! grep -Eq '^[[:space:]]+cpu:' arc-runner-values.yaml || [[ "$(grep -Ec '^[[:space:]]+cpu: 100m$' arc-runner-values.yaml)" == 1 ]]
! grep -Fq 'podman' Makefile
