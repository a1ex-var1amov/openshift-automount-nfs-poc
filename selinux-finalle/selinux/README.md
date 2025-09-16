# SELinux host policy option for browseable autofs mounts in containers

This folder contains a minimal SELinux policy that allows containers (container_t) to traverse and read autofs_t directories. It addresses the issue where pods cannot browse the autofs indirect mountpoint (e.g., /var/mnt/home) even though individual submounts work.

## Files
- allow-container-autofs.te: policy source (Type Enforcement) permitting container_t to traverse autofs_t dirs/links.
- machineconfig-allow-container-autofs.yaml: MachineConfig that deploys the compiled policy to worker nodes and loads it via a one-shot systemd unit.

## Rationale
- Autofs creates an indirect mount point labeled autofs_t. Default policy denies container_t from traversing it, causing `ls /var/mnt/home` to fail while `ls /var/mnt/home/<user>` may succeed after an automount trigger.
- This policy grants least-privilege read/traverse permissions without broadening access to other types.

## How to build locally
On a RHEL/Fedora host with SELinux toolchain:

```
checkmodule -M -m -o allow-container-autofs.mod allow-container-autofs.te
semodule_package -o allow-container-autofs.pp -m allow-container-autofs.mod
```

This produces `allow-container-autofs.pp`.

## Deploy cluster-wide on OpenShift (RHCOS)
Embed the `.pp` into a MachineConfig and let MCO roll it out to workers.

1) Base64-encode the policy package:

```
BASE64_PP=$(base64 -w0 allow-container-autofs.pp)
```

2) Create `machineconfig-allow-container-autofs.yaml` with the following content (replace `<BASE64_OF_PP>`):

```
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  name: 98-allow-container-autofs
  labels:
    machineconfiguration.openshift.io/role: worker
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - path: /etc/selinux/allow-container-autofs.pp
        mode: 0644
        contents:
          source: data:text/plain;base64,<BASE64_OF_PP>
    systemd:
      units:
      - name: selinux-install-autofs-policy.service
        enabled: true
        contents: |
          [Unit]
          Description=Install SELinux policy to allow container_t to traverse autofs_t
          After=network-online.target
          ConditionPathExists=/etc/selinux/allow-container-autofs.pp

          [Service]
          Type=oneshot
          ExecStart=/usr/sbin/semodule -i /etc/selinux/allow-container-autofs.pp
          RemainAfterExit=yes

          [Install]
          WantedBy=multi-user.target
```

3) Apply the MachineConfig:

```
oc apply -f machineconfig-allow-container-autofs.yaml
```

4) Wait for MachineConfigPool to update workers:

```
oc get mcp
oc describe mcp worker
```

5) Verify on a worker node:

```
semodule -l | grep allow-container-autofs
```

6) Validate from the automount pod:

```
oc exec -n automount-nfs-poc -l app=automount -- timeout 10 ls -la /var/mnt/home
```

## Notes
- This is a host-level change affecting all containers on the labeled nodes.
- Keep the policy minimal; the provided rules only allow read/traverse of autofs mountpoints.
- Alternative: avoid autofs_t entirely by pre-mounting NFS on the host to a static path labeled `container_file_t` and using HostPath into pods.

# Breakdown of `allow-container-autofs.te`

## Module Declaration

``` te
module allow-container-autofs 1.0;
```

Declares a named policy module (`allow-container-autofs`) with version
1.0.\
This is required by `semodule` for install/upgrade.

------------------------------------------------------------------------

## Requirements

``` te
require {
    type container_t;
    type autofs_t;
    class dir { getattr search open read };
    class lnk_file { read getattr };
}
```

-   **type container_t**\
    Domain type for most container processes on OpenShift (the confined
    process type your pods run as).

-   **type autofs_t**\
    Type for autofs-managed mountpoints (the indirect root like
    `/var/mnt/home`).

-   **class dir { getattr search open read }**\
    Represents the directory object class. Grants specific read/traverse
    permissions on directories labeled `autofs_t`.

-   **class lnk_file { read getattr }**\
    Represents the symlink object class. Grants permissions for reading
    symlink metadata and targets.

------------------------------------------------------------------------

## Allow Rules

### Directory Permissions

``` te
allow container_t autofs_t:dir { getattr search open read };
```

Grants container processes (`container_t`) the **minimum** directory
permissions on `autofs_t` directories: - `getattr`: Read metadata (e.g.,
`ls -ld`, `stat`). - `search`: Traverse permission (needed to walk into
the directory). - `open`: Allow opening the directory handle (needed by
list operations). - `read`: Read directory entries (needed for
listing/`ls`).

**Effect:** Enables "parent browse" of the autofs mount root (e.g.,
`ls -la /var/mnt/home`) so pod processes can see the list of users.

------------------------------------------------------------------------

### Symlink Permissions

``` te
allow container_t autofs_t:lnk_file { read getattr };
```

Grants minimal permissions on symlinks under the `autofs_t` mount: -
`getattr`: Get symlink metadata. - `read`: Read the link target (so the
VFS can resolve it).

**Effect:** Allows autofs to present link-like entries during
resolution.

------------------------------------------------------------------------

## Why Only These Permissions?

-   **Principle of least privilege:**\
    Only read/lookup/traverse on the `autofs_t` mountpoint.\
    No write/append/rename/remove permissions → policy doesn't allow
    modifying the autofs root.

-   **NFS writes unaffected:**\
    Actual NFS-mounted directory types (`nfs_t` on host,
    `container_file_t` inside containers via hostPath) and NFS server
    export settings (`root_squash`, UID/GID ownership) control write
    behavior.

------------------------------------------------------------------------

## High-Level Behavior Enabled

-   **Before:** `ls /var/mnt/home` failed/denied from pods
    (`container_t` blocked on `autofs_t`).\
-   **After:** Pods can list/traverse `/var/mnt/home`, discover
    subdirectories, and trigger automount to mount individual user
    directories on-demand.
