VERSION := $(shell grep '"version"' .claude-plugin/plugin.json | head -1 | sed 's/.*"version": *"//;s/".*//')
LDFLAGS := -ldflags "-X main.version=$(VERSION)"

.PHONY: build install test test-integration lint clean

build:
	go build $(LDFLAGS) -o conclave ./cmd/conclave

install:
	go install $(LDFLAGS) ./cmd/conclave

test:
	go test ./... -race -cover -count=1

test-integration:
	go test ./... -race -tags=integration -count=1

lint:
	golangci-lint run ./...

clean:
	rm -f conclave
