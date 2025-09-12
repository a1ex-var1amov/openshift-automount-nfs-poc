#!/bin/bash

# Script to list available home directories
# This works around the SELinux limitation that prevents browsing autofs mounts

echo "Available home directories:"
echo "=========================="

# List known users from the users.csv file
if [ -f /toolbox/users.csv ]; then
    while IFS=, read -r USERNAME USER_UID USER_GID; do
        [ -z "$USERNAME" ] && continue
        if [ -d "/home/$USERNAME" ]; then
            echo "✓ /home/$USERNAME (UID: $USER_UID, GID: $USER_GID)"
        else
            echo "✗ /home/$USERNAME (not mounted)"
        fi
    done < /toolbox/users.csv
fi

# Check for shared directories
if [ -d "/home/xyz" ]; then
    echo "✓ /home/xyz (shared directory)"
else
    echo "✗ /home/xyz (not mounted)"
fi

echo ""
echo "Note: Individual directories are accessible, but browsing /home is restricted due to SELinux context limitations on autofs mounts."
