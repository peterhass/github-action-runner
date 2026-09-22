BIN_DIR := $(HOME)/.local/bin
DATA_DIR := $(HOME)/.local/share/github-actions-runner
SYSTEMD_DIR := $(HOME)/.config/systemd/user

.PHONY: install configure status logs restart disable kvm-test uninstall test

install:
	command -v k3s >/dev/null || { echo 'k3s is required; see README.md' >&2; exit 1; }
	command -v helm >/dev/null || { echo 'helm is required; see README.md' >&2; exit 1; }
	command -v python3 >/dev/null || { echo 'python3 is required; see README.md' >&2; exit 1; }
	command -v systemd-inhibit >/dev/null || { echo 'systemd-inhibit is required; see README.md' >&2; exit 1; }
	command -v gdbus >/dev/null || { echo 'gdbus is required; see README.md' >&2; exit 1; }
	install -D --mode=0755 ./github-actions-runner $(BIN_DIR)/github-actions-runner
	install -D --mode=0644 ./k3s-rootless.service $(SYSTEMD_DIR)/k3s-rootless.service
	install -D --mode=0644 ./github-actions-resume.service $(SYSTEMD_DIR)/github-actions-resume.service
	install -D --mode=0644 ./github-actions-sleep-inhibit.service $(SYSTEMD_DIR)/github-actions-sleep-inhibit.service
	install -D --mode=0644 ./arc-controller-values.yaml $(DATA_DIR)/arc-controller-values.yaml
	install -D --mode=0644 ./arc-runner-values.yaml $(DATA_DIR)/arc-runner-values.yaml
	install -D --mode=0644 ./nix-cache.yaml $(DATA_DIR)/nix-cache.yaml
	systemctl --user daemon-reload
	systemctl --user enable --now k3s-rootless.service
	systemctl --user enable --now github-actions-resume.service
	systemctl --user enable --now github-actions-sleep-inhibit.service
	$(BIN_DIR)/github-actions-runner wait
	$(BIN_DIR)/github-actions-runner install

configure:
	$(BIN_DIR)/github-actions-runner configure

status:
	$(BIN_DIR)/github-actions-runner status

logs:
	$(BIN_DIR)/github-actions-runner logs

restart:
	systemctl --user restart k3s-rootless.service

# Stops K3s and its sleep/resume helpers. ARC runner pods disappear with the cluster.
disable:
	systemctl --user disable --now github-actions-resume.service
	systemctl --user disable --now github-actions-sleep-inhibit.service
	systemctl --user disable --now k3s-rootless.service

kvm-test:
	$(BIN_DIR)/github-actions-runner kvm-test

uninstall:
	systemctl --user disable --now github-actions-resume.service 2>/dev/null || true
	systemctl --user disable --now github-actions-sleep-inhibit.service 2>/dev/null || true
	$(BIN_DIR)/github-actions-runner uninstall
	rm -f $(BIN_DIR)/github-actions-runner
	rm -f $(SYSTEMD_DIR)/k3s-rootless.service
	rm -f $(SYSTEMD_DIR)/github-actions-resume.service
	rm -f $(SYSTEMD_DIR)/github-actions-sleep-inhibit.service
	rm -rf $(DATA_DIR)
	systemctl --user daemon-reload

test:
	./tests/smoke.sh
