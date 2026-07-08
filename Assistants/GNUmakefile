# Top-level GNUmakefile for Assistants
# 1. Builds AssistantFramework (without installing)
# 2. Builds and installs each subfolder that has a GNUmakefile and no .DISABLED
# Error codes are propagated (no || true).

SUBDIRS := $(sort $(shell for d in *; do \
	[ -d "$${d}" ] && [ "$${d}" != "AssistantFramework" ] && \
	! [ -f "$${d}/.DISABLED" ] && \
	[ -f "$${d}/GNUmakefile" ] && echo "$${d}"; \
	done))

.PHONY: all build framework $(SUBDIRS)

all: build

framework:
	@echo "Building AssistantFramework..."
	$(MAKE) -C AssistantFramework
	@echo "AssistantFramework built."

$(SUBDIRS): framework
	@echo "Building and installing $@..."
	$(MAKE) -C $@ install
	@echo "$@ done."

build: framework $(SUBDIRS)
	@echo "All assistants built and installed."

clean:
	@for d in AssistantFramework $(SUBDIRS); do \
		echo "Cleaning $$d"; \
		$(MAKE) -C $$d clean; \
	done
	@echo "All assistants cleaned."

distclean: clean
	@for d in AssistantFramework $(SUBDIRS); do \
		if [ -f "$${d}/GNUmakefile" ]; then \
			$(MAKE) -C $$d distclean; \
		fi; \
	done

install: build
	@echo "All assistants installed."
