# SELinux approach

- Host policy (`selinux/allow-container-autofs.te`) lets containers (`container_t`) traverse autofs roots (`autofs_t`) so `/home` (indirect map) can be listed.
- Autofs mounts specify `context=system_u:object_r:container_file_t:s0` so mounted NFS content is accessible by containers.

Install policy on RHCOS via MachineConfig (see `selinux/` folder for building `.pp` and applying `machineconfig-allow-container-autofs.yaml`).

Validation:
```bash
oc debug node/<worker> -- chroot /host semodule -l | grep allow-container-autofs
oc -n automount-nfs-poc exec -l app=automount -- timeout 5 ls -la /var/mnt/home || true
```
