#!/usr/bin/env bash
# Amahi-kai installer — https://amahi-kai.com
# Usage: curl -fsSL https://amahi-kai.com/install.sh | sudo bash
set -euo pipefail

REPO="https://github.com/CatDogBark/Amahi-kai.git"
INSTALL_DIR="/opt/amahi-kai"
BRANCH="main"

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
  echo "⚠️  Cannot detect OS. Amahi-kai supports Ubuntu 24.04+ and Debian 12+."
fi

# Install git if missing
if ! command -v git &>/dev/null; then
  echo "  Installing git..."
  apt-get update -qq && apt-get install -y -qq git
fi

# Clone or update
if [ -d "$INSTALL_DIR/.git" ]; then
  echo "  Updating existing installation..."
  git config --global --add safe.directory "$INSTALL_DIR"
  cd "$INSTALL_DIR"
  git fetch origin "$BRANCH"
  git reset --hard "origin/$BRANCH"
else
  echo "  Cloning Amahi-kai..."
  git clone --branch "$BRANCH" "$REPO" "$INSTALL_DIR"
  cd "$INSTALL_DIR"
fi

echo ""
echo "  Running installer..."
echo ""

# Hand off to the full installer
exec bin/amahi-install
