.PHONY: bootstrap build test coverage abi-export lint demo-local demo-testnet demo-sepolia demo-compare demo-launch deploy-sepolia demo-all check-deps verify-commits

bootstrap:
	./scripts/bootstrap.sh

build:
	forge build

test:
	forge test

coverage:
	forge coverage --report summary

abi-export:
	./scripts/export_abis.sh

lint:
	forge fmt --check
	forge build

check-deps:
	./scripts/bootstrap.sh

verify-commits:
	./verify_commits.sh

demo-local:
	./scripts/demo_local.sh

demo-testnet:
	./scripts/demo_testnet.sh

demo-sepolia:
	./scripts/demo_sepolia.sh

demo-compare:
	./scripts/demo_compare.sh

demo-launch:
	./scripts/demo_launch.sh

deploy-sepolia:
	./scripts/deploy_sepolia.sh

demo-all: demo-launch demo-compare
