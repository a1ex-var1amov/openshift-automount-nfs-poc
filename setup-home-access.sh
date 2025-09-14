#!/bin/bash

# Script to set up home directory access by creating individual symlinks
# This works around the SELinux limitation that prevents browsing autofs mounts

echo "Setting up home directory access..."

# Create a directory for individual home symlinks
mkdir -p /home-individual

# Function to create symlink for a user if their directory exists
create_home_symlink() {
    local username=$1
    if [ -d "/home/$username" ]; then
        ln -sf "/home/$username" "/home-individual/$username"
        echo "✓ Created symlink for $username"
    else
        echo "✗ Directory /home/$username not found"
    fi
}

# Create symlinks for all users from users.csv
if [ -f /toolbox/users.csv ]; then
    while IFS=, read -r USERNAME USER_UID USER_GID; do
        [ -z "$USERNAME" ] && continue
        create_home_symlink "$USERNAME"
    done < /toolbox/users.csv
fi

# Create symlink for shared directory
create_home_symlink "xyz"

echo "Home directory access setup complete!"
echo "Individual directories are available at /home-individual/"
echo "Example: ls -la /home-individual/userb"
