# GitHub Actions Runner

A small, rootless K3s + GitHub Actions Runner Controller (ARC) setup for an AMD64 Linux workstation. ARC keeps **zero runners while idle** and starts up to six ephemeral runners when GitHub queues work. Every runner can access `/dev/kvm`.

K3s itself runs as the current user through `systemd --user`; a companion user service holds an idle inhibitor only while an ARC runner pod is pending or running. This prevents automatic idle sleep during jobs while allowing normal sleep when the runner scale set is idle. Because the watcher is an unprivileged lingering user service, explicit suspend/lid inhibition requires an additional polkit rule; see the note below. A second user service listens for logind's resume signal and restarts rootless K3s after a short delay, recreating ARC's GitHub listener with a fresh network connection. The K3s service has low CPU/I/O weight but no CPU quota, so CI can use all otherwise-idle CPU and yields under contention.

## Prerequisites

This repository targets current Arch Linux first. Install the host dependencies and enable lingering once:

```sh
sudo pacman -S --needed curl fuse-overlayfs glib2 helm
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

`make install` installs and starts the rootless K3s, resume-recovery, and sleep-inhibition user services, waits for Kubernetes, installs the official ARC controller Helm chart, deploys the persistent Nix cache, and prompts for:

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

With no queued work, only K3s, the ARC controller, its listener, and the small Nix cache server remain. Runner pods are ephemeral and scale from zero to six according to assigned jobs. The sleep-inhibition service watches those runner pods, so it releases its lock as soon as the runner scale set returns to zero. The resume-recovery service restarts rootless K3s five seconds after each system resume, causing ARC to create a fresh listener instead of retaining a stale pre-suspend connection.

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

## Nix cache

A shared Nix binary cache is part of the runner installation. K3s provisions a 100 GiB `nix-cache` persistent volume, an nginx pod serves it inside the cluster, and every runner mounts the same cache read/write.

Runner job hooks automatically configure Nix with the in-cluster cache as an additional trusted substituter and `max-jobs = auto`. At the end of a job, if Nix was installed by the workflow, the runner copies its disposable Nix store into the persistent binary cache. Upload is serialized between runners and is best-effort so a cache failure does not turn a successful workflow into a failure.

This intentionally caches the complete Nix store from a Nix-using job, including substituted dependencies. That costs local disk space but makes later ephemeral runners independent of the previous runner's `/nix/store` and avoids repeated downloads/builds. Repositories do not need cache-specific workflow configuration.

The cache is trusted without signatures because it is private to this rootless single-node CI cluster and writable only by its runner pods. Do not expose the `nix-cache` Service outside the cluster.

## KVM

All runner pods bind-mount the host `/dev/kvm`. KVM is shareable, so several runners may launch VMs concurrently. The runner container uses UID 0 *inside the rootless K3s user namespace* so device access maps back to the unprivileged host user that owns the K3s process.

Test the exact rootless KVM path before sending jobs to it:

```sh
make kvm-test
```

This creates a temporary pod with the same `/dev/kvm` hostPath and verifies read/write access.

## Resource policy

There is deliberately **no Kubernetes CPU limit**. Each runner requests only `100m` for scheduling, while `k3s-rootless.service` uses low `CPUWeight`, `IOWeight`, and a high nice value. CI can therefore consume the whole CPU when it is idle but loses contention to ordinary work in the same user manager.

There is deliberately **no per-runner memory limit**. Memory-heavy Nix builds can use available RAM instead of being killed at an arbitrary pod limit. If the host comes under genuine memory pressure, normal Linux/cgroup OOM policy applies to the CI processes.

## Commands

```text
make status      Show K3s, Kubernetes, and Nix cache status
make logs        Follow ARC controller/listener logs
make restart     Restart rootless K3s
make disable     Stop and disable rootless K3s and its sleep/resume helpers
make configure   Re-run ARC and Nix cache configuration
make kvm-test    Verify /dev/kvm from a rootless pod
make uninstall   Remove ARC, the Nix cache, and local configuration
make test        Run repository smoke tests
```

K3s logs are available with:

```sh
journalctl --user -u k3s-rootless -f
```

## Files

- Helper command: `~/.local/bin/github-actions-runner`
- Rootless K3s unit: `~/.config/systemd/user/k3s-rootless.service`
- Resume-recovery unit: `~/.config/systemd/user/github-actions-resume.service`
- Sleep-inhibition unit: `~/.config/systemd/user/github-actions-sleep-inhibit.service`
- Installed ARC/cache configuration: `~/.local/share/github-actions-runner/`
- Kubeconfig: `~/.kube/k3s.yaml`

## Security

Use this only for trusted repositories and trusted workflows. Runner jobs receive KVM access and execute as root inside a user namespace whose host identity is the unprivileged K3s user. Rootless K3s reduces the host-root blast radius, but it is not a security boundary against every kernel or KVM vulnerability.

K3s rootless mode is still documented as experimental upstream.
