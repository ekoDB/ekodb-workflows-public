# ekodb-workflows-public -- the reusable release workflow for ekoDB's public
# repositories. `make help` lists targets.
SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

SCRIPTS := scripts
SH_SCRIPTS := $(wildcard $(SCRIPTS)/*.sh)
PY_SCRIPTS := $(wildcard $(SCRIPTS)/*.py)
SH_TESTS   := $(wildcard $(SCRIPTS)/*_test.sh)
PY_TESTS   := $(wildcard $(SCRIPTS)/*_test.py)

ACTIONLINT_VERSION := 1.7.12
TOOLS_DIR := .tooling
ACTIONLINT_BIN := $(TOOLS_DIR)/actionlint

DEV_REQS := requirements-dev.txt
VENV := .venv
PY   := $(if $(wildcard $(VENV)/bin/python),$(CURDIR)/$(VENV)/bin/python,python3)
RUFF := $(if $(wildcard $(VENV)/bin/ruff),$(CURDIR)/$(VENV)/bin/ruff,ruff)

.PHONY: help bootstrap test lint lint-shell lint-actions lint-python bump-version

help: ## List targets
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  %-16s %s\n", $$1, $$2}'

bootstrap: ## Create .venv with the pinned Python tooling (PyYAML, ruff)
	@python3 -m venv $(VENV) && $(VENV)/bin/pip install -q -r $(DEV_REQS) && echo "bootstrapped $(VENV)"

test: ## Run every scripts/*_test.py then every scripts/*_test.sh; refuse on zero matches
	@$(PY) -c "import yaml" 2>/dev/null || { echo "PyYAML is not installed -- run: make bootstrap"; exit 1; }
	@[ -n "$(strip $(PY_TESTS))" ] || { echo "no python harnesses matched $(SCRIPTS)/*_test.py -- refusing to report success on zero tests"; exit 1; }
	@[ -n "$(strip $(SH_TESTS))" ] || { echo "no bash harnesses matched $(SCRIPTS)/*_test.sh -- refusing to report success on zero tests"; exit 1; }
	@for t in $(PY_TESTS); do echo "python: $$t"; (cd $(SCRIPTS) && $(PY) "$$(basename $$t)") || exit 1; done
	@for t in $(SH_TESTS); do echo "bash: $$t"; bash "$$t" || exit 1; done
	@echo "all ekodb-workflows-public tests passed"

lint: lint-shell lint-actions lint-python ## shellcheck, actionlint, ruff

lint-shell: ## shellcheck --severity=warning over scripts/*.sh
	@command -v shellcheck >/dev/null || { echo "shellcheck is required (brew install shellcheck / apt install shellcheck)"; exit 1; }
	@shellcheck --severity=warning $(SH_SCRIPTS) && echo "shellcheck clean"

# actionlint's expression checker does not know `job.workflow_sha` (the SHA of
# the reusable workflow file, in the job context per GitHub's contexts
# reference); the one ignore below is that false positive and nothing else.
lint-actions: ## actionlint over .github/workflows (system binary, else a pinned download into .tooling/)
	@AL="$$(command -v actionlint || true)"; \
	if [ -z "$$AL" ] && [ -x "$(ACTIONLINT_BIN)" ]; then AL="$$(pwd)/$(ACTIONLINT_BIN)"; fi; \
	if [ -z "$$AL" ]; then \
	  mkdir -p $(TOOLS_DIR) && bash <(curl -fsSL https://raw.githubusercontent.com/rhysd/actionlint/v$(ACTIONLINT_VERSION)/scripts/download-actionlint.bash) $(ACTIONLINT_VERSION) $(TOOLS_DIR) >/dev/null && AL="$$(pwd)/$(ACTIONLINT_BIN)"; \
	fi; \
	"$$AL" -color -ignore 'property "workflow_sha" is not defined' && echo "actionlint clean"

lint-python: ## ruff over scripts/*.py
	@[ -z "$(strip $(PY_SCRIPTS))" ] || $(RUFF) check $(PY_SCRIPTS)

bump-version: ## Collapse [Unreleased] into a dated block and stamp version.json (VERSION=X.Y.Z)
	@[ -n "$(VERSION)" ] || { echo "usage: make bump-version VERSION=X.Y.Z"; exit 2; }
	@printf '%s' "$(VERSION)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$' || { echo "VERSION must be plain X.Y.Z"; exit 2; }
	@grep -q '^## \[Unreleased\]$$' CHANGELOG.md || { echo "CHANGELOG.md has no [Unreleased] block to collapse"; exit 1; }
	@sed -i.bak "s/^## \[Unreleased\]$$/## [$(VERSION)] - $$(date -u +%Y-%m-%d)/" CHANGELOG.md && rm -f CHANGELOG.md.bak
	@printf '{\n  "version": "%s"\n}\n' "$(VERSION)" > version.json
	@echo "collapsed [Unreleased] into [$(VERSION)] and stamped version.json; commit as: chore(*): v$(VERSION)"
