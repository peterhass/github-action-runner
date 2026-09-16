# GitHub Actions Runner

A small, rootless Podman Quadlet for running concurrent GitHub Actions jobs as the current user on an AMD64 Linux system. It creates one runner per physical CPU core, packages the official GitHub Actions runner and GitHub's official Docker container-hooks bundle, and uses the rootless Podman API instead of Docker or nested Podman.

## Prerequisites

Install the system-wide packages and enable lingering once. These are the only commands that require administrator access:

```bash
sudo apt install podman uidmap passt slirp4netns fuse-overlayfs curl unzip python3 util-linux
sudo loginctl enable-linger "$USER"
```

Podman 5.4.2 or newer is required for the build Quadlet.

The account also needs subordinate UID and GID ranges in `/etc/subuid` and `/etc/subgid`; the distribution normally creates these when `uidmap` and Podman are installed.

## Install

Create a repository or organization runner in GitHub, then copy its short-lived registration token. Install as the user who will run CI:

```bash
git clone <repo-url>
cd github-actions-runner
make install
```

`make install` detects the number of physical CPU cores with `lscpu`, installs the build and templated container Quadlets plus one runner instance per core, enables the rootless `podman.socket`, builds the local image through `github-actions-runner-build.service`, prompts once for the GitHub URL and token, registers the runners, and starts them. Quadlet applies each instance's `[Install]` section during `daemon-reload`, because generated services cannot be enabled directly with `systemctl enable`. The token is read without terminal echo, passed to each configuration process over standard input, and is never printed or stored.

Installation is idempotent. Registrations live in numbered directories such as `~/.local/share/github-actions-runner/state-1`; another `make install` only registers missing runners. An existing single-runner installation is reused as `state-1` through a compatibility symlink and mount without re-registering it. The detected runner count is stored in `~/.local/share/github-actions-runner/runner-count` so every management command operates on the same set of instances.

## Commands

```text
make status        Show the user service status
make logs          Follow the user service journal
make restart       Restart the runner
make disable       Disable and stop the runner
make update-hooks  Rebuild with the latest official hooks and restart
make uninstall     Unregister from GitHub and remove all local state
```

`make uninstall` asks for a GitHub runner removal token when the runner is registered. It only deletes the persisted state after unregistration succeeds.

`make disable` stops and masks the generated runner service. A later `make install` unmasks and starts it again without creating another GitHub registration.

The installed `github-actions-runner` command also provides `configure`, `status`, `logs`, `update-hooks`, and `unregister` directly.

## Workflows

Every job sent to this runner must define `container:`. `ACTIONS_RUNNER_REQUIRE_JOB_CONTAINER=true` rejects jobs that do not. For example:

```yaml
jobs:
  test:
    runs-on: self-hosted
    container: ubuntu:24.04
    steps:
      - uses: actions/checkout@v4
      - run: ./test.sh
```

The runner uses GitHub's official Docker hooks with a compatibility command that talks to the mounted rootless Podman socket. The command translates runner-container paths to their corresponding host paths and removes the Docker socket mount that the GitHub runner automatically requests for job containers. Job and service containers are therefore created by the current user's host Podman service. There is no Docker daemon, privileged runner container, or nested Podman.

Never mount the Podman socket directly into workflow job containers. Socket access is equivalent to arbitrary code execution as the host user and is intentionally limited to the runner container.

Use this runner only for trusted repositories and trusted workflows. A workflow can control containers through the runner and can modify the persistent work directory.

## Resources

The generated Quadlet services and socket-activated `podman.service` run in `github-actions.slice`. All runners and their job and service containers consequently share a hard 1 GiB memory limit. On machines with many physical cores, increase `MemoryMax` in `github-actions.slice` if the workloads need more memory.

There is no CPU quota. When the machine is idle, CI may use all CPU cores. Under CPU or I/O contention, its low CPU and I/O weights, idle I/O scheduling class, and high nice value make it lose strongly to normal workloads.

## Files

- Runner state and workspaces: `~/.local/share/github-actions-runner/state-N`
- Detected runner count: `~/.local/share/github-actions-runner/runner-count`
- Installed image sources: `~/.local/share/github-actions-runner/image`
- Build Quadlet: `~/.config/containers/systemd/github-actions-runner.build`
- Quadlet template: `~/.config/containers/systemd/github-actions-runner@.container`
- Shared slice: `~/.config/systemd/user/github-actions.slice`
- Podman drop-in: `~/.config/systemd/user/podman.service.d/github-actions.conf`

Each state directory is mounted at `/runner` and at its unchanged host path inside its runner. The latter allows the host Podman API to resolve workspace bind mounts requested by the hooks. The rootless socket is mounted at `/run/podman/podman.sock`; it is not exposed to job containers.
