# selinux-finalle

This bundle deploys:
- Automounter DaemonSet (autofs) mounting `/var/mnt/home` from the node
- A test pod (`userb`, UID/GID 2002) consuming `/home` via HostPath

It assumes an external NFS server at 192.168.88.210 exporting:
- `/exports` (fsid=0)
- `/exports/home` (with subdirs `usera`, `userb`, `xyz`)

Quick start:

1) Update NFS IP if different:
- Edit `automount/auto.home` and `automount/extra.nfs` (vers=3)

2) Deploy:
```bash
oc apply -k selinux-finalle/automount
oc apply -k selinux-finalle
```

3) Verify (non-blocking):
```bash
AUTOPOD=$(oc -n automount-nfs-poc get pods -l app=automount -o jsonpath='{.items[0].metadata.name}')
oc -n automount-nfs-poc exec "$AUTOPOD" -- bash -lc 'timeout 5 stat /var/mnt/home/userb || true; mount | grep /var/mnt/home || true'

oc -n automount-nfs-poc exec selinux-test-userb-home -- bash -lc 'timeout 5 stat /home/userb || true; echo ok > /home/userb/ok.txt || true; cat /home/userb/ok.txt || true'
```

Notes:
- `auto.home` uses `context=container_file_t` for mounted NFS so containers can traverse
- `extra.autofs` uses `--browse` to avoid hangs on root listing
