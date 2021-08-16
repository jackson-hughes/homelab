#cloud-config
# https://cloudinit.readthedocs.io/en/latest/topics/examples.html
users:
  - name: jhughes
    primary_group: jhughes
    groups: wheel
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
     - "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCoiyPVqPGXbHXs4+NnxRYluBrTzCYkV1X2LOqaE4eG7QQHDMHbUgEiry03zNn2iJzMLgHuraGWPF4Txs1lnEo3KVxCgAe9h4NgTtQAZxP6wydTLZUcLHWIA2mtOWvY2egBvY/vfJytHD22inAArGlcN4O17WGcd5WaCAl+Wo2azY0erMDX2otSMAlEnihnH2ucacQf28CQgFBY5mQ6yZ9isoeJEHlsCC/5eV8qGJuwoVWW2MwdY90InEQE9Cd0qO/+ZC30PFZhNZwAhQLXcl9xE454kauWwd9SrJSKtgjscLBFi9X0rUwEvl2+cMQYaEhuzVvQbOsk0ey+mKhX4U41lEU/2oxcrvrn13lVvcY+Ve1YLyNeiXDl36XCnfSgo1c/sUCDvpwYd1Cw3oroS7Gux6b0oZMyE/RJVFCgbNcFD2CHlNfzmpQFplScOMfj19oKHVrxkAN7ByPCyvB7i55TPkTZRbfxegI2sQ3uAADLfDxqcVogfyiLpYzJe6FeHk8eEtcQp6AiygQnFgb53iW9fPFjVw7ATjPXj5pcr4fs2gUM8rlIjBursCxa5Tg71QZaXVP1Rntd4gSMlawJd1cfGNFgB4YscYv4glacUAkz0tQMh4+jHQlPTx1t2X7L+d5vTvqV0TWOqMdlmirKPF5avkmwugLH9FYJpjHdy1xNgw== jhughes@carbon"
fqdn: ${hostname}
packages:
  - bind-utils
  - firewalld
runcmd:
  - systemctl enable --now firewalld
  - yum update \-y
  - reboot
