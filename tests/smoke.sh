#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

test_home="${test_dir}/home"
stub_dir="${test_dir}/bin"
test_log="${test_dir}/commands.log"
mkdir -p "$test_home/.local/share/github-actions-runner/state" "$stub_dir"
touch "$test_home/.local/share/github-actions-runner/state/.runner" "$test_log"

cat > "${stub_dir}/lscpu" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '# Core,Socket' '0,0' '0,0' '1,0' '1,0'
EOF

cat > "${stub_dir}/systemctl" <<'EOF'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "${TEST_LOG:?}"
EOF

cat > "${stub_dir}/podman" <<'EOF'
#!/usr/bin/env bash
printf 'podman %s\n' "$*" >> "${TEST_LOG:?}"
EOF

chmod +x "${stub_dir}/lscpu" "${stub_dir}/systemctl" "${stub_dir}/podman"

export HOME="$test_home"
export TEST_LOG="$test_log"
export PATH="${stub_dir}:${PATH}"

cd "$repo_dir"
bash -n github-actions-runner
if command -v shellcheck >/dev/null 2>&1; then
    shellcheck github-actions-runner
fi

[[ "$(./github-actions-runner physical-core-count)" == 2 ]]
printf 'https://github.com/example/repository\ntest-token\n' | make install

data_dir="${test_home}/.local/share/github-actions-runner"
quadlet_dir="${test_home}/.config/containers/systemd"

[[ "$(< "${data_dir}/runner-count")" == 2 ]]
[[ -L "${data_dir}/state-1" ]]
[[ "$(readlink "${data_dir}/state-1")" == state ]]
[[ -d "${data_dir}/state-2" ]]
[[ -L "${quadlet_dir}/github-actions-runner@1.container" ]]
[[ -L "${quadlet_dir}/github-actions-runner@2.container" ]]
[[ ! -e "${quadlet_dir}/github-actions-runner@3.container" ]]
[[ -f "${quadlet_dir}/github-actions-runner@1.container.d/10-legacy-state.conf" ]]
[[ "$(grep -c '^podman run ' "$test_log")" == 1 ]]

: > "$test_log"
"${test_home}/.local/bin/github-actions-runner" status
grep -Fq 'github-actions-runner@1.service github-actions-runner@2.service' "$test_log"
