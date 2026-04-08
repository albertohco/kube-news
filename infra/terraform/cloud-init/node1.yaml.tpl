#cloud-config
hostname: rke2-node-1
fqdn: rke2-node-1.local
manage_etc_hosts: true

ssh_pwauth: true
chpasswd:
  list: |
    ubuntu:${vm_password}
  expire: false

users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    ssh_authorized_keys:
      - ${ssh_public_key}

# Desabilita systemd-resolved e configura DNS ANTES de tudo
bootcmd:
  - systemctl stop systemd-resolved
  - systemctl disable systemd-resolved
  - rm -f /etc/resolv.conf
  - printf "nameserver ${dns_server_1}\nnameserver ${dns_server_2}\nnameserver 8.8.8.8\n" > /etc/resolv.conf

package_update: true
package_upgrade: false

packages:
  - curl
  - open-iscsi
  - nfs-common
  - qemu-guest-agent

# Cria config do RKE2 sem problemas de indentação
write_files:
  - path: /etc/rancher/rke2/config.yaml
    owner: root:root
    permissions: '0600'
    content: |
      token: ${rke2_token}
      tls-san:
        - rke2-node-1
        - rke2-node-1.local
        - ${node1_ip}

runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE=server sh -
  - systemctl enable rke2-server.service
  - systemctl start rke2-server.service
  - |
    TIMEOUT=120
    ELAPSED=0
    until [ -f /etc/rancher/rke2/rke2.yaml ]; do
      if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "AVISO: Timeout aguardando kubeconfig" >&2
        break
      fi
      sleep 5
      ELAPSED=$((ELAPSED + 5))
    done
  - mkdir -p /home/ubuntu/.kube
  - cp /etc/rancher/rke2/rke2.yaml /home/ubuntu/.kube/config || true
  - chown -R ubuntu:ubuntu /home/ubuntu/.kube || true
  - chmod 600 /home/ubuntu/.kube/config || true
  - ln -sf /var/lib/rancher/rke2/bin/kubectl /usr/local/bin/kubectl || true
  # Instala local-path-provisioner e define como StorageClass padrão
  - /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml
  - /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml patch storageclass local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

final_message: "rke2-node-1 bootstrap concluido em $UPTIME segundos"
