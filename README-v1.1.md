# OpenShift Automount NFS POC - v1.1 Clean Release

## Overview

This is the clean, production-ready version of the OpenShift Automount NFS POC. This release contains only the essential components needed to deploy and run the solution successfully.

## What This Solution Provides

- **Browsable `/home` directory** in OpenShift pods
- **Live NFS persistence** for user home directories
- **SELinux-compliant** implementation
- **Works with regular users** (no root privileges required)

## Quick Start

### Prerequisites
- OpenShift 4.x cluster with admin access
- Node with NFS utilities installed

### Deployment
```bash
# 1. Create namespace
oc apply -f namespace/kustomization.yaml

# 2. Deploy NFS Server
oc apply -f nfs-server/kustomization.yaml

# 3. Deploy LDAP Server
oc apply -f ldap/kustomization.yaml

# 4. Deploy Automount DaemonSet
oc apply -f automount/kustomization.yaml

# 5. Deploy the working solution
oc apply -f test-pod/selinux-fix-scc.yaml
oc apply -f test-pod/selinux-fix-sa.yaml
oc apply -f test-pod/test-pod-deploy-usera-live-nfs.yaml
```

### Testing
```bash
# Test the solution
oc exec -n automount-nfs-poc -l app=test-pod-usera-live-nfs -c test-pod -- ls -la /home
```

## File Structure

### Core Components
- `nfs-server/` - NFS server providing home directory exports
- `ldap/` - LDAP server for user authentication
- `automount/` - Automount daemon managing NFS mounts
- `namespace/` - OpenShift namespace configuration

### Final Working Solution
- `test-pod/test-pod-deploy-usera-live-nfs.yaml` - **Main working solution**
- `test-pod/selinux-fix-scc.yaml` - Security Context Constraint
- `test-pod/selinux-fix-sa.yaml` - Service Account
- `test-pod/network-policy.yaml` - Network security policy

### Documentation
- `solution-final-complete.md` - Complete technical documentation
- `docs/diagrams/` - Architecture diagrams

## Key Features

1. **SELinux Solution**: Uses symlinks to bypass autofs SELinux context limitations
2. **Live NFS**: All file operations go directly to NFS, ensuring persistence
3. **User Access**: Regular users can browse and access home directories
4. **Security**: Works within OpenShift security constraints

## Architecture

```
NFS Server → Automount DaemonSet → Test Pods
    ↓              ↓                    ↓
/exports/home/  /var/mnt/home/    /home (browsable)
```

## Support

For detailed technical information, see `solution-final-complete.md`.

## Version History

- **v1.1**: Clean release with only essential working components
- **backup-development-complete**: Contains all development files and experimental approaches
