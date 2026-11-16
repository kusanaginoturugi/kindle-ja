.PHONY: test lint

test: lint
	bats tests
	python3 -m unittest discover -s tests

lint:
	shellcheck kindle-ja deploy setup-ocrd
