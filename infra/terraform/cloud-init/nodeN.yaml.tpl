#cloud-config
hostname: ${hostname}
fqdn: ${hostname}.local
manage_etc_hosts: true

package_update: true
package_upgrade: false

packages:
  - curl
  - open-iscsi
  - nfs-common

runcmd:
  # Configura o RKE2 para ingressar no cluster existente via node-1
  - mkdir -p /etc/rancher/rke2
  - |
    cat > /etc/rancher/rke2/config.yaml <<'RKEEOF'
    server: https://${node1_ip}:9345
    token: ${rke2_token}
    RKEEOF
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
