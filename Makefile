IMAGE ?= jirauha/pibox
SANDBOX_UID ?= $(shell id -u)
SANDBOX_GID ?= $(shell id -g)
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
	docker build \
		--build-arg SANDBOX_UID=$(SANDBOX_UID) \
		--build-arg SANDBOX_GID=$(SANDBOX_GID) \
		--build-arg SANDBOX_USER=$(SANDBOX_USER) \
		-t $(IMAGE) .

rebuild:
	docker build --no-cache \
		--build-arg SANDBOX_UID=$(SANDBOX_UID) \
		--build-arg SANDBOX_GID=$(SANDBOX_GID) \
		--build-arg SANDBOX_USER=$(SANDBOX_USER) \
		-t $(IMAGE) .

run:
	PIBOX_IMAGE=$(IMAGE) ./pibox.sh run

shell:
	PIBOX_IMAGE=$(IMAGE) ./pibox.sh shell

clean:
	docker image rm $(IMAGE)
