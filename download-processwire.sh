#!/bin/bash
# Script to download and extract ProcessWire CMS

set -e

# Configuration
PROCESSWIRE_REPO="processwire/processwire"
VERSION="${1:-latest}"
DESTINATION_PATH="${2:-./app}"
TEMP_DIR="./temp_download"
CLEAN_FIRST="false"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --clean)
            CLEAN_FIRST="true"
            shift
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --destination)
            DESTINATION_PATH="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

echo -e "\033[0;36mProcessWire Download Script\033[0m"
echo -e "\033[0;36m===========================\033[0m"
echo ""

# Clean destination if requested
if [ "$CLEAN_FIRST" = "true" ] && [ -d "$DESTINATION_PATH" ]; then
    echo -e "\033[0;33mCleaning destination folder: $DESTINATION_PATH\033[0m"
    read -p "Are you sure you want to delete all contents of $DESTINATION_PATH? (yes/no): " confirm
    if [ "$confirm" = "yes" ]; then
        rm -rf "${DESTINATION_PATH:?}"/*
        echo -e "\033[0;32mDestination cleaned.\033[0m"
    else
        echo -e "\033[0;33mClean operation cancelled.\033[0m"
    fi
fi

# Create temp directory
if [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
fi
mkdir -p "$TEMP_DIR"

# Cleanup function
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        echo -e "\033[0;36mCleaning up temporary files...\033[0m"
        rm -rf "$TEMP_DIR"
    fi
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Get the latest release or specific version
if [ "$VERSION" = "latest" ]; then
    echo -e "\033[0;36mFetching latest ProcessWire release information...\033[0m"
    RELEASE_URL="https://api.github.com/repos/$PROCESSWIRE_REPO/releases/latest"
    
    if command -v curl &> /dev/null; then
        RELEASE_INFO=$(curl -sL -H "User-Agent: ProcessWire-Downloader" "$RELEASE_URL" 2>/dev/null || echo "")
    elif command -v wget &> /dev/null; then
        RELEASE_INFO=$(wget -qO- --header="User-Agent: ProcessWire-Downloader" "$RELEASE_URL" 2>/dev/null || echo "")
    else
        echo -e "\033[0;31mError: Neither curl nor wget is available.\033[0m"
        exit 1
    fi
    
    if [ -n "$RELEASE_INFO" ]; then
        # Try to parse JSON (requires jq or manual parsing)
        if command -v jq &> /dev/null; then
            DOWNLOAD_URL=$(echo "$RELEASE_INFO" | jq -r '.zipball_url')
            VERSION_TAG=$(echo "$RELEASE_INFO" | jq -r '.tag_name')
        else
            # Fallback: parse manually
            DOWNLOAD_URL=$(echo "$RELEASE_INFO" | grep -o '"zipball_url"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4 | head -n1)
            VERSION_TAG=$(echo "$RELEASE_INFO" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4 | head -n1)
        fi

        if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
            echo -e "\033[0;33mFailed to fetch release info from GitHub API. Using direct download...\033[0m"
            DOWNLOAD_URL="https://github.com/$PROCESSWIRE_REPO/archive/refs/heads/master.zip"
            VERSION_TAG="master"
        elif [ "$VERSION_TAG" = "null" ]; then
            VERSION_TAG="latest"
        else
            echo -e "\033[0;32mLatest version: $VERSION_TAG\033[0m"
        fi
    else
        echo -e "\033[0;33mFailed to fetch release info. Using master branch...\033[0m"
        DOWNLOAD_URL="https://github.com/$PROCESSWIRE_REPO/archive/refs/heads/master.zip"
        VERSION_TAG="master"
    fi
else
    echo -e "\033[0;36mFetching ProcessWire version: $VERSION\033[0m"
    DOWNLOAD_URL="https://github.com/$PROCESSWIRE_REPO/archive/refs/tags/$VERSION.zip"
    VERSION_TAG="$VERSION"
fi

# Download ProcessWire
ZIP_FILE="$TEMP_DIR/processwire.zip"
echo -e "\033[0;36mDownloading ProcessWire from: $DOWNLOAD_URL\033[0m"

if command -v curl &> /dev/null; then
    curl -L -H "User-Agent: ProcessWire-Downloader" -o "$ZIP_FILE" "$DOWNLOAD_URL"
elif command -v wget &> /dev/null; then
    wget --header="User-Agent: ProcessWire-Downloader" -O "$ZIP_FILE" "$DOWNLOAD_URL"
fi

if [ ! -f "$ZIP_FILE" ]; then
    echo -e "\033[0;31mError: Download failed.\033[0m"
    exit 1
fi

FILE_SIZE=$(du -h "$ZIP_FILE" | cut -f1)
echo -e "\033[0;32mDownload completed: $FILE_SIZE\033[0m"

# Extract the archive
echo -e "\033[0;36mExtracting ProcessWire...\033[0m"
EXTRACT_PATH="$TEMP_DIR/extracted"
mkdir -p "$EXTRACT_PATH"

if command -v unzip &> /dev/null; then
    unzip -q "$ZIP_FILE" -d "$EXTRACT_PATH"
else
    echo -e "\033[0;31mError: unzip is not available. Please install unzip.\033[0m"
    exit 1
fi

# Find the extracted folder (GitHub adds a folder with repo name)
EXTRACTED_FOLDER=$(find "$EXTRACT_PATH" -mindepth 1 -maxdepth 1 -type d | head -n1)

if [ -z "$EXTRACTED_FOLDER" ]; then
    echo -e "\033[0;31mError: Could not find extracted ProcessWire folder\033[0m"
    exit 1
fi

echo -e "\033[0;36mFound extracted folder: $(basename "$EXTRACTED_FOLDER")\033[0m"

# Create destination if it doesn't exist
mkdir -p "$DESTINATION_PATH"

# Copy files to destination
echo -e "\033[0;36mCopying ProcessWire files to $DESTINATION_PATH...\033[0m"

for item in "$EXTRACTED_FOLDER"/* "$EXTRACTED_FOLDER"/.*; do
    if [ "$(basename "$item")" = "." ] || [ "$(basename "$item")" = ".." ]; then
        continue
    fi
    
    if [ ! -e "$item" ]; then
        continue
    fi
    
    ITEM_NAME=$(basename "$item")
    DEST_ITEM="$DESTINATION_PATH/$ITEM_NAME"
    
    if [ -e "$DEST_ITEM" ]; then
        echo -e "  \033[0;33mOverwriting: $ITEM_NAME\033[0m"
        rm -rf "$DEST_ITEM"
    else
        echo -e "  Copying: $ITEM_NAME"
    fi
    
    cp -r "$item" "$DESTINATION_PATH/"
done

echo ""
echo -e "\033[0;32mSUCCESS! ProcessWire has been downloaded and extracted.\033[0m"
echo -e "\033[0;32mLocation: $DESTINATION_PATH\033[0m"
echo -e "\033[0;32mVersion: $VERSION_TAG\033[0m"

# Display next steps
echo ""
echo -e "\033[0;36mNext Steps:\033[0m"
echo -e "\033[0;37m1. Review and configure site/config.php for your database settings\033[0m"
echo -e "\033[0;37m2. Start your Docker containers: docker-compose up -d\033[0m"
echo -e "\033[0;37m3. Access ProcessWire at http://localhost:8088\033[0m"
echo ""

echo -e "\033[0;36mDone!\033[0m"
