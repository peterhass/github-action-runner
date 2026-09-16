# GitHub Actions Runner

A small, rootless Podman Quadlet for running GitHub Actions jobs as the current user on an AMD64 Linux system. It packages the official GitHub Actions runner and GitHub's official Docker container-hooks bundle, while using the rootless Podman API instead of Docker or nested Podman.

## Prerequisites

Install the system-wide packages and enable lingering once. These are the only commands that require administrator access:

```bash
sudo apt install podman uidmap passt slirp4netns fuse-overlayfs curl unzip python3
sudo loginctl enable-linger "$USER"
```

The account also needs subordinate UID and GID ranges in `/etc/subuid` and `/etc/subgid`; the distribution normally creates these when `uidmap` and Podman are installed.

## Install

Create a repository or organization runner in GitHub, then copy its short-lived registration token. Install as the user who will run CI:

```bash
git clone <repo-url>
cd github-actions-runner
make install
```

`make install` builds the local image, installs the Quadlet and user units, enables the rootless `podman.socket`, prompts for the GitHub URL and token, and starts the runner. The token is read without terminal echo, passed to the configuration process over standard input, and is never printed or stored.

Installation is idempotent. The registration lives in `~/.local/share/github-actions-runner/state`; if its `.runner` file exists, another `make install` does not register a second runner.

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

The runner uses GitHub's official Docker hooks with a compatibility command that talks to the mounted rootless Podman socket. Job and service containers are therefore created by the current user's host Podman service. There is no Docker daemon, privileged runner container, or nested Podman.

Never mount the Podman socket directly into workflow job containers. Socket access is equivalent to arbitrary code execution as the host user and is intentionally limited to the runner container.

Use this runner only for trusted repositories and trusted workflows. A workflow can control containers through the runner and can modify the persistent work directory.

## Resources

The generated Quadlet service and socket-activated `podman.service` run in `github-actions.slice`. The runner and all job and service containers consequently share a hard 1 GiB memory limit.

There is no CPU quota. When the machine is idle, CI may use all CPU cores. Under CPU or I/O contention, its low CPU and I/O weights, idle I/O scheduling class, and high nice value make it lose strongly to normal workloads.

## Files

- Runner state and workspaces: `~/.local/share/github-actions-runner/state`
- Installed image sources: `~/.local/share/github-actions-runner/image`
- Quadlet: `~/.config/containers/systemd/github-actions-runner.container`
- Shared slice: `~/.config/systemd/user/github-actions.slice`
- Podman drop-in: `~/.config/systemd/user/podman.service.d/github-actions.conf`

The state directory is mounted at `/runner` and at its unchanged host path inside the runner. The latter allows the host Podman API to resolve workspace bind mounts requested by the hooks. The rootless socket is mounted at `/run/podman/podman.sock`; it is not exposed to job containers.
