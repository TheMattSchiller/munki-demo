#!/bin/bash

# Munki Installation Script
# This script installs the Munki software management tools on macOS

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
MUNKI_VERSION="${MUNKI_VERSION:-latest}"
MUNKI_REPO_URL="https://github.com/munki/munki/releases/download/${MUNKI_VERSION}"
TEMP_DIR=$(mktemp -d)
MUNKI_INSTALL_PKG="${TEMP_DIR}/munkitools.pkg"

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

check_munki_installed() {
    if [[ -d "/usr/local/munki" ]] && [[ -f "/usr/local/munki/managedsoftwareupdate" ]]; then
        log_info "Munki appears to be already installed at /usr/local/munki"
        
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

get_latest_version() {
    log_info "Fetching latest Munki release information..."
    # Try to get the latest version and download URL from GitHub API
    RELEASE_JSON=$(curl -s https://api.github.com/repos/munki/munki/releases/latest)
    
    LATEST_VERSION=$(echo "$RELEASE_JSON" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || echo "")
    
    if [[ -z "$LATEST_VERSION" ]]; then
        log_warn "Could not determine latest version, using 'latest' tag"
        LATEST_VERSION="latest"
        MUNKI_REPO_URL="https://github.com/munki/munki/releases/download/${LATEST_VERSION}"
    else
        log_info "Latest version: ${LATEST_VERSION}"
        # Always set the base URL for fallback
        MUNKI_REPO_URL="https://github.com/munki/munki/releases/download/${LATEST_VERSION}"
        
        # Find the .pkg asset download URL
        DOWNLOAD_URL=$(echo "$RELEASE_JSON" | grep -o '"browser_download_url": "[^"]*\.pkg"' | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
        
        if [[ -n "$DOWNLOAD_URL" ]]; then
            MUNKI_DOWNLOAD_URL="$DOWNLOAD_URL"
            log_info "Found download URL: ${MUNKI_DOWNLOAD_URL}"
        fi
    fi
}

download_munki() {
    # If we have a direct download URL from the API, use it
    if [[ -n "${MUNKI_DOWNLOAD_URL:-}" ]]; then
        log_info "Downloading Munki from ${MUNKI_DOWNLOAD_URL}..."
        if curl -L -f -o "${MUNKI_INSTALL_PKG}" "${MUNKI_DOWNLOAD_URL}" 2>/dev/null; then
            log_info "Download completed successfully"
            return 0
        fi
    fi
    
    # Fallback: Try constructed URLs
    log_info "Downloading Munki from ${MUNKI_REPO_URL}..."
    
    # Try common pkg filenames
    for pkg_name in "munkitools.pkg" "munkitools-${LATEST_VERSION}.pkg" "munkitools-${LATEST_VERSION#v}.pkg"; do
        if curl -L -f -o "${MUNKI_INSTALL_PKG}" "${MUNKI_REPO_URL}/${pkg_name}" 2>/dev/null; then
            log_info "Download completed successfully"
            return 0
        fi
    done
    
    log_error "Failed to download Munki installer"
    log_error "Please download manually from: https://github.com/munki/munki/releases"
    return 1
}

install_munki() {
    log_info "Installing Munki..."
    
    if [[ ! -f "${MUNKI_INSTALL_PKG}" ]]; then
        log_error "Installer package not found: ${MUNKI_INSTALL_PKG}"
        return 1
    fi
    
    # Install the package
    if installer -pkg "${MUNKI_INSTALL_PKG}" -target /; then
        log_info "Munki installation completed successfully"
        
        # Verify installation
        if [[ -f "/usr/local/munki/managedsoftwareupdate" ]]; then
            log_info "Verification: Munki tools installed successfully"
            /usr/local/munki/managedsoftwareupdate --version 2>/dev/null || true
            return 0
        else
            log_warn "Installation completed but verification failed"
            return 1
        fi
    else
        log_error "Installation failed"
        return 1
    fi
}

configure_munki_plist() {
    log_info "Configuring Munki preferences..."
    
    MUNKI_PLIST="/Library/Preferences/ManagedInstalls.plist"
    REPO_URL="http://192.168.8.25/"
    CLIENT_IDENTIFIER="site_default"
    
    # Create the plist if it doesn't exist
    if [[ ! -f "${MUNKI_PLIST}" ]]; then
        log_info "Creating ${MUNKI_PLIST}..."
        defaults write "${MUNKI_PLIST}" SoftwareRepoURL "${REPO_URL}"
        defaults write "${MUNKI_PLIST}" ClientIdentifier "${CLIENT_IDENTIFIER}"
    else
        # Update existing plist
        defaults write "${MUNKI_PLIST}" SoftwareRepoURL "${REPO_URL}"
        defaults write "${MUNKI_PLIST}" ClientIdentifier "${CLIENT_IDENTIFIER}"
    fi
    
    # Ensure proper ownership and permissions
    chown root:wheel "${MUNKI_PLIST}" 2>/dev/null || true
    chmod 644 "${MUNKI_PLIST}" 2>/dev/null || true
    
    # Verify the settings were applied
    CURRENT_URL=$(defaults read "${MUNKI_PLIST}" SoftwareRepoURL 2>/dev/null || echo "")
    CURRENT_IDENTIFIER=$(defaults read "${MUNKI_PLIST}" ClientIdentifier 2>/dev/null || echo "")
    
    if [[ "${CURRENT_URL}" == "${REPO_URL}" ]] && [[ "${CURRENT_IDENTIFIER}" == "${CLIENT_IDENTIFIER}" ]]; then
        log_info "SoftwareRepoURL configured: ${REPO_URL}"
        log_info "ClientIdentifier configured: ${CLIENT_IDENTIFIER}"
        return 0
    else
        log_warn "Failed to verify Munki configuration"
        return 1
    fi
}

cleanup() {
    log_info "Cleaning up temporary files..."
    rm -rf "${TEMP_DIR}"
}

# Main execution
main() {
    log_info "Starting Munki installation..."
    
    check_macos
    check_root
    check_munki_installed
    get_latest_version
    
    # Trap to ensure cleanup on exit
    trap cleanup EXIT
    
    if download_munki; then
        if install_munki; then
            if configure_munki_plist; then
                log_info "Munki installation and configuration completed successfully!"
                log_info ""
                log_info "Next steps:"
                log_info "1. Run '/usr/local/munki/managedsoftwareupdate' to test the installation"
                log_info "   Or: sudo /usr/local/munki/managedsoftwareupdate"
                log_info "2. Optional: Add /usr/local/munki to your PATH for easier access"
            else
                log_warn "Installation completed but configuration had issues"
            fi
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

