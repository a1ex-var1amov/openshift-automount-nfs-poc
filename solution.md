# OpenShift NFS Automount Solution

## Overview

This solution demonstrates how to implement NFS automounting on OpenShift using autofs (automatic filesystem mounting) with mount propagation. The solution enables dynamic mounting of user home directories from an NFS server, allowing users to access their home directories transparently without manual mount operations.

## Architecture Components

### 1. NFS Server (`nfs-server/`)
- **Purpose**: Provides NFS exports for user home directories
- **Implementation**: Single pod deployment with privileged container
- **Key Features**:
  - Exports `/exports/home/*` for individual user directories
  - Exports `/exports/*` for shared directories
  - Creates user directories based on `users.csv` or LDAP integration
  - Sets proper ownership (UID/GID) for each user directory

### 2. Automount DaemonSet (`automount/`)
- **Purpose**: Runs autofs daemon on all worker nodes
- **Implementation**: DaemonSet with privileged container and host access
- **Key Features**:
  - Mounts NFS shares on-demand using autofs
  - Uses mount propagation to make mounts available to other pods
  - Runs with `hostPID: true` and `hostNetwork: true`
  - Mounts host `/var/mnt` directory with bidirectional propagation

### 3. Test Pods (`test-pod/`)
- **Purpose**: Demonstrates user access to automounted home directories
- **Implementation**: Multiple deployments with different user contexts
- **Key Features**:
  - Each pod runs as different user (usera: 2001, userb: 2002, etc.)
  - Mounts host `/var/mnt/home` with `HostToContainer` propagation
  - Accesses user-specific home directories via automount

## How It Works

### 1. NFS Server Setup
```bash
# NFS server creates user directories with proper ownership
mkdir -p /exports/home/$USERNAME
chown ${USER_UID}:${USER_GID} /exports/home/$USERNAME
chmod 755 /exports/home/$USERNAME

# Exports directories via NFS
echo "/exports/home *(rw,async,root_squash)" > /etc/exports.d/home.exports
exportfs -r
```

### 2. Automount Configuration
The automount daemon uses two key configuration files:

**`/etc/extra.autofs`**:
```
/mnt/automount /etc/extra.nfs
/var/mnt/home /etc/auto.home
```

**`/etc/auto.home`**:
```
xyz -rw,vers=3,context=system_u:object_r:container_file_t:s0 172.30.240.59:/exports/home/xyz
*   -rw,vers=3,context=system_u:object_r:container_file_t:s0 172.30.240.59:/exports/home/&
```

### 3. Mount Propagation
- **Automount DaemonSet**: Uses `Bidirectional` mount propagation to mount NFS shares on host
- **Test Pods**: Use `HostToContainer` propagation to access host-mounted directories
- **Result**: Pods can access automounted NFS shares without direct NFS mounting

### 4. User Directory Access
When a pod accesses `/home/usera`, the following happens:
1. Pod mounts `/var/mnt/home` from host
2. Host has automounted `/var/mnt/home/usera` via autofs
3. Pod sees the NFS-mounted directory with proper permissions
4. User can read/write files in their home directory

## Prerequisites

### 1. OpenShift Cluster Requirements
- OpenShift cluster with worker nodes
- Cluster admin privileges for SCC (Security Context Constraint) management
- Ability to create privileged containers

### 2. Required OpenShift Resources
- **Security Context Constraints**: 
  - `privileged` SCC for automount daemon
  - `restricted-hostpath` SCC for test pods
- **Service Accounts**: With appropriate SCC bindings
- **RBAC**: Roles and role bindings for SCC access

### 3. Network Requirements
- NFS server accessible from worker nodes
- Port 2049 (NFS), 20048 (mountd), 111 (rpcbind) open
- DNS resolution for NFS server service

### 4. Storage Requirements
- Persistent volume for NFS server exports
- Sufficient storage for user home directories

## Configuration Files

### Key Configuration Files

1. **`automount/extra.autofs`**: Autofs master map configuration
2. **`automount/extra.nfs`**: NFS mount options
3. **`automount/auto.home`**: User directory mapping rules
4. **`nfs-server/users.csv`**: User definitions (username, UID, GID)
5. **`automount/run.sh`**: Automount daemon startup script
6. **`nfs-server/init.sh`**: NFS server initialization script

### Security Contexts

**Automount DaemonSet**:
```yaml
securityContext:
  privileged: true
hostPID: true
hostNetwork: true
```

**Test Pods**:
```yaml
securityContext:
  runAsUser: 2001
  runAsGroup: 2001
```

## Deployment Steps

1. **Create Namespace**:
   ```bash
   oc apply --kustomize namespace
   ```

2. **Deploy NFS Server**:
   ```bash
   oc apply --kustomize nfs-server
   ```

3. **Get NFS Server IP**:
   ```bash
   oc get svc --namespace automount-nfs-poc nfs-server --output jsonpath='{.spec.clusterIP}'
   ```

4. **Update NFS IP in Configuration**:
   ```bash
   vi automount/extra.nfs
   # Update IP address in the file
   ```

5. **Deploy Automount DaemonSet**:
   ```bash
   oc apply -k automount
   ```

6. **Deploy Test Pods**:
   ```bash
   oc apply --kustomize test-pod
   ```

## Verification

### Check Deployment Status
```bash
# Check all pods are running
oc get pods -n automount-nfs-poc

# Check automount daemonset
oc get daemonsets -n automount-nfs-poc

# Check NFS service
oc get svc -n automount-nfs-poc
```

### Test User Access
```bash
# Test usera access
oc exec -n automount-nfs-poc test-pod-usera-xxx -- ls -la /home/usera

# Test userb access  
oc exec -n automount-nfs-poc test-pod-userb-xxx -- ls -la /home/userb

# Test shared directory access
oc exec -n automount-nfs-poc test-pod-usera-xxx -- ls -la /home/xyz
```

### Check Mount Status
```bash
# Check NFS mounts in test pod
oc exec -n automount-nfs-poc test-pod-usera-xxx -- mount | grep nfs

# Check automount logs
oc logs -n automount-nfs-poc daemonset/automount --tail=20
```

## Current Status

✅ **Working Components**:
- NFS server is running and exporting directories
- Automount daemon is running on all worker nodes
- Test pods can access their respective home directories
- Mount propagation is working correctly
- User permissions are properly set

✅ **Verified Functionality**:
- Users can read/write to their home directories
- Shared directories are accessible to all users
- Automount is dynamically mounting directories on access
- Proper UID/GID mapping is working

## Limitations and Considerations

1. **Security**: Requires privileged containers and host access
2. **Performance**: NFS performance depends on network and storage
3. **Reliability**: Single NFS server creates single point of failure
4. **Scalability**: Limited by NFS server capacity and network bandwidth
5. **Unmounting**: Automount doesn't seem to unmount unused volumes after timeout

## Troubleshooting

### Common Issues

1. **Permission Denied**: Check UID/GID mapping in users.csv
2. **Mount Failures**: Verify NFS server IP and network connectivity
3. **Automount Not Working**: Check automount daemon logs and configuration
4. **SCC Issues**: Ensure proper service account bindings

### Debug Commands

```bash
# Check automount status
oc exec -n automount-nfs-poc daemonset/automount -- automount -l

# Check NFS exports
oc exec -n automount-nfs-poc nfs-server-xxx -- showmount -e

# Check mount propagation
oc exec -n automount-nfs-poc test-pod-xxx -- cat /proc/mounts | grep nfs
```

## References

- [Kubernetes Mount Propagation](https://kubernetes.io/docs/concepts/storage/volumes/#mount-propagation)
- [OpenShift Security Context Constraints](https://docs.openshift.com/container-platform/4.12/authentication/managing-security-context-constraints.html)
- [Autofs Documentation](https://linux.die.net/man/5/autofs)
- [NFS Configuration](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/managing_file_systems/exporting-nfs-shares_managing-file-systems)
