#!/bin/bash

# Script to import Docker images into JFrog Artifactory.
# Author: Mahyar Damavand
# Date: 2024-12-29
# Version: 1.0

# Imporet credentials if exists
[ -f .env ] && source .env

# Defaults
DEFAULT_JFROG_URL="jfrog.example.com"
DEFAULT_TARGET_DIR="/tmp/registry-sync"

# Constants
JFROG_URL=${JFROG_URL:-$DEFAULT_JFROG_URL}
TARGET_DIR=${TARGET_DIR:-$DEFAULT_TARGET_DIR}

# Function for logging
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: $1" >&1
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: $1" >&2
}

# Check user running the script
if [ "$(id --user --name)" != "root" ]; then
    log_error "Script can only be run as root"
    exit 1
fi

log_info "Starting Docker image import process."

# Make sure TARGET_DIR exists
mkdir -p $TARGET_DIR

# Import images
for img in $(ls "$TARGET_DIR"/docker-image-*tar.gz 2>/dev/null); do
    decoded_name=$(echo "$(basename "$img")" | sed -r 's/docker-image-(.*).tar.gz/\1/' | base64 -d)
    image_ref="$JFROG_URL/docker/${decoded_name//library\//}"
    log_info "Importing image from file: $img to reference: $image_ref"

    regctl image import "$image_ref" "$img"
    if [ $? -ne 0 ]; then
        log_error "Failed to import image: $img"
        continue
    fi
done

log_info "Docker image import process completed successfully."
exit 0
