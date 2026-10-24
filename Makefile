PIBOX_ENGINE ?= podman
IMAGE ?= docker.io/jirauha/pibox
SANDBOX_UID ?= 1000
SANDBOX_GID ?= 1000
SANDBOX_USER ?= sandbox

.PHONY: help build rebuild run shell clean

help:
	@echo "Usage: make <target>"
	@echo
	@echo "Targets:"
	@echo "  build    Build the sandbox image"
	@echo "  rebuild  Rebuild the sandbox image without cache"
	@echo "  run      Run pi inside the sandbox"
	@echo "  shell    Open a bash shell inside the sandbox"
	@echo "  clean    Remove the sandbox image"
	@echo
	@echo "Variables:"
	@echo "  PIBOX_ENGINE=$(PIBOX_ENGINE)"
	@echo "  IMAGE=$(IMAGE)"
	@echo "  SANDBOX_UID=$(SANDBOX_UID)"
	@echo "  SANDBOX_GID=$(SANDBOX_GID)"
	@echo "  SANDBOX_USER=$(SANDBOX_USER)"
	@echo
	@echo "Examples:"
	@echo "  make build"
	@echo "  make run"
	@echo "  IMAGE=my-pibox make build"

build:
	$(PIBOX_ENGINE) build \
		--build-arg SANDBOX_UID=$(SANDBOX_UID) \
		--build-arg SANDBOX_GID=$(SANDBOX_GID) \
		--build-arg SANDBOX_USER=$(SANDBOX_USER) \
		-t $(IMAGE) .

rebuild:
	$(PIBOX_ENGINE) build --no-cache \
		--build-arg SANDBOX_UID=$(SANDBOX_UID) \
		--build-arg SANDBOX_GID=$(SANDBOX_GID) \
		--build-arg SANDBOX_USER=$(SANDBOX_USER) \
		-t $(IMAGE) .

run:
	PIBOX_ENGINE=$(PIBOX_ENGINE) PIBOX_IMAGE=$(IMAGE) PIBOX_SANDBOX_UID=$(SANDBOX_UID) PIBOX_SANDBOX_GID=$(SANDBOX_GID) ./pibox.sh

shell:
	PIBOX_ENGINE=$(PIBOX_ENGINE) PIBOX_IMAGE=$(IMAGE) PIBOX_SANDBOX_UID=$(SANDBOX_UID) PIBOX_SANDBOX_GID=$(SANDBOX_GID) ./pibox.sh shell

clean:
	$(PIBOX_ENGINE) image rm $(IMAGE)
