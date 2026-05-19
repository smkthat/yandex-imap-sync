# Image names
IMAGE_NAME=mail-sync
CONTAINER_NAME=mail-sync-container

# ANSI styles
BOLD=\033[1m
YELLOW=\033[33m
CYAN=\033[36m
RED=\033[31m
RESET=\033[0m

.PHONY: build run logs stop clean test shellcheck quickstart help

help: ## Show available targets
	@printf '$(BOLD)$(YELLOW)%s$(RESET)\n' 'yandex-imap-sync'
	@echo
	@printf '$(BOLD)%s$(RESET)\n' 'Available targets:'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(CYAN)%-15s$(RESET) %s\n", $$1, $$2}'
	@echo
	@make quickstart

quickstart: ## Show the safe migration run order
	@printf '$(BOLD)%s$(RESET)\n' 'Safe migration run order:'
	@printf '  $(YELLOW)1.$(RESET) %s\n' 'Prepare .env from .env.example and fill in app passwords.'
	@printf '  $(YELLOW)2.$(RESET) %s\n' 'Check local scripts:'
	@printf '     $(CYAN)%s$(RESET)\n' 'make test'
	@printf '  $(YELLOW)3.$(RESET) %s\n' 'Build the Docker image:'
	@printf '     $(CYAN)%s$(RESET)\n' 'make build'
	@printf '  $(YELLOW)4.$(RESET) %s\n' 'Check authentication without migrating messages:'
	@printf '     $(CYAN)%s$(RESET)\n' 'make run-logs PARAMS="--justlogin"'
	@printf '  $(YELLOW)5.$(RESET) %s\n' 'Check folders without changing the target mailbox:'
	@printf '     $(CYAN)%s$(RESET)\n' 'make run-logs PARAMS="--dry --justfolders --automap --useheader Message-Id --errorsmax 5"'
	@printf '  $(YELLOW)6.$(RESET) %s\n' 'Run the full migration:'
	@printf '     $(CYAN)%s$(RESET)\n' 'make run-logs PARAMS="--automap --useheader Message-Id --errorsmax 5"'
	@printf '%s\n' ''
	@printf '$(RED)!! Do not add $(YELLOW)%s$(RED) or $(YELLOW)%s$(RED) unless you want to delete messages.$(RESET)\n' '--delete1' '--delete2'

build: ## Build the Docker image
	docker build -t $(IMAGE_NAME) .

shellcheck: ## Check shell script syntax
	bash -n src/mail-sync.sh tests/mail-sync-config-test.sh

test: shellcheck ## Run tests
	bash tests/mail-sync-config-test.sh

run: ## Run the container in the background
	docker run -d --name $(CONTAINER_NAME) --env-file .env $(IMAGE_NAME)

run-logs: ## Run the container with live logs (example: make run-logs PARAMS="--justlogin")
	docker run --rm --name $(CONTAINER_NAME) --env-file .env $(if $(PARAMS),-e PARAMS="$(PARAMS)") $(IMAGE_NAME)

logs: ## Follow logs from the background container
	docker logs -f $(CONTAINER_NAME)

stop: ## Stop and remove the container
	docker stop $(CONTAINER_NAME) || true
	docker rm $(CONTAINER_NAME) || true

clean: stop ## Full cleanup: stop the container and remove the image
	docker rmi $(IMAGE_NAME)
