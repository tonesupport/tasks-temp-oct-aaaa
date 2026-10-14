# Examples
`tasks.patch` was made with almanac on a copy of the snapshot: two adds, one set, and one done. It passes:
    python3 check.py examples/tasks.patch
(It predates the >change notes protocol, so check.py WARNs that the touched tasks have no `>change` line.)
The ids mcd7 and 8zg9 were allocated at build time. Your own run will get different ones.
