#!/bin/bash


###################################
# Prerequisites

# Update the list of packages
sudo apt-get update

# Install pre-requisite packages.
sudo apt-get install -y wget curl

# Get the latest PowerShell version from GitHub API
echo "Getting latest PowerShell version..."
LATEST_VERSION=$(curl -s https://api.github.com/repos/PowerShell/PowerShell/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
echo "Latest version: $LATEST_VERSION"

# Download the PowerShell package file
PACKAGE_NAME="powershell_${LATEST_VERSION#v}-1.deb_amd64.deb"
DOWNLOAD_URL="https://github.com/PowerShell/PowerShell/releases/download/$LATEST_VERSION/$PACKAGE_NAME"
echo "Downloading $PACKAGE_NAME..."
wget "$DOWNLOAD_URL"

###################################
# Install the PowerShell package
sudo dpkg -i "$PACKAGE_NAME"

# Resolve missing dependencies and finish the install (if necessary)
sudo apt-get install -f

# Delete the downloaded package file
rm "$PACKAGE_NAME"

# Start PowerShell Preview
pwsh
