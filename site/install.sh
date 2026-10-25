#!/usr/bin/env bash
# Amahi-kai installer — https://amahi-kai.com
# Usage: curl -fsSL https://amahi-kai.com/install.sh | sudo bash
# Options go after "bash -s --", e.g.: curl -fsSL https://amahi-kai.com/install.sh | sudo bash -s -- --headless
set -euo pipefail

REPO="https://github.com/CatDogBark/Amahi-kai.git"
INSTALL_DIR="/opt/amahi-kai"
# main is the release branch. AMAHI_BRANCH=dev installs the code in development, for testing:
#   curl -fsSL https://amahi-kai.com/install.sh | sudo AMAHI_BRANCH=dev bash
BRANCH="${AMAHI_BRANCH:-main}"

echo ""
echo "  🌊  Amahi-kai Installer"
echo "  ========================"
echo ""

# Check root
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Please run as root: curl -fsSL https://amahi-kai.com/install.sh | sudo bash"
  exit 1
fi

# Check OS
if [ -f /etc/os-release ]; then
  . /etc/os-release
  echo "  OS: $PRETTY_NAME"
else
  echo "⚠️  Cannot detect OS. Amahi-kai is made for Ubuntu 24.04."
fi
[ "$BRANCH" = main ] || echo "  Branch: $BRANCH"

# Install git if missing
if ! command -v git &>/dev/null; then
  echo "  Installing git..."
  apt-get update -qq && apt-get install -y -qq git
fi

# Installed already: its own installer runs on the version installed. New versions come through
# System Update (Settings → System Status), which follows the update channel, backs the
# database up first and goes back if a step fails; fetching here would skip all three.
if [ -d "$INSTALL_DIR/.git" ]; then
  echo "  Amahi-kai is installed already: running its installer on the version installed."
  echo "  New versions come through System Update (Settings → System Status)."
  [ "$BRANCH" = main ] || echo "  (AMAHI_BRANCH is for a new install; an installed one picks its channel there, under Follows.)"
  git config --global --get-all safe.directory 2>/dev/null | grep -qxF "$INSTALL_DIR" \
    || git config --global --add safe.directory "$INSTALL_DIR"
  echo ""
  cd "$INSTALL_DIR"
  exec bin/amahi-install "$@"
fi

# Clone (git as root, without hooks from the checkout)
echo "  Cloning Amahi-kai..."
git clone --branch "$BRANCH" "$REPO" "$INSTALL_DIR"
cd "$INSTALL_DIR"

echo ""
echo "  Running installer..."
echo ""

# Hand off to the full installer, which uses the code fetched here as it is.
export AMAHI_CODE_FETCHED=1
exec bin/amahi-install "$@"
