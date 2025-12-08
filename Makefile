# copy:
# 	@echo "============== begin copy to github_release =============="
# 	@find . -type f -not -name "*.png" -not -name "*.md" -not -path "./.git/*" -not -path "./github_release/*" -exec cp {} github_release/ \;
# 	@rm -rf github_release/.gitignore
# 	@rm -rf github_release/Makefile
# 	@echo "============== end copy to github_release =============="

copy:
	@echo "============== begin copy to github_release =============="
	@rm -rf github_release/*
	@cp ./prover_resources/* github_release/
	@cp ./verifier_resources/* github_release/
	@echo "============== end copy to github_release =============="

release:
	@echo "============== begin release to github =============="
	@bash ./calculate_sha256.sh > sha256sum.txt
	@echo "============== end release to github =============="
