# Day-2 storage operations (`playbooks/ops/`)

On-demand operations against the VSP One B26 arrays — **not** a sequence. Unlike
the numbered `01–09` build playbooks (which you run in order to stand the lab
up), these are a menu: reach for one individually when a situation calls for it.
Every play takes `target_serial` and resolves its connection from the vault, so
run them from the **project root** so `ansible.cfg` decrypts the vault.

## Plays

| Play | Type | What it does |
|------|------|--------------|
| `facts-drives.yml` | read-only | Lists physical drives (type codes, capacity, FREE vs in-use). Use it to pick `drive_type_code`s before creating a pool. |
| `facts-ports.yml` | read-only | Lists storage ports (FC/iSCSI, topology, WWN, attributes). |
| `facts-hostgroups.yml` | read-only | Lists host groups; optional `-e '{"ports":[...]}'` to restrict to specific ports. |
| `remove-pool.yml` | **DESTRUCTIVE** | Deletes a DDP pool by id. The pool must be empty first. |
| `remove-hostgroup.yml` | **DESTRUCTIVE** | Unpresents each group's mapped LDEVs, then deletes the group(s). Keeps the LDEVs. |

The destructive plays require `-e confirm=true` and refuse to run without it.

## Examples

```bash
# discovery (safe, read-only)
ansible-playbook playbooks/ops/facts-drives.yml      -e target_serial=810294
ansible-playbook playbooks/ops/facts-ports.yml       -e target_serial=810294
ansible-playbook playbooks/ops/facts-hostgroups.yml  -e target_serial=810294 -e '{"ports":["CL1-A","CL2-A"]}'

# destructive (require confirm=true)
ansible-playbook playbooks/ops/remove-hostgroup.yml -e target_serial=810294 -e confirm=true \
  -e '{"host_groups":[{"name":"hg-node1-810294","port_id":"CL1-A","ldevs":[100]}]}'

ansible-playbook playbooks/ops/remove-pool.yml -e target_serial=810294 -e pool_id=0 -e confirm=true
```

## Teardown order

The array enforces dependencies, so a full unwind must run in this order:

1. **`remove-hostgroup.yml`** — unpresents the mapped LDEVs and deletes the host
   groups. (A host group with LDEVs presented cannot be deleted — this play does
   the unpresent first.)
2. **Delete the LDEVs** — currently `hv_ldev` with `state: absent`; there is no
   dedicated op yet. Add one if this becomes routine.
3. **`remove-pool.yml`** — only succeeds once the pool has no volumes.

Build-up runs the opposite way (pool → LDEVs → host groups); see
`../09-provision-storage.yml`.
