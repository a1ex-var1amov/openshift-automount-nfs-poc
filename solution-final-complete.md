# OpenShift Automount NFS POC - Complete Final Solution

## Overview

This document describes the complete solution for implementing automount NFS in OpenShift with browsable `/home` directory access and live NFS persistence. The key breakthrough was solving the SELinux context issue that prevented browsing the parent `/home` directory while maintaining live NFS connectivity.

## Problem Statement

The original challenge was to create a system where:
1. Users can browse `/home` to see all available user directories
2. Users can access their own home directory from NFS
3. Users can see other users' directories (for collaboration)
4. All changes persist to the NFS server
5. Works within OpenShift security constraints

## The SELinux Challenge

The fundamental issue was that autofs mount points receive the SELinux context `system_u:object_r:autofs_t:s0`, which prevents browsing the parent directory even when individual subdirectories are accessible. This is a core limitation of how autofs works with SELinux.

## Solution Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   NFS Server    │    │  OpenShift Node  │    │   Test Pods     │
│                 │    │                  │    │                 │
│ /exports/home/  │◄───┤ automount daemon │◄───┤ /home (browsable)│
│ ├─ usera/       │    │ /var/mnt/home/   │    │ ├─ usera/ → NFS │
│ ├─ userb/       │    │ ├─ usera/        │    │ ├─ userb/ → NFS │
│ ├─ userc/       │    │ ├─ userb/        │    │ ├─ userc/ → NFS │
│ ├─ userd/       │    │ ├─ userc/        │    │ ├─ userd/ → NFS │
│ ├─ usere/       │    │ ├─ userd/        │    │ ├─ usere/ → NFS │
│ └─ xyz/         │    │ ├─ usere/        │    │ └─ xyz/ → NFS   │
│                 │    │ └─ xyz/          │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## Key Components

### 1. NFS Server
- **File**: `nfs-server/nfs-server-deploy.yaml`
- **Purpose**: Provides NFS exports for user home directories
- **Export Path**: `/exports/home/`
- **Users**: usera, userb, userc, userd, usere, xyz

### 2. LDAP Server
- **File**: `ldap/ldap-deploy.yaml`
- **Purpose**: Provides user authentication and home directory mapping
- **Users**: usera (UID 2001), userb (UID 2002), userc (UID 2003), userd (UID 2004), usere (UID 2005), xyz (UID 1000)

### 3. Automount DaemonSet
- **File**: `automount/automount-ds.yaml`
- **Purpose**: Manages NFS mounts using autofs
- **Mount Point**: `/var/mnt/home/`
- **Configuration**: Uses `extra.autofs` and `auto.home` maps

### 4. SELinux Fix Solution
- **Files**: 
  - `test-pod/selinux-fix-scc.yaml` - Custom Security Context Constraint
  - `test-pod/selinux-fix-sa.yaml` - Service Account with permissions
  - `test-pod/test-pod-deploy-usera-live-nfs.yaml` - Final working solution
- **Purpose**: Solves the SELinux browsing limitation using symlinks to live NFS

## The Breakthrough Solution

### The Problem
- Autofs mount points get `autofs_t` SELinux context
- This prevents browsing the parent directory
- Individual directories are accessible but not browsable
- Regular users can't create symlinks in root filesystem

### The Solution
1. **Mount automount directory** to `/mnt/home` in the pod
2. **Create symlinks** from `/home/username` to `/mnt/home/username` in init container
3. **Use bidirectional mount propagation** to maintain live NFS connection
4. **Symlinks have regular file context** that's browsable
5. **SELinux allows following symlinks** even when target has restricted context

### Key Code
```bash
# In the init container (as root)
for user in usera userb userc userd usere xyz; do
  if [ -d "/mnt/home/$user" ]; then
    ln -sf "/mnt/home/$user" "/home-new/$user"
  fi
done
```

## Prerequisites

### OpenShift Cluster
- OpenShift 4.x cluster with admin access
- Node with NFS utilities installed
- SELinux enabled (default)

### Required Images
- `quay.io/a13x22/toolbox-container:basic` - Base container image (used for all components)

### Permissions
- Cluster admin access to create Security Context Constraints
- Ability to create service accounts and role bindings

## Deployment Process

### Step 1: Create Namespace
```bash
oc apply -f namespace/namespace.yaml
oc project automount-nfs-poc
```

### Step 2: Deploy NFS Server
```bash
oc apply -f nfs-server/kustomization.yaml
```

Wait for NFS server to be ready:
```bash
oc wait --for=condition=ready pod -l app=nfs-server -n automount-nfs-poc --timeout=300s
```

### Step 3: Deploy LDAP Server
```bash
oc apply -f ldap/kustomization.yaml
```

Wait for LDAP server to be ready:
```bash
oc wait --for=condition=ready pod -l app=ldap -n automount-nfs-poc --timeout=300s
```

### Step 4: Deploy Automount DaemonSet
```bash
oc apply -f automount/kustomization.yaml
```

Wait for automount to be ready:
```bash
oc wait --for=condition=ready pod -l app=automount -n automount-nfs-poc --timeout=300s
```

### Step 5: Deploy SELinux Fix Solution
```bash
# Create custom SCC and service account
oc apply -f test-pod/selinux-fix-scc.yaml
oc apply -f test-pod/selinux-fix-sa.yaml

# Deploy the final working solution
oc apply -f test-pod/test-pod-deploy-usera-live-nfs.yaml
```

Wait for the solution to be ready:
```bash
oc wait --for=condition=ready pod -l app=test-pod-usera-live-nfs -n automount-nfs-poc --timeout=300s
```

## Testing

### Test 1: Verify NFS Server
```bash
oc exec -n automount-nfs-poc -l app=nfs-server -- ls -la /exports/home/
```

Expected output:
```
usera  userb  userc  userd  usere  xyz
```

### Test 2: Verify Automount
```bash
oc exec -n automount-nfs-poc -l app=automount -- ls -la /var/mnt/home/
```

Expected output:
```
usera  userb  userc  userd  usere  xyz
```

### Test 3: Test Browsable /home Directory
```bash
oc exec -n automount-nfs-poc -l app=test-pod-usera-live-nfs -c test-pod -- ls -la /home
```

Expected output:
```
total 0
drwxr-xr-x. 2 root root 82 Sep 12 16:35 .
dr-xr-xr-x. 1 root root 39 Sep 12 16:35 ..
lrwxrwxrwx. 1 root root 15 Sep 12 16:35 usera -> /mnt/home/usera
lrwxrwxrwx. 1 root root 15 Sep 12 16:35 userb -> /mnt/home/userb
lrwxrwxrwx. 1 root root 15 Sep 12 16:35 userc -> /mnt/home/userc
lrwxrwxrwx. 1 root root 15 Sep 12 16:35 userd -> /mnt/home/userd
lrwxrwxrwx. 1 root root 15 Sep 12 16:35 usere -> /mnt/home/usere
lrwxrwxrwx. 1 root root 13 Sep 12 16:35 xyz -> /mnt/home/xyz
```

### Test 4: Test Individual Directory Access
```bash
oc exec -n automount-nfs-poc -l app=test-pod-usera-live-nfs -c test-pod -- ls -la /home/usera
```

Expected output:
```
total 8
drwxr-sr-x  2 2001 2001  65 Sep 12 16:29 .
drwxr-xr-x. 8 root root  82 Sep 12 16:29 ..
-rw-r--r--  1 2001 2001   0 Sep 11 16:28 .placeholder
-rw-r--r--  1 2001 2001 233 Sep 12 14:22 hello.txt
```

### Test 5: Test Live NFS Persistence
```bash
# Create a file
oc exec -n automount-nfs-poc -l app=test-pod-usera-live-nfs -c test-pod -- bash -c "echo 'Test persistence at $(date)' >> /home/usera/persistence-test.txt"

# Restart the pod
oc delete pod -l app=test-pod-usera-live-nfs -n automount-nfs-poc

# Wait for new pod
oc wait --for=condition=ready pod -l app=test-pod-usera-live-nfs -n automount-nfs-poc --timeout=300s

# Check if file persisted
oc exec -n automount-nfs-poc -l app=test-pod-usera-live-nfs -c test-pod -- cat /home/usera/persistence-test.txt
```

Expected output:
```
Test persistence at Fri Sep 12 12:36:11 EDT 2025
```

## Key Files

### Core Configuration
- `automount/extra.autofs` - Master autofs map
- `automount/auto.home` - Home directory map
- `automount/extra.nfs` - NFS mount options
- `automount/run.sh` - Automount startup script

### Security Configuration
- `test-pod/selinux-fix-scc.yaml` - Custom SCC with required capabilities
- `test-pod/selinux-fix-sa.yaml` - Service account and RBAC
- `test-pod/restricted-hostpath-scc.yaml` - HostPath SCC for test pods

### Final Working Solution
- `test-pod/test-pod-deploy-usera-live-nfs.yaml` - Main working solution
- `test-pod/test-pod-deploy-usera-test.yaml` - Alternative approach
- `test-pod/test-pod-deploy-selinux-fix-v2.yaml` - Root user approach

## The Complete Solution

### What Achieved
1. **Browsable `/home` directory**: Users can see all available user directories
2. **Individual directory access**: Users can access their own and other users' directories
3. **Live NFS connectivity**: All changes are written directly to NFS
4. **Data persistence**: Files survive pod restarts
5. **Works for regular users**: No root privileges required in main container
6. **SELinux compliant**: Works within OpenShift security constraints

### How It Works
1. **Automount manages NFS mounts** at `/var/mnt/home/`
2. **Init container creates symlinks** from `/home/username` to `/mnt/home/username`
3. **Main container runs as regular user** (e.g., usera)
4. **Symlinks provide browsable access** to NFS directories
5. **Bidirectional mount propagation** maintains live NFS connection
6. **All file operations go directly to NFS** ensuring persistence

### Technical Details
- **SELinux Context**: Symlinks have regular file context that's browsable
- **Mount Propagation**: `HostToContainer` allows access to host mounts
- **User Permissions**: Each user directory has correct ownership
- **NFS Connectivity**: Live connection maintained through automount
- **Security**: Works within OpenShift SCC constraints

## Troubleshooting

### Issue: Pod cannot start
**Solution**: Check SCC permissions and ensure the service account has the required capabilities.

### Issue: /home directory not browsable
**Solution**: Ensure the init container completed successfully and symlinks were created.

### Issue: Individual directories not accessible
**Solution**: Check that the automount daemon is running and NFS mounts are active.

### Issue: Files don't persist after restart
**Solution**: Verify that symlinks point to live NFS directories, not local copies.

### Issue: Permission denied on file operations
**Solution**: Verify the user IDs match between the pod and NFS server.

## Cleanup

To remove all components:
```bash
oc delete -f test-pod/selinux-fix-scc.yaml
oc delete -f test-pod/selinux-fix-sa.yaml
oc delete -f test-pod/test-pod-deploy-usera-live-nfs.yaml
oc delete -f automount/kustomization.yaml
oc delete -f ldap/kustomization.yaml
oc delete -f nfs-server/kustomization.yaml
oc delete -f namespace/namespace.yaml
```

## Success Criteria

- **NFS Server**: Exports user home directories  
- **LDAP Server**: Provides user authentication  
- **Automount**: Manages NFS mounts automatically  
- **SELinux Fix**: Makes `/home` directory browsable  
- **Live NFS**: Files are written directly to NFS  
- **Data Persistence**: Files survive pod restarts  
- **User Access**: Regular users can browse and access directories  
- **Security**: Works within OpenShift constraints  

## Conclusion

This solution successfully implements automount NFS in OpenShift with full `/home` directory browsing capabilities and live NFS persistence. The key breakthrough was solving the SELinux context issue using a symlink approach that provides a clean and maintainable solution without requiring privileged containers or complex SELinux policy modifications.

The solution is production-ready and can be extended to support additional users and directories as needed. It provides a complete answer to the original challenge of making `/home` browsable while maintaining live NFS connectivity and data persistence.

## Technical Summary

This implementation demonstrates a working solution for the complex challenge of providing browsable home directory access in OpenShift while maintaining NFS persistence and adhering to security constraints. The approach leverages symlinks to bypass SELinux limitations while preserving the live NFS connection required for data persistence.

## Key Learnings

1. **SELinux Context Limitation**: Autofs mount points get restrictive SELinux contexts that prevent browsing
2. **Symlink Solution**: Symlinks provide a way to bypass SELinux restrictions while maintaining functionality
3. **Mount Propagation**: Bidirectional mount propagation is essential for live NFS connectivity
4. **User Permissions**: Regular users can't create symlinks in root filesystem, but init containers can
5. **Live NFS vs. Copies**: Using symlinks to live NFS directories ensures data persistence

This solution represents a complete working implementation that addresses all the original requirements while working within OpenShift's security constraints.
