APP_FILES=$(shell find . -type f -name '*.lua')
LIT_VERSION=3.7.3
TARGET=build/rackspace-monitoring-agent
LUVI?=./luvi
LIT?=./lit
LUVISIGAR?=luvi-sigar
PREFIX?=/usr/bin

all: $(TARGET)

$(LUVISIGAR):
	[ ! -x luvi-sigar ] && $(LIT) get-luvi -o luvi-sigar || exit 0

$(TARGET):  lit $(LUVISIGAR) $(APP_FILES)
	cmake -H. -Bbuild
	cmake --build build
	build/rackspace-monitoring-agent -v

install: $(TARGET)
	install -m 777 $(TARGET) $(PREFIX)/

test: lit $(LUVISIGAR)
	rm -rf tests/tmpdir && mkdir tests/tmpdir
	$(LIT) install
	./luvi-sigar . -m tests/run.lua

clean:
	rm -rf lit luvi luvi-sigar build

lit:
	curl -L https://github.com/luvit/lit/raw/${LIT_VERSION}/get-lit.sh | sh

lint:
	find . ! -path './deps/**' ! -path './tests/**' -name '*.lua' | xargs luacheck

package:
	cmake -H. -Bbuild
	cmake --build build -- package

packagerepo:
	cmake --build build -- packagerepo

packagerepoupload:
	cmake --build build -- packagerepoupload

siggen:
	cmake --build build -- siggen

siggenupload:
	cmake --build build -- siggenupload

# Ubuntu 24.04 Docker build targets
ubuntu24-build:
	@echo "==> Building rackspace-monitoring-agent .deb for Ubuntu 24.04"
	@echo "==> First build may take 15-20 minutes (downloading dependencies, compiling)."
	@echo "==> Subsequent builds will be faster due to Docker layer caching."
	@if [ ! -d "../sigar" ]; then \
		echo "ERROR: ../sigar directory not found."; \
		echo "Clone the private sigar repo as a sibling directory first:"; \
		echo "  git clone git@github.com:racker/sigar.git ../sigar"; \
		exit 1; \
	fi
	mkdir -p dist
	rm -rf .docker-context && mkdir -p .docker-context
	cp -a . .docker-context/agent
	cp -a ../sigar .docker-context/sigar
	docker build -f .docker-context/agent/Dockerfile.ubuntu24 -t rma-ubuntu24-builder .docker-context
	rm -rf .docker-context
	docker run --rm -v "$$(pwd)/dist:/output" rma-ubuntu24-builder
	@echo "==> Done. Package is in ./dist/"

ubuntu24-test:
	docker run --rm -v "$$(pwd)/dist:/packages:ro" ubuntu:24.04 \
		bash -c "apt-get update && apt-get install -y /packages/*.deb && rackspace-monitoring-agent -v"

ubuntu24-shell:
	docker run --rm -it -v "$$(pwd)/dist:/output" rma-ubuntu24-builder bash

ubuntu24-clean:
	rm -rf dist/
	-docker rmi rma-ubuntu24-builder 2>/dev/null

.PHONY: clean lint package packagerepo packagerepoupload siggen siggenupload install ubuntu24-build ubuntu24-test ubuntu24-clean ubuntu24-shell
