#!/bin/bash

# AutoPkg Installation Script
# This script installs AutoPkg and sets up recipe repositories on macOS
# Based on: https://github.com/autopkg/autopkg/wiki/Getting-Started

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
AUTOPKG_REPO_URL="https://github.com/autopkg/autopkg/releases"
TEMP_DIR=$(mktemp -d)
AUTOPKG_INSTALL_PKG="${TEMP_DIR}/AutoPkg.pkg"

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_macos() {
    if [[ "$(uname)" != "Darwin" ]]; then
        log_error "This script is designed for macOS only"
        exit 1
    fi
}

check_autopkg_installed() {
    if command -v autopkg &> /dev/null; then
        log_info "AutoPkg appears to be already installed"
        autopkg --version
        
        # Support non-interactive mode via environment variable
        if [[ "${NON_INTERACTIVE:-}" == "1" ]] || [[ "${FORCE_REINSTALL:-}" == "1" ]]; then
            log_info "Non-interactive mode: proceeding with reinstall"
            return 0
        fi
        
        read -p "Do you want to reinstall? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Installation cancelled"
            exit 0
        fi
    fi
}

check_git() {
    if command -v git &> /dev/null; then
        log_info "Git is already installed: $(git --version)"
        return 0
    fi
    
    log_warn "Git is not installed. AutoPkg requires Git for recipe management."
    log_info "Attempting to install Git via Xcode Command Line Tools..."
    
    # Check if command line tools are installed
    if [[ -d "/Library/Developer/CommandLineTools" ]]; then
        log_info "Xcode Command Line Tools directory exists"
        # Try to install/update via xcode-select
        if xcode-select --install 2>&1 | grep -q "already installed"; then
            log_info "Command Line Tools appear to be installed"
            # Try to set the path
            if [[ -d "/Library/Developer/CommandLineTools" ]]; then
                export PATH="/Library/Developer/CommandLineTools/usr/bin:${PATH}"
            fi
        else
            log_warn "Command Line Tools installation dialog may have appeared"
            log_warn "Please complete the installation if prompted, then run this script again"
        fi
    else
        log_info "Prompting for Xcode Command Line Tools installation..."
        xcode-select --install || true
        log_warn "Please complete the Xcode Command Line Tools installation, then run this script again"
        exit 1
    fi
    
    # Verify git is now available
    if ! command -v git &> /dev/null; then
        log_error "Git installation failed. Please install Git manually and run this script again."
        log_info "You can install Git by running: xcode-select --install"
        exit 1
    fi
    
    log_info "Git installed successfully: $(git --version)"
}

get_latest_version() {
    log_info "Fetching latest AutoPkg release information..."
    
    # Get the latest release info from GitHub API
    RELEASE_INFO=$(curl -s https://api.github.com/repos/autopkg/autopkg/releases/latest)
    
    # Extract version tag
    LATEST_VERSION=$(echo "$RELEASE_INFO" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || echo "")
    
    # Get the actual download URL for the .pkg file from browser_download_url
    AUTOPKG_DOWNLOAD_URL=$(echo "$RELEASE_INFO" | grep '"browser_download_url".*\.pkg"' | cut -d '"' -f 4 | head -1 || echo "")
    
    if [[ -z "$LATEST_VERSION" ]] || [[ -z "$AUTOPKG_DOWNLOAD_URL" ]]; then
        log_error "Could not determine latest version or download URL from GitHub API"
        log_error "Please download AutoPkg manually from: ${AUTOPKG_REPO_URL}"
        exit 1
    fi
    
    log_info "Latest version: ${LATEST_VERSION}"
    log_info "Download URL: ${AUTOPKG_DOWNLOAD_URL}"
}

download_autopkg() {
    log_info "Downloading AutoPkg from ${AUTOPKG_DOWNLOAD_URL}..."
    
    # Download the pkg file
    if curl -L -f -o "${AUTOPKG_INSTALL_PKG}" "${AUTOPKG_DOWNLOAD_URL}"; then
        log_info "Download completed successfully"
        
        # Verify the file was downloaded and has content
        if [[ ! -f "${AUTOPKG_INSTALL_PKG}" ]] || [[ ! -s "${AUTOPKG_INSTALL_PKG}" ]]; then
            log_error "Downloaded file is missing or empty"
            return 1
        fi
        
        log_info "Package size: $(du -h "${AUTOPKG_INSTALL_PKG}" | cut -f1)"
        return 0
    else
        log_error "Failed to download AutoPkg installer"
        log_error "Please download manually from: ${AUTOPKG_REPO_URL}"
        return 1
    fi
}

install_autopkg() {
    log_info "Installing AutoPkg..."
    
    if [[ ! -f "${AUTOPKG_INSTALL_PKG}" ]]; then
        log_error "Installer package not found: ${AUTOPKG_INSTALL_PKG}"
        return 1
    fi
    
    # Install the package using installer command line to bypass Gatekeeper
    # This is recommended in the AutoPkg documentation for unsigned packages
    log_info "Installing AutoPkg package (this may require Gatekeeper approval)..."
    
    if installer -pkg "${AUTOPKG_INSTALL_PKG}" -target /; then
        log_info "AutoPkg installation completed successfully"
        
        # Verify installation
        if command -v autopkg &> /dev/null; then
            log_info "Verification: AutoPkg installed successfully"
            autopkg --version
            return 0
        else
            log_warn "Installation completed but autopkg command not found in PATH"
            log_info "You may need to restart your terminal or source your shell profile"
            return 1
        fi
    else
        log_error "Installation failed"
        log_warn "If you see a Gatekeeper warning, you can:"
        log_warn "1. Open the pkg from Finder with right-click > Open"
        log_warn "2. Or use: sudo installer -pkg ${AUTOPKG_INSTALL_PKG} -target /"
        return 1
    fi
}

configure_munki_repo() {
    if [[ -n "${MUNKI_REPO:-}" ]]; then
        log_info "Configuring AutoPkg for Munki repository: ${MUNKI_REPO}"
        
        if [[ -d "${MUNKI_REPO}" ]]; then
            defaults write com.github.autopkg MUNKI_REPO "${MUNKI_REPO}"
            log_info "MUNKI_REPO preference set successfully"
        else
            log_warn "MUNKI_REPO path does not exist: ${MUNKI_REPO}"
            log_warn "Skipping Munki repository configuration"
            log_warn "You can set it manually with:"
            log_warn "  defaults write com.github.autopkg MUNKI_REPO /path/to/munki_repo"
        fi
    else
        log_info "MUNKI_REPO not set. Skipping Munki configuration."
        log_info "To configure later, run:"
        log_info "  defaults write com.github.autopkg MUNKI_REPO /path/to/munki_repo"
    fi
}

install_recipes() {
    log_info "Installing AutoPkg recipe repositories..."
    
    # The standard recipes repo
    if autopkg repo-add recipes --quiet 2>/dev/null; then
        log_info "Recipe repository 'recipes' added successfully"
    else
        # Check if it's already added
        if autopkg repo-list | grep -q "com.github.autopkg.recipes"; then
            log_info "Recipe repository 'recipes' is already installed"
        else
            log_warn "Failed to add recipe repository. You can add it manually with:"
            log_warn "  autopkg repo-add recipes"
        fi
    fi
    
    log_info "Available recipe repositories:"
    autopkg repo-list || true
}

cleanup() {
    log_info "Cleaning up temporary files..."
    rm -rf "${TEMP_DIR}"
}

# Main execution
main() {
    log_info "Starting AutoPkg installation..."
    
    check_macos
    check_root
    check_autopkg_installed
    check_git
    get_latest_version
    
    # Trap to ensure cleanup on exit
    trap cleanup EXIT
    
    if download_autopkg; then
        if install_autopkg; then
            # Configure Munki repo if provided
            configure_munki_repo
            
            # Install recipe repositories
            install_recipes
            
            log_info ""
            log_info "AutoPkg installation completed successfully!"
            log_info ""
            log_info "Next steps:"
            log_info "1. View available recipes: autopkg list-recipes"
            log_info "2. Get info on a recipe: autopkg info RecipeName.munki"
            log_info "3. Run a recipe: autopkg run -v RecipeName.munki"
            log_info "4. Configure Munki repo: defaults write com.github.autopkg MUNKI_REPO /path/to/munki_repo"
            log_info ""
            log_info "For more information, see: https://github.com/autopkg/autopkg/wiki/Getting-Started"
        else
            log_error "Installation failed"
            exit 1
        fi
    else
        log_error "Download failed"
        exit 1
    fi
}

# Run main function
main "$@"

