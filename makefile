-include .env

.PHONY: help build test stageTest

help:
	@echo "Usage:"
	@echo "  make build"
	@echo ""
	@echo "  make test"
	@echo ""
	@echo "  make coverage"


build :; forge build --sizes

test :; forge test -vvv

coverage :; forge coverage --no-match-coverage "^(test|script)/"

coverageReport :; forge coverage --no-match-coverage "^(test|script)/" --report debug > coverage.info
