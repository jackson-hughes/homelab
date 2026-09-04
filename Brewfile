# Tooling for working in this repo. Install with: brew bundle
#
# The trusted: options scope trust to the specific third-party formula/cask
# rather than the whole tap, and make fresh-machine `brew bundle` work with
# no manual `brew trust` step. Note `brew bundle cleanup` resets the trust
# store to exactly these declarations.
tap "fluxcd/tap", trusted: { formulae: ["flux"] }
tap "controlplaneio-fluxcd/tap", trusted: { formulae: ["flux-operator"] }
tap "home-operations/tap", trusted: { casks: ["flate"] }
tap "postfinance/tap", trusted: { casks: ["topf"] }

# Cluster management
brew "fluxcd/tap/flux" # fully qualified: homebrew/core has an unrelated "flux"
brew "controlplaneio-fluxcd/tap/flux-operator" # manages the FluxInstance that installs Flux
brew "kubernetes-cli"
brew "talosctl"
cask "postfinance/tap/topf"
brew "virtctl"
cask "headlamp"

# Task running and repo scripts
brew "go-task"
brew "jq" # scripts/check-schematic.sh

# Infrastructure as code
brew "tfenv" # resolves infra/terraform/*/.terraform-version; run `tfenv install` there once

# Validation: local companion to CI (.github/workflows, .pre-commit-config.yaml)
brew "pre-commit"
brew "kubeconform" # scripts/validate-kubernetes.sh
brew "kustomize"   # scripts/validate-kubernetes.sh
brew "go"          # builds the SHA-pinned gitleaks/actionlint pre-commit hooks
brew "shellcheck"  # actionlint shells out to it to lint workflow run: blocks
cask "home-operations/tap/flate" # offline Flux render/diff, as in the flate-* CI jobs
