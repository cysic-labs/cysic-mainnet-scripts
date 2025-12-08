DEFAULT_GOAL: release

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



.PHONY: release copy
