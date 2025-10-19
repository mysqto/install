.PHONY: help test quick-test clean install

help:
	@echo "FR24Feed Installation - Available targets:"
	@echo ""
	@echo "  make test          - Run quick test (Ubuntu 22.04)"
	@echo "  make quick-test    - Same as test"
	@echo "  make clean         - Clean up test containers"
	@echo "  make install       - Install FR24Feed on current system"
	@echo ""

test: quick-test

quick-test:
	@echo "Running quick test..."
	@./quick-test.sh

clean:
	@echo "Cleaning up test containers..."
	@docker ps -a | grep fr24-test | awk '{print $$1}' | xargs -r docker rm -f 2>/dev/null || true
	@docker ps -a | grep fr24-quick-test | awk '{print $$1}' | xargs -r docker rm -f 2>/dev/null || true
	@echo "Cleanup complete"

install:
	@echo "Installing FR24Feed..."
	@echo "Please provide configuration:"
	@read -p "Sharing key (or press Enter to skip): " key; \
	read -p "Latitude (or press Enter to skip): " lat; \
	read -p "Longitude (or press Enter to skip): " lon; \
	read -p "Altitude in meters (or press Enter to skip): " alt; \
	if [ -n "$$key" ]; then \
		sudo ./install --key "$$key" --lat "$$lat" --lon "$$lon" --alt "$$alt"; \
	else \
		sudo ./install; \
	fi

