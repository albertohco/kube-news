#cloud-config
hostname: rke2-node-1
fqdn: rke2-node-1.local
manage_etc_hosts: true

package_update: true
package_upgrade: false

packages:
  - curl
  - open-iscsi
  - nfs-common

runcmd:
  # Configura o RKE2 como servidor primário (bootstrap do cluster)
  - mkdir -p /etc/rancher/rke2
  - |
    cat > /etc/rancher/rke2/config.yaml <<'RKEEOF'
    token: ${rke2_token}
    tls-san:
      - rke2-node-1
      - rke2-node-1.local
    RKEEOF
  - curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE=server sh -
  - systemctl enable rke2-server.service
  - systemctl start rke2-server.service
  # Aguarda o kubeconfig ser gerado pelo RKE2
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
  # Disponibiliza kubectl e kubeconfig para o usuário ubuntu
  - mkdir -p /home/ubuntu/.kube
  - cp /etc/rancher/rke2/rke2.yaml /home/ubuntu/.kube/config || true
  - chown -R ubuntu:ubuntu /home/ubuntu/.kube || true
  - chmod 600 /home/ubuntu/.kube/config || true
  - ln -sf /var/lib/rancher/rke2/bin/kubectl /usr/local/bin/kubectl || true

final_message: "rke2-node-1 bootstrap concluido em $UPTIME segundos. Verifique com: kubectl get nodes"
