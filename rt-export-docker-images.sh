#!/bin/bash

# Script to export Docker images from JFrog Artifactory and generate Prometheus metrics.
# Author: Mahyar Damavand
# Date: 2024-12-29
# Version: 1.1

# Import credentials if exists
[ -f .env ] && source .env

# Defaults
DEFAULT_JFROG_URL="jfrog.example.com"
DEFAULT_TARGET_DIR="/tmp/registry-sync"
DEFAULT_JF_ACCESS_TOKEN="JF-ACCESS-TOKEN"
DEFAULT_METRICS_FILE="/var/log/registry-sync-metrics.prom"

# Constants
JFROG_URL=${JFROG_URL:-$DEFAULT_JFROG_URL}
URL="https://$JFROG_URL/artifactory/api/search/aql"
HEADER_TYPE="Content-type: text/plain"
JF_ACCESS_TOKEN=${JF_ACCESS_TOKEN:-$DEFAULT_JF_ACCESS_TOKEN}
HEADER_AUTH="Authorization: Bearer $JF_ACCESS_TOKEN"
TARGET_DIR=${TARGET_DIR:-$DEFAULT_TARGET_DIR}
METRICS_FILE=${METRICS_FILE:-$DEFAULT_METRICS_FILE}
LOCK_FILE="$TARGET_DIR/.sync-docker.lock"

# Metrics variables
script_start_time=$(date +%s)
success_count=0
failure_count=0
overall_status=0

# Function for logging
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: $1" >&1
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: $1" >&2
}

# Ensure to be the master and not a secondry instance
if [[ -e $LOCK_FILE ]]; then
    log_error "Another instance is running. Remove $LOCK_FILE if you know what you do."
    exit 1
else
    # Make sure TARGET_DIR exists
    mkdir -p "$TARGET_DIR"

    touch $LOCK_FILE
fi

# Function to write metrics to file
write_metrics() {
    local script_end_time=$(date +%s)
    local script_duration=$((script_end_time - script_start_time))

    cat <<EOF > "$METRICS_FILE"
# HELP jfrog_sync_last_timestamp_seconds Unix timestamp of the last script execution
# TYPE jfrog_sync_last_timestamp_seconds gauge

# HELP jfrog_sync_last_duration_seconds Duration of the last script execution in seconds
# TYPE jfrog_sync_last_duration_seconds gauge

# HELP jfrog_sync_images_total Total number of images processed by the script
# TYPE jfrog_sync_images_total counter

# HELP jfrog_sync_status Sync script execution status (1 = successful, 0 = unsuccessful).
# TYPE jfrog_sync_status gauge

jfrog_sync_last_timestamp_seconds{action="export",repo="docker"} $script_start_time
jfrog_sync_last_duration_seconds{action="export",repo="docker"} $script_duration
jfrog_sync_images_total{action="export",repo="docker",status="success"} $success_count
jfrog_sync_images_total{action="export",repo="docker",status="failure"} $failure_count
jfrog_sync_status{action="export",repo="docker"} $overall_status
EOF
}

cleanup() {
    # Keep script running until we can remove lock file
    while ! rm -f $LOCK_FILE &>/dev/null; do sleep 1; done
}

# Trap to ensure metrics are written on exit
trap 'overall_status=$(($? == 0 ? 1 : 0)); write_metrics; cleanup' EXIT

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

# Export images
for img in $images; do
    image_ref="$JFROG_URL/docker/$img"
    image_file="$TARGET_DIR/docker-image-$(echo -n "$img" | base64 -w0).tar.gz"
    log_info "Exporting image: $image_ref to file: $image_file"
    
    regctl image export -p local --compress "$image_ref" > "$image_file"
    if [ $? -ne 0 ]; then
        log_error "Failed to export image: $image_ref"
        ((failure_count++))
        continue
    fi
    ((success_count++))
done

log_info "Docker image export process completed successfully."
exit 0
