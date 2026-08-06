SHELL := /bin/bash
VERSION := $(shell cat VERSION)
ARCHIVE := dist/srm-dhcp-export-$(VERSION).zip

.PHONY: check test package clean

check:
	bash -n srm-dhcp-export.sh tests/run.sh tests/fakes/ssh
	python3 -m py_compile lib/process_reservations.py lib/render_pdf.py
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck srm-dhcp-export.sh tests/run.sh tests/fakes/ssh; \
	else \
		printf '%s\n' 'ShellCheck is not installed; skipping shell lint.'; \
	fi

test: check
	./tests/run.sh

package: check
	@mkdir -p dist
	@git archive --format=zip --prefix=srm-dhcp-export-$(VERSION)/ --output=$(ARCHIVE) HEAD
	@printf 'Created %s\n' '$(ARCHIVE)'

clean:
	rm -rf dist lib/__pycache__
