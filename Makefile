IMAGE := localhost/github-actions-runner:latest
BIN_DIR := $(HOME)/.local/bin
DATA_DIR := $(HOME)/.local/share/github-actions-runner
IMAGE_DIR := $(DATA_DIR)/image
STATE_DIR := $(DATA_DIR)/state
SYSTEMD_DIR := $(HOME)/.config/systemd/user
QUADLET_DIR := $(HOME)/.config/containers/systemd

.PHONY: install status logs restart disable update-hooks uninstall

install:
	install -D --mode=0755 ./github-actions-runner $(BIN_DIR)/github-actions-runner
	install -D --mode=0755 ./github-actions-runner $(IMAGE_DIR)/github-actions-runner
	install -D --mode=0644 ./Containerfile $(IMAGE_DIR)/Containerfile
	mkdir -p $(STATE_DIR)
	install -D --mode=0644 ./github-actions-runner.build $(QUADLET_DIR)/github-actions-runner.build
	install -D --mode=0644 ./github-actions-runner.container $(QUADLET_DIR)/github-actions-runner.container
	install -D --mode=0644 ./github-actions.slice $(SYSTEMD_DIR)/github-actions.slice
	install -D --mode=0644 ./podman.service.d/github-actions.conf $(SYSTEMD_DIR)/podman.service.d/github-actions.conf
	systemctl --user unmask github-actions-runner.service
	systemctl --user daemon-reload
	systemctl --user enable --now podman.socket
	systemctl --user restart github-actions-runner-build.service
	$(BIN_DIR)/github-actions-runner configure
	systemctl --user start github-actions-runner.service

status:
	$(BIN_DIR)/github-actions-runner status

logs:
	$(BIN_DIR)/github-actions-runner logs

restart:
	systemctl --user restart github-actions-runner.service

disable:
	systemctl --user mask --now github-actions-runner.service

update-hooks:
	$(BIN_DIR)/github-actions-runner update-hooks

uninstall:
	$(BIN_DIR)/github-actions-runner unregister
	-systemctl --user stop github-actions-runner.service
	-systemctl --user unmask github-actions-runner.service
	-systemctl --user stop github-actions-runner-build.service
	rm -f $(QUADLET_DIR)/github-actions-runner.build
	rm -f $(QUADLET_DIR)/github-actions-runner.container
	rm -f $(SYSTEMD_DIR)/github-actions.slice
	rm -f $(SYSTEMD_DIR)/podman.service.d/github-actions.conf
	rmdir --ignore-fail-on-non-empty $(SYSTEMD_DIR)/podman.service.d
	rm -f $(BIN_DIR)/github-actions-runner
	rm -rf $(DATA_DIR)
	-podman image rm $(IMAGE)
	systemctl --user daemon-reload
