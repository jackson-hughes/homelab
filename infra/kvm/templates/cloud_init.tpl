#cloud-config
# https://cloudinit.readthedocs.io/en/latest/topics/examples.html
users:
  - name: jhughes
    primary_group: jhughes
    groups: wheel
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCucbFWSU95hYFbJgst2m2Y4f82OgU2ZZEMO3GuWmelEQqIDlNdbInY4dJ458l/I0LbSOS2ldgoqXxZaeiizHI+SZX+8TPgC7Wp+H15YNrfwtFp4MHLpxvVvfndeKi2Yx+9pXeFLmSb7WGqmAmTXqmcDv3Lk/ihyuQVvyHfovzUjaxEHa44aDosBmZpsfVPEmsyw2AD03xauLfmE3cnnFJu3vqmf2Bk2HWlT8Ufb1iJjqwWfztgZOsRfpfXS37JuXvTdGOeO8govY3PKPZogHu1Fpicsr4VORa5ZKDmA1sLZ/+mmpKYfRULTQH2NVc8K5auDNjN+cWDcHAiZwsQo7N/2IF+Rs8dRU3UlOWWBGR8vpFEg/EW3ZQ9C0tNpkexOBUcJr/s3+7edUYCcdAg2JtvtEMHjcEda5VE3i5qAE2LxMU/9hTY0Z6Tu6RJnQVZMV6cYn1YqWnPwhBV1kdww9VXjknUDD1jlZRFQF9CoHKN6zmPKhAliCtub8akkjlEJoJEBxDIuGzSkNVbAN9WI5ra1n9G/slcvAAfKIks0uqF/2vOM2iPzKUl0IgGsSmlxsvGtjvjCsRm+RTx+XIXzIG7w5+HzkNr+kDyDBVLRMb1xgNvwstCDmanCoXegeUh5XTE4OKQKxTvy2sI/qTO/yGGDty7ebUL14gXSA44hi3hJQ== macbook air"
fqdn: ${hostname}
packages:
  - bind-utils
  - firewalld
  - salt-minion
runcmd:
  - systemctl enable --now firewalld
  - dnf update -y
  - reboot
