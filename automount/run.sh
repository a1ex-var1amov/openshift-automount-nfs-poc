#!/bin/bash

# Install automounter and nfs rpms
dnf install --assumeyes \
  autofs \
  nfs-utils \
  openldap-clients

mkdir -p /mnt/automount
mkdir -p /var/mnt/home

# Set proper permissions for home directory
chmod 755 /var/mnt/home

# Start the autofs in background
automount \
  --foreground \
  --dont-check-daemon \
  --debug &

# Wait a moment for automount to start
sleep 5

# Set permissions on the mount point after automount starts
chmod 755 /var/mnt/home

# Keep the script running
wait
