# 🔧 Ajuste — Liberar WSL para acessar VPN (Hyper-V Firewall)

## Problema

O WSL2 com mirrored networking não consegue alcançar o servidor Proxmox `10.0.11.120`
via VPN (OpenVPN TAP-Windows6), pois o **Hyper-V Firewall** do Windows 11 bloqueia
o tráfego encaminhado do WSL para a rede VPN.

- ✅ Windows alcança `10.0.11.120` normalmente
- ❌ WSL recebe timeout ao tentar acessar `10.0.11.120`

---

## Correção — PowerShell como Administrador

Abra o **PowerShell como Administrador** e execute:

```powershell
# Opção 1 — Hyper-V Firewall (parâmetro correto: -RemoteAddresses)
New-NetFirewallHyperVRule `
  -DisplayName "WSL acesso VPN Proxmox" `
  -Direction Outbound `
  -Action Allow `
  -RemoteAddresses "10.0.11.0/24" `
  -VMCreatorId "{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}"
```

> O `VMCreatorId` acima é o identificador padrão do WSL2 no Windows 11.

---

## Verificar se a regra foi criada

```powershell
Get-NetFirewallHyperVRule | Where-Object DisplayName -like "*Proxmox*"
```

---

## Validar no WSL após aplicar a regra

```bash
# Testar conectividade TCP na porta do Proxmox
curl -k --connect-timeout 5 https://10.0.11.120:8006/api2/json/version

# Esperado: JSON com versão do Proxmox
```

---

## Se o Hyper-V Firewall ainda der erro — Windows Firewall convencional

```powershell
# Opção 2 — Windows Firewall padrão (funciona em qualquer versão do PS)
New-NetFirewallRule `
  -DisplayName "WSL VPN Proxmox Outbound" `
  -Direction Outbound `
  -LocalAddress "10.0.13.2" `
  -RemoteAddress "10.0.11.0/24" `
  -Action Allow `
  -Profile Any

New-NetFirewallRule `
  -DisplayName "WSL VPN Proxmox Inbound" `
  -Direction Inbound `
  -LocalAddress "10.0.13.2" `
  -RemoteAddress "10.0.11.0/24" `
  -Action Allow `
  -Profile Any
```

---

## Remover as regras (se necessário)

```powershell
# Remover regra Hyper-V Firewall
Remove-NetFirewallHyperVRule -DisplayName "WSL acesso VPN Proxmox"

# Remover regras convencionais (se usou a Opção 2)
Remove-NetFirewallRule -DisplayName "WSL VPN Proxmox Outbound"
Remove-NetFirewallRule -DisplayName "WSL VPN Proxmox Inbound"
```

---

## Após liberar o acesso — continuar a implantação

Com o WSL alcançando o Proxmox, instale o Terraform nativo Linux no WSL
para evitar o problema de lock file do binário Windows:

```bash
TERRAFORM_VERSION="1.10.5"
wget -O /tmp/tf.zip \
  https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip
sudo unzip -o /tmp/tf.zip -d /usr/local/bin/
rm /tmp/tf.zip
terraform version
```

Depois execute a implantação normalmente:

```bash
cd ~/caminho/para/kube-news/infra/terraform

terraform init
terraform plan
terraform apply
```
