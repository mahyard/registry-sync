#!/bin/bash

# Script to export Docker images from JFrog Artifactory.
# Author: Mahyar Damavand
# Date: 2024-12-29
# Version: 1.0

# Import credentials if exists
[ -f .env ] && source .env

# Defaults
DEFAULT_JFROG_URL="jfrog.example.com"
DEFAULT_TARGET_DIR="/tmp/registry-sync"
DEFAULT_JF_ACCESS_TOKEN="JF-ACCESS-TOKEN"

# Constants
JFROG_URL=${JFROG_URL:-$DEFAULT_JFROG_URL}
URL="https://$JFROG_URL/artifactory/api/search/aql"
HEADER_TYPE="Content-type: text/plain"
JF_ACCESS_TOKEN=${JF_ACCESS_TOKEN:-$DEFAULT_JF_ACCESS_TOKEN}
HEADER_AUTH="Authorization: Bearer $JF_ACCESS_TOKEN"
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

# AQL Query to find relevant Docker image manifests
AQL_EXP=$(cat <<'EOF'
items.find({
    "$or": [
        {
            "$and": [
                {"repo": "docker"},
                {"path": {"$nmatch": "*/sha256__*"}},
                {"name": {"$match": "*manifest.json"}}
            ]
        }
    ]
}).include("name", "repo", "path", "sha256", "size")
EOF
)

log_info "Starting Docker image export process."

# Fetch the list of images using the AQL query
log_info "Executing AQL query to fetch image manifests."
response=$(curl -s -X POST "$URL" -H "$HEADER_TYPE" -H "$HEADER_AUTH" -d "$AQL_EXP")
if [ $? -ne 0 ]; then
    log_error "Failed to execute curl command. Response: $response"
    exit 1
fi

# Extract and process image paths
log_info "Processing response to extract image paths."
images=$(echo "$response" | jq -r '.results[].path' | sed -r 's#(.*)/(.*)#\1:\2#' | sort -u)
if [ -z "$images" ]; then
    log_info "No images found to export."
    exit 0
fi

# Make sure TARGET_DIR exists
mkdir -p $TARGET_DIR

# Export images
for img in $images; do
    image_ref="$JFROG_URL/docker/$img"
    image_file="$TARGET_DIR/docker-image-$(echo -n "$img" | base64).tar.gz"
    log_info "Exporting image: $image_ref to file: $image_file"
    
    regctl image export -p local --compress "$image_ref" > "$image_file"
    if [ $? -ne 0 ]; then
        log_error "Failed to export image: $image_ref"
        continue
    fi
done

log_info "Docker image export process completed successfully."
exit 0
