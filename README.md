# GitHub Actions Runner

A small, rootless K3s + GitHub Actions Runner Controller (ARC) setup for an AMD64 Linux workstation. ARC keeps **zero runners while idle** and starts up to six ephemeral runners when GitHub queues work. Every runner can access `/dev/kvm`.

K3s itself runs as the current user through `systemd --user`; root inside runner pods maps into the rootless K3s user namespace, not host root. The K3s service has low CPU/I/O weight but no CPU quota, so CI can use all otherwise-idle CPU and yields under contention.

## Prerequisites

This repository targets current Arch Linux first. Install the host dependencies and enable lingering once:

```sh
sudo pacman -S --needed curl fuse-overlayfs helm
sudo loginctl enable-linger "$USER"
```

Install the K3s binary without installing its rootful system service:

```sh
curl -fL -o /tmp/k3s https://github.com/k3s-io/k3s/releases/latest/download/k3s
sudo install -m 0755 /tmp/k3s /usr/local/bin/k3s
rm /tmp/k3s
```

Rootless K3s requires pure cgroup v2 and delegated cgroups. Modern systemd systems normally provide this; verify with `stat -fc %T /sys/fs/cgroup` (expected: `cgroup2fs`). The supplied user unit has `Delegate=yes`.

For KVM, make sure the current user can open the device:

```sh
ls -l /dev/kvm
test -r /dev/kvm && test -w /dev/kvm
```

On Arch this normally means membership in the `kvm` group. Log out and back in after changing group membership.

## Install

```sh
git clone <repo-url>
cd github-action-runner
make install
```

`make install` installs and starts the rootless K3s user service, waits for Kubernetes, installs the official ARC controller Helm chart, and prompts for:

1. the GitHub repository or organization URL;
2. a GitHub PAT used by ARC.

The PAT is written only to a Kubernetes Secret in the rootless cluster. For a repository runner, use a token with the permissions required by GitHub's ARC documentation. A GitHub App can be substituted later if desired.

The ARC charts are pinned to `0.14.2` by the helper script. Override temporarily with `ARC_VERSION=...`.

## Scaling

`arc-runner-values.yaml` configures:

```yaml
runnerScaleSetName: self-hosted-k3s
minRunners: 0
maxRunners: 6
```

With no queued work, only K3s, the ARC controller, and its listener remain. Runner pods are ephemeral and scale from zero to six according to assigned jobs.

Use the scale-set name in workflows:

```yaml
jobs:
  test:
    runs-on: self-hosted-k3s
    steps:
      - uses: actions/checkout@v4
      - run: ./test.sh
```

The runner image is intentionally not configured with Docker-in-Docker. Jobs run directly in the ephemeral runner pod. If a workflow uses `container:` or `services:`, add an ARC container mode appropriate for that workflow.

## KVM

All runner pods bind-mount the host `/dev/kvm`. KVM is shareable, so several runners may launch VMs concurrently. The runner container uses UID 0 *inside the rootless K3s user namespace* so device access maps back to the unprivileged host user that owns the K3s process.

Test the exact rootless KVM path before sending jobs to it:

```sh
make kvm-test
```

This creates a temporary pod with the same `/dev/kvm` hostPath and verifies read/write access.

## Resource policy

There is deliberately **no Kubernetes CPU limit**. Each runner requests only `100m` for scheduling, while `k3s-rootless.service` uses low `CPUWeight`, `IOWeight`, and a high nice value. CI can therefore consume the whole CPU when it is idle but loses contention to ordinary work in the same user manager.

Each runner has a 4 GiB memory limit. Six runners can therefore consume at most 24 GiB in their runner containers, leaving headroom on a 32 GiB workstation. Adjust this in `arc-runner-values.yaml` if VM memory requirements differ.

## Commands

```text
make status      Show K3s and Kubernetes pod status
make logs        Follow ARC controller/listener logs
make restart     Restart rootless K3s
make disable     Stop and disable rootless K3s
make configure   Re-run ARC configuration
make kvm-test    Verify /dev/kvm from a rootless pod
make uninstall   Remove ARC and local configuration
make test        Run repository smoke tests
```

K3s logs are available with:

```sh
journalctl --user -u k3s-rootless -f
```

## Files

- Helper command: `~/.local/bin/github-actions-runner`
- Rootless K3s unit: `~/.config/systemd/user/k3s-rootless.service`
- Installed ARC values: `~/.local/share/github-actions-runner/`
- Kubeconfig: `~/.kube/k3s.yaml`

## Security

Use this only for trusted repositories and trusted workflows. Runner jobs receive KVM access and execute as root inside a user namespace whose host identity is the unprivileged K3s user. Rootless K3s reduces the host-root blast radius, but it is not a security boundary against every kernel or KVM vulnerability.

K3s rootless mode is still documented as experimental upstream.
