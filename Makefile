IMAGE := localhost/github-actions-runner:latest
BIN_DIR := $(HOME)/.local/bin
DATA_DIR := $(HOME)/.local/share/github-actions-runner
IMAGE_DIR := $(DATA_DIR)/image
STATE_DIR := $(DATA_DIR)/state
SYSTEMD_DIR := $(HOME)/.config/systemd/user
QUADLET_DIR := $(HOME)/.config/containers/systemd
RUNNER_COUNT := $(shell ./github-actions-runner physical-core-count)
ifeq ($(RUNNER_COUNT),)
$(error Could not determine the number of physical CPU cores)
endif
RUNNER_INSTANCES := $(shell seq 1 $(RUNNER_COUNT))
RUNNER_SERVICES := $(addprefix github-actions-runner@,$(addsuffix .service,$(RUNNER_INSTANCES)))

.PHONY: install status logs restart disable update-hooks uninstall

install:
	-systemctl --user stop github-actions-runner.service
	-systemctl --user stop 'github-actions-runner@*.service'
	install -D --mode=0755 ./github-actions-runner $(BIN_DIR)/github-actions-runner
	install -D --mode=0755 ./github-actions-runner $(IMAGE_DIR)/github-actions-runner
	install -D --mode=0644 ./Containerfile $(IMAGE_DIR)/Containerfile
	if [ -f $(STATE_DIR)/.runner ] && [ ! -e $(DATA_DIR)/state-1 ]; then ln -s state $(DATA_DIR)/state-1; fi
	mkdir -p $(addprefix $(DATA_DIR)/state-,$(RUNNER_INSTANCES))
	printf '%s\n' $(RUNNER_COUNT) > $(DATA_DIR)/runner-count
	install -D --mode=0644 ./github-actions-runner.build $(QUADLET_DIR)/github-actions-runner.build
	install -D --mode=0644 ./github-actions-runner@.container $(QUADLET_DIR)/github-actions-runner@.container
	for unit in $(QUADLET_DIR)/github-actions-runner@[0-9]*.container; do [ ! -L "$$unit" ] || rm -f "$$unit"; done
	for instance in $(RUNNER_INSTANCES); do ln -sfn github-actions-runner@.container $(QUADLET_DIR)/github-actions-runner@$$instance.container; done
	if [ -L $(DATA_DIR)/state-1 ]; then install -D --mode=0644 ./github-actions-runner@1.container.d/10-legacy-state.conf $(QUADLET_DIR)/github-actions-runner@1.container.d/10-legacy-state.conf; else rm -f $(QUADLET_DIR)/github-actions-runner@1.container.d/10-legacy-state.conf; fi
	rm -f $(QUADLET_DIR)/github-actions-runner.container
	install -D --mode=0644 ./github-actions.slice $(SYSTEMD_DIR)/github-actions.slice
	install -D --mode=0644 ./podman.service.d/github-actions.conf $(SYSTEMD_DIR)/podman.service.d/github-actions.conf
	-systemctl --user unmask github-actions-runner.service
	-systemctl --user unmask $(RUNNER_SERVICES)
	systemctl --user daemon-reload
	systemctl --user enable --now podman.socket
	systemctl --user restart github-actions-runner-build.service
	$(BIN_DIR)/github-actions-runner configure
	systemctl --user start $(RUNNER_SERVICES)

status:
	$(BIN_DIR)/github-actions-runner status

logs:
	$(BIN_DIR)/github-actions-runner logs

restart:
	systemctl --user restart $(RUNNER_SERVICES)

disable:
	systemctl --user mask --now $(RUNNER_SERVICES)

update-hooks:
	$(BIN_DIR)/github-actions-runner update-hooks

uninstall:
	$(BIN_DIR)/github-actions-runner unregister
	-systemctl --user stop $(RUNNER_SERVICES) github-actions-runner.service
	-systemctl --user unmask $(RUNNER_SERVICES) github-actions-runner.service
	-systemctl --user stop github-actions-runner-build.service
	rm -f $(QUADLET_DIR)/github-actions-runner.build
	rm -f $(QUADLET_DIR)/github-actions-runner.container
	rm -f $(QUADLET_DIR)/github-actions-runner@.container
	for unit in $(QUADLET_DIR)/github-actions-runner@[0-9]*.container; do [ ! -L "$$unit" ] || rm -f "$$unit"; done
	rm -rf $(QUADLET_DIR)/github-actions-runner@1.container.d
	rm -f $(SYSTEMD_DIR)/github-actions.slice
	rm -f $(SYSTEMD_DIR)/podman.service.d/github-actions.conf
	rmdir --ignore-fail-on-non-empty $(SYSTEMD_DIR)/podman.service.d
	rm -f $(BIN_DIR)/github-actions-runner
	rm -rf $(DATA_DIR)
	-podman image rm $(IMAGE)
	systemctl --user daemon-reload
