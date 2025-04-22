#!/bin/bash

# Script to import Docker images into JFrog Artifactory and generate Prometheus metrics.
# Author: Mahyar Damavand
# Date: 2024-12-29
# Version: 1.1

# Import credentials if exists
[ -f .env ] && source .env

# Defaults
DEFAULT_JFROG_URL="jfrog.example.com"
DEFAULT_TARGET_DIR="/tmp/registry-sync"
DEFAULT_METRICS_FILE="/var/log/registry-sync-metrics.prom"

# Constants
JFROG_URL=${JFROG_URL:-$DEFAULT_JFROG_URL}
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

# Ensure to run the task after the export process has completed
if [[ -e $LOCK_FILE ]]; then
    log_error "The export process is ongoing. Remove $LOCK_FILE if you know what you're doing."
    exit 1
fi

# Function to write metrics to file
write_metrics() {
    local script_end_time=$(date +%s)
    local script_duration=$((script_end_time - script_start_time))

    # Merge metrics from this script and export script into one
    # and store it in the node-exporter's textfile collector's directory
    metrics_file_basename=$(basename $METRICS_FILE)
    cat "$METRICS_FILE" - <<EOF > /var/lib/prometheus/node-exporter/$metrics_file_basename

jfrog_sync_last_timestamp_seconds{action="import",repo="docker"} $script_start_time
jfrog_sync_last_duration_seconds{action="import",repo="docker"} $script_duration
jfrog_sync_images_total{action="import",repo="docker",status="success"} $success_count
jfrog_sync_images_total{action="import",repo="docker",status="failure"} $failure_count
jfrog_sync_status{action="import",repo="docker"} $overall_status
EOF
}

# Trap to ensure metrics are written on exit
trap 'overall_status=$(($? == 0)); write_metrics' EXIT
trap 'overall_status=$(($? == 0)); write_metrics' EXIT

# Check user running the script
if [ "$(id --user --name)" != "root" ]; then
    log_error "Script can only be run as root"
    exit 1
fi

log_info "Starting Docker image import process."

# Import images
for img in $(ls "$TARGET_DIR"/docker-image-*tar.gz 2>/dev/null); do
    decoded_name=$(echo "$(basename "$img")" | sed -r 's/docker-image-(.*).tar.gz/\1/' | base64 -d)
    image_ref="$JFROG_URL/docker/${decoded_name//library\//}"
    log_info "Importing image from file: $img to reference: $image_ref"

    regctl image import "$image_ref" "$img"
    if [ $? -ne 0 ]; then
        log_error "Failed to import image: $img"
        ((failure_count++))
        continue
    fi
    ((success_count++))
done

log_info "Docker image import process completed successfully."
exit 0
