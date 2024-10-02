ARCHS := x86_64 arm aarch64 powerpc
TARGETS := $(addprefix build-, $(ARCHS))

.PHONY: clean help download_packages build build-docker-image $(TARGETS)

help:
	@echo "Usage:"
	@echo "  make build"
	@echo ""

	@for target in $(TARGETS); do \
		echo "  $$target"; \
	done

	@echo ""
	@echo "  make clean"

build/download_packages.stamp:
	mkdir -p build/packages

	./src/download_packages.sh build/packages

	touch build/download_packages.stamp

download-packages: build/download_packages.stamp

build-docker-image: Dockerfile
	docker build -t gdb-static .

build: $(TARGETS)

$(TARGETS): build-%: download-packages build-docker-image
	mkdir -p build
	docker run --user $(shell id -u):$(shell id -g) \
		--rm --volume ./build:/build gdb-static \
		/app/gdb/build.sh $* /build/ /app/gdb/gdb_static.patch

clean:
	rm -rf build

# Kill and remove all containers of image gdb-static
	docker ps -a | grep -P "^[a-f0-9]+\s+gdb-static\s+" | awk '{print $$1}' | xargs docker rm -f 2>/dev/null || true

	docker rmi -f gdb-static 2>/dev/null || true
