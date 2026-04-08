#cloud-config
hostname: ${hostname}
fqdn: ${hostname}.local
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
      server: https://${node1_ip}:9345
      token: ${rke2_token}

runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  # Aguarda o node-1 estar pronto (timeout 10 minutos)
  - |
    TIMEOUT=600
    ELAPSED=0
    echo "Aguardando rke2-node-1 em ${node1_ip}:9345..."
    until curl -sk https://${node1_ip}:9345/ping >/dev/null 2>&1; do
      if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "ERRO: Timeout aguardando node-1 apos $${ELAPSED}s" >&2
        exit 1
      fi
      echo "  node-1 ainda nao disponivel ($${ELAPSED}s elapsed)..."
      sleep 15
      ELAPSED=$((ELAPSED + 15))
    done
    echo "node-1 disponivel! Iniciando join..."
  - curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE=server sh -
  - systemctl enable rke2-server.service
  - systemctl start rke2-server.service

final_message: "${hostname} join concluido em $UPTIME segundos"
