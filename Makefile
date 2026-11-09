# Every check and build of the repository, the same on a laptop and in CI.
REGISTRY := ghcr.io/xoadev/nanobrain
IMAGES ?= $(notdir $(wildcard images/*))
# What a pull request is compared with: CI checks out the merge commit, whose first parent is main.
BASE ?= origin/main

# The shared head of AGENTS.md, above its <!-- xoadev:end --> line, comes from AGENTS_URL.
AGENTS_URL := https://xoa.dev/_dev/OSS_AGENTS.md
AGENTS_SCRIPT := https://xoa.dev/_dev/agents.sh

# Pinned tools, fetched into .tmp/bin and checked against their sha256: the same version here and in CI.
BIN := .tmp/bin
HADOLINT_VERSION := 2.15.1
SHELLCHECK_VERSION := 0.11.0
ACTIONLINT_VERSION := 1.7.12
RUMDL_VERSION := 0.3.0
TYPOS_VERSION := 1.51.1
RUFF_VERSION := 0.17.1

ARCH := $(shell uname -m)
ifeq ($(ARCH),x86_64)
HADOLINT_ARCH := x86_64
ACTIONLINT_ARCH := amd64
HADOLINT_SHA256 := c7187db94eeeeca956519a6af171adc31453941a1e777961f6e680f697c8c507
SHELLCHECK_SHA256 := 8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198
ACTIONLINT_SHA256 := 8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8
RUMDL_SHA256 := 6c90c398f04c11a09dcbd2da08bdaa6d53d9b14393e3cd32dbdf4da5620eec5c
TYPOS_SHA256 := 93c301fd4120ff076e2cc2a6d6a61cab4a4bdb81899287c0938b452e56d1f454
RUFF_SHA256 := 2d9878b5e6a3d0dedadbfc01a64bfe54e72f560adbfd235937cd29e1fc9238e3
else ifeq ($(ARCH),aarch64)
HADOLINT_ARCH := arm64
ACTIONLINT_ARCH := arm64
HADOLINT_SHA256 := f6198ef8090f404dbb771abfee086eb8c48ac177f30da7fd3510aca35b344b5d
SHELLCHECK_SHA256 := 12b331c1d2db6b9eb13cfca64306b1b157a86eb69db83023e261eaa7e7c14588
ACTIONLINT_SHA256 := 325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6
RUMDL_SHA256 := 5a6274e69bf22164ee6adb47381c870f61ece4648a89fa8b178f0ed24857154a
TYPOS_SHA256 := 2ac5e37b3236b3c07dec5cdf1527acf143aec4674a6089b0bf424d021b35e099
RUFF_SHA256 := 255404ccf2f7950ff6aad8858321a6f416fe2a840ae4e37dfb4c21cb8774f325
else
$(error no pinned tools for $(ARCH): add its sha256s to the Makefile, or run make on x86_64 or aarch64)
endif

LINTERS = $(BIN)/hadolint $(BIN)/shellcheck $(BIN)/actionlint $(BIN)/rumdl $(BIN)/typos $(BIN)/ruff

.PHONY: help lint format test changed-images agents-sync agents-check

help: ## List the targets
	@grep -hE '^[a-z%-]+:.*## ' $(MAKEFILE_LIST) | sed 's/:.*## /\t/' | sort

lint: $(LINTERS) agents-check ## Dockerfiles, workflows, Markdown, typos, Python and the shared AGENTS.md head
	$(BIN)/hadolint images/*/Dockerfile
	PATH="$(CURDIR)/$(BIN):$$PATH" $(BIN)/actionlint
	$(BIN)/rumdl check --no-cache .
	$(BIN)/typos
	$(BIN)/ruff check .
	$(BIN)/ruff format --check .

format: $(BIN)/rumdl $(BIN)/ruff ## Apply the formatters and the safe fixes of every linter
	$(BIN)/rumdl check --no-cache --fix .
	$(BIN)/ruff check --fix .
	$(BIN)/ruff format .

test: $(addprefix image-,$(IMAGES)) ## Build every image (or IMAGES="a b") and run its check.py inside it

image-%: ## Build images/<name> and run its check.py inside it, with no GPU. arm64 only
	docker build -t $(REGISTRY)/$*:check images/$*
	docker run --rm -i --entrypoint /opt/venv/bin/python3 $(REGISTRY)/$*:check - < images/$*/check.py

# VERSION is convco's, from the commits that touched images/<name>/ (release.yaml). A tag is
# published once: "manifest unknown" is the registry saying it does not exist yet, and any other
# failure stops here rather than risk rewriting a tag. Either way the tag's digest goes to
# $GITHUB_OUTPUT, so a run that pushed but failed before its release finishes it on the next one.
publish-%: ## Build, check and push images/<name> as VERSION=X.Y.Z, unless that tag is already published
	@echo "$(VERSION)" | grep -qxE '[0-9]+\.[0-9]+\.[0-9]+' || { echo "VERSION='$(VERSION)': pass the X.Y.Z to publish, make publish-$* VERSION=X.Y.Z"; exit 1; }
	@tag="$(REGISTRY)/$*:$(VERSION)"; \
	if error=$$(docker manifest inspect "$$tag" 2>&1 >/dev/null); then \
	  echo "$$tag is already published, and a published tag is never rewritten"; \
	else \
	  case "$$error" in *"manifest unknown"*) ;; *) echo "cannot tell whether $$tag exists: $$error"; exit 1 ;; esac; \
	  $(MAKE) --no-print-directory image-$* && docker tag $(REGISTRY)/$*:check "$$tag" && docker push "$$tag" || exit 1; \
	fi; \
	echo "digest=$$(docker buildx imagetools inspect --format '{{.Manifest.Digest}}' "$$tag")" >> "$${GITHUB_OUTPUT:-/dev/stdout}"

changed-images: ## The images whose folder differs from BASE, one per line
	@git diff --name-only $(BASE)...HEAD -- images/ | cut -d/ -f2 | sort -u | while read -r image; do \
	  [ -d "images/$$image" ] && echo "$$image"; done; true

agents-sync agents-check: ## Sync (agents-sync) or check (agents-check) the shared head of AGENTS.md
	@if s=$$(curl -fsS --max-time 20 '$(AGENTS_SCRIPT)'); then sh -c "$$s" agents $(@:agents-%=%) '$(AGENTS_URL)'; \
	else echo "warning: $(AGENTS_SCRIPT) unreachable, $@ not run" >&2; [ $@ = agents-check ]; fi

# $(call fetch,url,sha256): downloads url to $@.download and refuses it unless it matches sha256.
define fetch
	@mkdir -p $(BIN)
	curl -fsSL --proto '=https' --retry 3 -o $@.download '$(1)'
	echo '$(2)  $@.download' | sha256sum -c --quiet - || { rm -f $@.download; exit 1; }
endef

$(BIN)/hadolint:
	$(call fetch,https://github.com/hadolint/hadolint/releases/download/v$(HADOLINT_VERSION)/hadolint-linux-$(HADOLINT_ARCH),$(HADOLINT_SHA256))
	chmod 0755 $@.download && mv $@.download $@

$(BIN)/shellcheck:
	$(call fetch,https://github.com/koalaman/shellcheck/releases/download/v$(SHELLCHECK_VERSION)/shellcheck-v$(SHELLCHECK_VERSION).linux.$(ARCH).tar.xz,$(SHELLCHECK_SHA256))
	tar -xJf $@.download -C $(BIN) --strip-components=1 shellcheck-v$(SHELLCHECK_VERSION)/shellcheck && rm $@.download

$(BIN)/actionlint:
	$(call fetch,https://github.com/rhysd/actionlint/releases/download/v$(ACTIONLINT_VERSION)/actionlint_$(ACTIONLINT_VERSION)_linux_$(ACTIONLINT_ARCH).tar.gz,$(ACTIONLINT_SHA256))
	tar -xzf $@.download -C $(BIN) actionlint && rm $@.download

$(BIN)/rumdl:
	$(call fetch,https://github.com/rvben/rumdl/releases/download/v$(RUMDL_VERSION)/rumdl-v$(RUMDL_VERSION)-$(ARCH)-unknown-linux-musl.tar.gz,$(RUMDL_SHA256))
	tar -xzf $@.download -C $(BIN) rumdl && rm $@.download

$(BIN)/typos:
	$(call fetch,https://github.com/crate-ci/typos/releases/download/v$(TYPOS_VERSION)/typos-v$(TYPOS_VERSION)-$(ARCH)-unknown-linux-musl.tar.gz,$(TYPOS_SHA256))
	tar -xzf $@.download -C $(BIN) ./typos && rm $@.download

$(BIN)/ruff:
	$(call fetch,https://github.com/astral-sh/ruff/releases/download/$(RUFF_VERSION)/ruff-$(ARCH)-unknown-linux-musl.tar.gz,$(RUFF_SHA256))
	tar -xzf $@.download -C $(BIN) --strip-components=1 ruff-$(ARCH)-unknown-linux-musl/ruff && rm $@.download
