#!/bin/bash

# Install nfs server utils and ldap clients
dnf install nfs-utils openldap-clients -y

# Make nfsd pseudo-filesystem available inside the container
mount -t nfsd nfsd /proc/fs/nfsd

# Start NFS daemons
/usr/sbin/rpcbind -w
/usr/sbin/rpc.mountd   # mountd is required for v2/v3; use defaults
/usr/sbin/rpc.statd --no-notify

# Configure NFS versions: enable v3 only (disable v2 and v4)
echo 0 > /proc/fs/nfsd/threads || true
echo "-2 +3 -4" > /proc/fs/nfsd/versions || true
/usr/sbin/rpc.nfsd 8

# Create directories
for CITY in dallas tucson sandiego; do
  # Create exported directory if it doesn't exit
  mkdir -p /exports/$CITY
  # allow wide open access
  chmod 777 /exports/$CITY
  # create a test file
  echo $CITY > /exports/$CITY/$CITY.txt
done

# Create sample home directories and set ownership from users.csv
if [ -f /toolbox/users.csv ]; then
  while IFS=, read -r USERNAME USER_UID USER_GID; do
    [ -z "$USERNAME" ] && continue
    mkdir -p "/exports/home/$USERNAME"
    chmod 755 "/exports/home/$USERNAME"
    chown ${USER_UID}:${USER_GID} "/exports/home/$USERNAME"
    touch "/exports/home/$USERNAME/.placeholder"
  done < /toolbox/users.csv
fi

# Shared tooling directory
mkdir -p /exports/home/xyz
chmod 777 /exports/home/xyz

# If LDAP is available, generate users.csv from LDAP
if getent hosts ldap.automount-nfs-poc.svc.cluster.local &>/dev/null; then
  ldapsearch -x -H ldap://ldap.automount-nfs-poc.svc.cluster.local:389 -b dc=example,dc=org "(objectClass=posixAccount)" uid uidNumber gidNumber homeDirectory \
    | awk '/^uid: /{u=$2}/^uidNumber: /{uid=$2}/^gidNumber: /{gid=$2}/^homeDirectory: /{home=$2} /^$/{if(u&&uid&&gid){print u","uid","gid; u=uid=gid=home=""}} END{if(u&&uid&&gid){print u","uid","gid}}' > /toolbox/users.csv || true
fi

# Add the exports directory to the list of exported dirs
echo "/exports *(rw,fsid=0,async,root_squash)" > /etc/exports.d/city.exports
echo "/exports/home *(rw,async,root_squash)" > /etc/exports.d/home.exports

# Export city directory via nfs
exportfs -r

# Show current nfs exports
showmount -e
