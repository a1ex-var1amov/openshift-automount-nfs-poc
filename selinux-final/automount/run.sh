#!/bin/bash

# Install automounter and nfs rpms
dnf install --assumeyes \
  autofs \
  nfs-utils \
  openldap-clients

mkdir -p /mnt/automount
mkdir -p /var/mnt/nfs-home
mkdir -p /var/mnt/home

# Start the autofs in background
automount \
  --foreground \
  --dont-check-daemon \
  --debug &

# Wait a moment for automount to start
sleep 5

# Create a bind mount solution
# Mount the NFS home directory to a regular directory that can be browsed
while true; do
  # Check if NFS mount is available
  if [ -d "/var/mnt/nfs-home" ] && [ "$(ls -A /var/mnt/nfs-home 2>/dev/null)" ]; then
    # Create a regular directory for bind mounting
    mkdir -p /var/mnt/home-regular
    
    # Bind mount the NFS content to a regular directory
    mount --bind /var/mnt/nfs-home /var/mnt/home-regular
    
    # Set proper permissions on the bind mount
    chmod 755 /var/mnt/home-regular
    chmod 755 /var/mnt/home-regular/* 2>/dev/null || true
    
    # Try to fix SELinux context
    chcon -t public_content_t /var/mnt/home-regular 2>/dev/null || true
    chcon -t public_content_t /var/mnt/home-regular/* 2>/dev/null || true
    
    echo "Bind mount created successfully"
    break
  else
    echo "Waiting for NFS mount to be available..."
  fi
  
  sleep 5
done

# Keep the script running
wait
