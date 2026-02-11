#!/bin/bash
#
# Android Build Environment Setup Script
# Run this on your Google Cloud VM or any Ubuntu 22.04+ system
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

print_info "=========================================="
print_info "Android Build Environment Setup"
print_info "=========================================="

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    print_warn "Running as root. Some operations may require sudo anyway."
fi

# Update system
print_info "Updating system packages..."
sudo apt-get update -y
sudo apt-get upgrade -y

# Install build dependencies
print_info "Installing Android build dependencies..."
sudo apt-get install -y \
    bc bison build-essential ccache curl flex g++-multilib gcc-multilib git \
    git-lfs gnupg gperf imagemagick lib32ncurses-dev lib32readline-dev \
    lib32z1-dev libelf-dev liblz4-tool libncurses6 libncurses-dev \
    libssl-dev libxml2 libxml2-utils lzop pngcrush rsync \
    schedtool squashfs-tools xsltproc zip zlib1g-dev \
    python3 python-is-python3 python3-pip \
    openjdk-17-jdk \
    fontconfig \
    tmux htop nano vim wget unzip aria2

# Install repo tool
print_info "Installing repo tool..."
if ! command -v repo &> /dev/null; then
    sudo curl -o /usr/local/bin/repo https://storage.googleapis.com/git-repo-downloads/repo
    sudo chmod a+x /usr/local/bin/repo
fi

# Configure git
print_info "Configuring git..."
git config --global user.email "${GIT_EMAIL:-builder@pixelos.local}"
git config --global user.name "${GIT_NAME:-PixelOS Builder}"
git config --global color.ui false
git config --global init.defaultBranch main

# Initialize git-lfs
print_info "Initializing git-lfs..."
git lfs install

# Setup ccache
print_info "Setting up ccache..."
CCACHE_SIZE="${CCACHE_SIZE:-50G}"
ccache -M "$CCACHE_SIZE"
echo 'export USE_CCACHE=1' >> ~/.bashrc
echo 'export CCACHE_EXEC=$(which ccache)' >> ~/.bashrc
echo "export CCACHE_DIR=${CCACHE_DIR:-/tmp/ccache}" >> ~/.bashrc

# Create build directory
BUILD_DIR="${BUILD_DIR:-$HOME/android}"
print_info "Creating build directory: $BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Setup swap if needed (for VMs with less memory)
TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
if [[ $TOTAL_MEM -lt 64 ]]; then
    print_warn "Memory is less than 64GB. Setting up 32GB swap..."
    if [[ ! -f /swapfile ]]; then
        sudo fallocate -l 32G /swapfile
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile
        sudo swapon /swapfile
        echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    fi
fi

# Set ulimits for large builds
print_info "Configuring system limits..."
echo "* soft nofile 65535" | sudo tee -a /etc/security/limits.conf
echo "* hard nofile 65535" | sudo tee -a /etc/security/limits.conf

# Verify Java
print_info "Verifying Java installation..."
java -version

print_success "=========================================="
print_success "Build environment setup complete!"
print_success "=========================================="
echo ""
print_info "Build directory: $BUILD_DIR"
print_info "ccache size: $CCACHE_SIZE"
print_info "ccache dir: ${CCACHE_DIR:-/tmp/ccache}"
echo ""
print_info "Next step: Run build-pixelos.sh to start building!"
echo ""
print_warn "You may need to log out and back in for all changes to take effect."

# PixelOS A16 Initialization Helper
print_info "=========================================="
print_info "PixelOS A16 Initialization Helper"
print_info "=========================================="
echo ""
echo "To initialize the PixelOS A16 repository, run:"
echo "  repo init -u https://review.pixelos.net/platform/manifest -b sixteen --git-lfs"
echo ""
echo "To sync the source code, run:"
echo "  repo sync -c -j\$(nproc --all) --force-sync --no-clone-bundle --no-tags"
echo ""
