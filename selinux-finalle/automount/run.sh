#!/bin/bash

# Install automounter and nfs rpms
dnf install --assumeyes \
  autofs \
  nfs-utils \
  openldap-clients

mkdir -p /mnt/automount
mkdir -p /var/mnt/home

# Start the autofs in background
automount \
  --foreground \
  --dont-check-daemon \
  --debug &

# Keep the script running alongside the foreground automount
wait
