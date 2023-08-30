manage_local_users:
  user.present:
    - name: jhughes
    - empty_password: True

/home/jhughes/.ssh/authorized_keys:
  file.managed:
    - source: https://github.com/jackson-hughes.keys
    - user: jhughes
    - group: jhughes
    - mode: 600
    - skip_verify: True
