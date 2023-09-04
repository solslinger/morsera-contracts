-include .env

fork-test:
	forge test --fork-url $(RPC_URL) -vvv

gas-report:
	forge test --fork-url $(RPC_URL) --gas-report