SHELL := /bin/bash

DEFAULT_GOAL: release

VERSION ?=
RELEASE_NOTES_FILE ?=

copy:
	@echo "============== begin copy to github_release =============="
	@rm -rf github_release/*
	@cp ./prover_resources/* github_release/
	@cp ./verifier_resources/* github_release/
	@echo "============== end copy to github_release =============="

release: copy
	@echo "============== begin release to github =============="
	@bash ./calculate_sha256.sh > sha256sum.txt
	@echo "============== end release to github =============="

auto-release:
	@bash ./auto_release.sh "$(VERSION)" "$(RELEASE_NOTES_FILE)"

.PHONY: release copy auto-release
