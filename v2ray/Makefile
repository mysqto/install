.PHONY: help test quick-test clean install-server install-client

help:
	@echo "V2Ray Installation - Available targets:"
	@echo ""
	@echo "  make test          - Run full test suite (all distros)"
	@echo "  make quick-test    - Run quick test (Ubuntu 22.04 only)"
	@echo "  make clean         - Clean up test containers"
	@echo "  make install-server - Install V2Ray server on current system"
	@echo "  make install-client - Install V2Ray client on current system"
	@echo ""

test:
	@echo "Running full test suite..."
	@./test.sh

quick-test:
	@echo "Running quick test..."
	@./quick-test.sh

clean:
	@echo "Cleaning up test containers..."
	@docker ps -a | grep v2ray-test | awk '{print $$1}' | xargs -r docker rm -f 2>/dev/null || true
	@docker ps -a | grep v2ray-quick-test | awk '{print $$1}' | xargs -r docker rm -f 2>/dev/null || true
	@echo "Cleanup complete"

install-server:
	@echo "Installing V2Ray server..."
	@sudo ./install --server

install-client:
	@echo "Please provide server details:"
	@read -p "Server address: " addr; \
	read -p "Server port: " port; \
	read -p "UUID: " uuid; \
	sudo ./install --client --address $$addr --port $$port --uuid $$uuid

