# 尝试运行 cargo prove --version 命令
if ! cargo prove --version &> /dev/null; then
    # step1: install sp1 prover system
    curl -L https://sp1up.succinct.xyz | bash

    # Store the correct profile file (i.e. .profile for bash or .zshenv for ZSH).
    case $SHELL in
    */zsh)
        PROFILE=${ZDOTDIR-"$HOME"}/.zshenv
        PREF_SHELL=zsh
        ;;
    */bash)
        PROFILE=$HOME/.bashrc
        PREF_SHELL=bash
        ;;
    */fish)
        PROFILE=$HOME/.config/fish/config.fish
        PREF_SHELL=fish
        ;;
    */ash)
        PROFILE=$HOME/.profile
        PREF_SHELL=ash
        ;;
    *)
        echo "sp1up: could not detect shell, manually add ${SP1_BIN_DIR} to your PATH."
        exit 1
    esac

    source ${PROFILE}
    sp1up
else
  echo "sp1 prover system installed, skip the installation steps"
fi

# CUDA installation is handled by install_and_run_prover0.sh.
echo "Skipping CUDA installation in eth_dependency.sh"

echo "Skipping Docker-related setup in eth_dependency.sh"
