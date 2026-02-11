.PHONY: build adapters docker test clean

# Build the thunderdome CLI
build:
	go build -o thunderdome .

# Cross-compile the Claude Code WebSocket server for Linux
adapters:
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o adapters/claude-code/ws-server ./adapters/claude-code/

# Build Docker images (depends on adapters being compiled)
docker: adapters
	docker build -t thunderdome/claude-code:latest -f docker/claude-code/Dockerfile adapters/claude-code/
	docker build -t thunderdome/aider:latest -f docker/aider/Dockerfile adapters/aider/

# Run all tests
test:
	go test ./...

# Smoke test: run null adapter against T1
smoke: build
	./thunderdome run --orchestrator null --task bench-time-tracker --trials 1

clean:
	rm -f thunderdome adapters/claude-code/ws-server
