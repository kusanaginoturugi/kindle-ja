.PHONY: test lint

test: lint
	bats tests

lint:
	shellcheck kindle-ja deploy
