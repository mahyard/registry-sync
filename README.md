# Sync JFrog Artifactory Docker Images

This repository presents my approach to synchronizing two disconnected instances of JFrog Artifactory using export/import processes with storage.

## How to setup
Provide the environmet settings:

```bash
cat <<TXT > .env
JF_ACCESS_TOKEN=asdfxyz
JFROG_URL=jfrog.example.com
TARGET_DIR=/tmp/registry-sync
TXT
```

Use a systemd service and timer to schedule its execution.

A sample unit:
```text
[Unit]
Description=Download docker images from Jfrog Artifactory and save them to diode

[Service]
WorkingDirectory=/opt/jfrog_downloader
ExecStart=/opt/jfrog_downloader/export-artifactory.sh
```

A sample timer:
```text
[Unit]
Description=Download docker images from Jfrog Artifactory and save them to diode

[Service]
WorkingDirectory=/opt/jfrog_downloader
ExecStart=/opt/jfrog_downloader/export-artifactory.sh
```
