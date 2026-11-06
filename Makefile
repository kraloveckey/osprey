.PHONY: all build app test run scan top clean

all: build app

build:
	cargo build --release

app:
	chmod +x scripts/bundle_app.sh
	./scripts/bundle_app.sh

test:
	cargo test

run: app
	open dist/Osprey.app

scan: build
	./target/release/osprey scan

top: build
	./target/release/osprey top

clean:
	cargo clean
	(cd macos && rm -rf .build)
	rm -rf dist
