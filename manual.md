# 📘 Manual — Instalação do Proxmox VE no Hyper-V (Servidor Headless)

Guia passo a passo para preparar o ambiente antes de executar o Terraform.

> **Cenário:** Windows Server Core (sem interface gráfica) com Hyper-V instalado em bare metal. Todos os comandos são executados remotamente via **PowerShell Remoting** ou **SSH** a partir de uma estação de trabalho Windows.

> **Objetivo:** Ter um Proxmox VE rodando dentro do Hyper-V com nested virtualization, pronto para receber as 3 VMs do cluster RKE2.

---

## Índice

1. [Pré-requisitos](#1-pré-requisitos)
2. [Conectar remotamente ao servidor Hyper-V](#2-conectar-remotamente-ao-servidor-hyper-v)
3. [Verificar e preparar o Hyper-V](#3-verificar-e-preparar-o-hyper-v)
4. [Baixar o ISO do Proxmox VE no servidor](#4-baixar-o-iso-do-proxmox-ve-no-servidor)
5. [Criar e configurar a VM do Proxmox via PowerShell](#5-criar-e-configurar-a-vm-do-proxmox-via-powershell)
6. [Habilitar Nested Virtualization](#6-habilitar-nested-virtualization)
7. [Instalar o Proxmox VE (console remoto)](#7-instalar-o-proxmox-ve-console-remoto)
8. [Acessar a Interface Web do Proxmox](#8-acessar-a-interface-web-do-proxmox)
9. [Configurações pós-instalação via SSH](#9-configurações-pós-instalação-via-ssh)
10. [Criar o Template Ubuntu 22.04 Cloud Image](#10-criar-o-template-ubuntu-2204-cloud-image)
11. [Habilitar Snippets no Storage local](#11-habilitar-snippets-no-storage-local)
12. [Configurar Acesso à API para o Terraform](#12-configurar-acesso-à-api-para-o-terraform)
13. [Validação Final](#13-validação-final)

---

## 1. Pré-requisitos

### No servidor bare metal (Windows Server Core)

| Requisito | Detalhe |
|---|---|
| **SO** | Windows Server 2019/2022 Core (sem GUI) |
| **Papel Hyper-V** | Instalado (`Install-WindowsFeature -Name Hyper-V`) |
| **PowerShell Remoting** | Habilitado (`Enable-PSRemoting`) |
| **RAM disponível** | Mínimo **14 GB** livres para a VM Proxmox |
| **Disco disponível** | Mínimo **150 GB** livres (VM Proxmox + 3 VMs internas) |
| **Virtualização** | Intel VT-x / AMD-V habilitado na BIOS |
| **Rede** | IP fixo no servidor, acessível pela estação de gerenciamento |

### Na estação de gerenciamento (seu computador Windows com GUI)

| Requisito | Para que serve |
|---|---|
| **PowerShell 5.1+** | Gerenciar o Hyper-V remotamente |
| **Hyper-V Management Tools** | Usar `vmconnect.exe` para acessar o console da VM |
| **Ferramentas RSAT** | Administração remota do servidor |

Instalar as Hyper-V Management Tools na estação (PowerShell como Administrador):

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-Tools-All
```

---

## 2. Conectar remotamente ao servidor Hyper-V

> Todos os comandos PowerShell das seções seguintes são executados **na sua estação de gerenciamento**, apontando para o servidor.

### Habilitar PowerShell Remoting no servidor (se ainda não estiver)

Se tiver acesso local ao servidor (KVM, iDRAC, iLO, etc.):

```powershell
# Execute diretamente no servidor via console físico/KVM
Enable-PSRemoting -Force
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
```

### Abrir sessão remota da sua estação de gerenciamento

```powershell
# Substitua pelo IP real do servidor
$servidor = "192.168.1.50"
$credencial = Get-Credential   # janela pedirá usuário/senha do servidor

Enter-PSSession -ComputerName $servidor -Credential $credencial
```

> A partir deste ponto, todos os comandos PowerShell são executados dentro desta sessão remota (o prompt mudará para `[192.168.1.50]: PS>`).

### Alternativa — SSH (se habilitado no servidor)

```powershell
ssh Administrador@192.168.1.50
```

---

## 3. Verificar e preparar o Hyper-V

Na sessão remota PowerShell:

```powershell
# Verificar se o Hyper-V está instalado
Get-WindowsFeature -Name Hyper-V

# Se não estiver instalado:
Install-WindowsFeature -Name Hyper-V -IncludeManagementTools -Restart
```

### Verificar ou criar um Virtual Switch externo

```powershell
# Listar switches existentes
Get-VMSwitch

# Listar adaptadores de rede físicos disponíveis
Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
```

Se não houver um switch externo, crie um (substitua `"Ethernet"` pelo nome do adaptador):

```powershell
New-VMSwitch -Name "SwitchExterno" -NetAdapterName "Ethernet" -AllowManagementOS $true
```

### Verificar espaço em disco

```powershell
Get-PSDrive -PSProvider FileSystem | Select-Object Name, Used, Free
```

---

## 4. Baixar o ISO do Proxmox VE no servidor

Na sessão remota PowerShell, baixe o ISO diretamente no servidor:

```powershell
# Criar diretório para ISOs
New-Item -ItemType Directory -Path "C:\ISOs" -Force

# Baixar o ISO do Proxmox VE (verifique a versão mais recente em proxmox.com/downloads)
$isoUrl = "https://enterprise.proxmox.com/iso/proxmox-ve_8.4-1.iso"
$isoPath = "C:\ISOs\proxmox-ve.iso"

Write-Host "Baixando ISO... (pode demorar alguns minutos)"
Invoke-WebRequest -Uri $isoUrl -OutFile $isoPath -UseBasicParsing

# Verificar se o download foi concluído
Get-Item $isoPath | Select-Object Name, Length
```

> 💡 Se o download via `Invoke-WebRequest` for lento, use `Start-BitsTransfer` (mais robusto para arquivos grandes):
> ```powershell
> Start-BitsTransfer -Source $isoUrl -Destination $isoPath
> ```

---

## 5. Criar e configurar a VM do Proxmox via PowerShell

Execute o bloco abaixo completo na sessão remota. Ajuste `$switchName` se o seu switch tiver outro nome:

```powershell
# ── Variáveis ──────────────────────────────────────────────
$vmName    = "proxmox"
$ramBytes  = 14GB          # 14 GB de RAM
$cpuCount  = 4             # vCPUs
$diskBytes = 150GB         # Disco para o Proxmox + VMs internas
$diskPath  = "C:\VMs\proxmox\proxmox.vhdx"
$isoPath   = "C:\ISOs\proxmox-ve.iso"
$switchName = "SwitchExterno"

# ── Criar diretório da VM ───────────────────────────────────
New-Item -ItemType Directory -Path "C:\VMs\proxmox" -Force

# ── Criar a VM (Geração 2) ──────────────────────────────────
New-VM -Name $vmName `
       -Generation 2 `
       -MemoryStartupBytes $ramBytes `
       -NewVHDPath $diskPath `
       -NewVHDSizeBytes $diskBytes `
       -SwitchName $switchName

# ── Configurar CPUs ─────────────────────────────────────────
Set-VMProcessor -VMName $vmName -Count $cpuCount

# ── Desabilitar memória dinâmica (Proxmox precisa de RAM fixa) ──
Set-VMMemory -VMName $vmName -DynamicMemoryEnabled $false

# ── Desabilitar Secure Boot (Proxmox não suporta) ──────────
Set-VMFirmware -VMName $vmName -EnableSecureBoot Off

# ── Adicionar o ISO como DVD ────────────────────────────────
Add-VMDvdDrive -VMName $vmName -Path $isoPath

# ── Configurar boot pelo DVD primeiro ──────────────────────
$dvd  = Get-VMDvdDrive -VMName $vmName
$disk = Get-VMHardDiskDrive -VMName $vmName
Set-VMFirmware -VMName $vmName -BootOrder $dvd, $disk

# ── Confirmar ───────────────────────────────────────────────
Get-VM -Name $vmName | Select-Object Name, State, MemoryStartup, ProcessorCount
```

Saída esperada:
```
Name     State  MemoryStartup ProcessorCount
----     -----  ------------- --------------
proxmox  Off    15032385536   4
```

---

## 6. Habilitar Nested Virtualization

> ⚠️ **A VM deve estar desligada** (`State: Off`) para este comando.

```powershell
Set-VMProcessor -VMName "proxmox" -ExposeVirtualizationExtensions $true

# Verificar
Get-VMProcessor -VMName "proxmox" | Select-Object ExposeVirtualizationExtensions
# Deve retornar: True
```

---

## 7. Instalar o Proxmox VE (console remoto)

### Iniciar a VM

Na sessão remota:

```powershell
Start-VM -Name "proxmox"
Get-VM -Name "proxmox"   # aguarde State = Running
```

### Acessar o console da VM

Como o servidor não tem GUI, use o `vmconnect.exe` **na sua estação de gerenciamento**:

```powershell
# Execute na sua estação (não na sessão remota)
# Substitua pelo IP do servidor Hyper-V
vmconnect.exe 192.168.1.50 proxmox
```

> 💡 O `vmconnect.exe` está disponível se você instalou as **Hyper-V Management Tools** na etapa 1.

Alternativamente, conecte o Hyper-V Manager da sua estação ao servidor remoto:
1. Abra o **Hyper-V Manager** na sua estação
2. Clique em **Conectar ao Servidor** → informe o IP do servidor
3. Clique com o botão direito na VM `proxmox` → **Conectar**

### Seguir o instalador do Proxmox

Com o console aberto, prossiga com a instalação:

| Etapa | O que fazer |
|---|---|
| **Tela de boot** | Selecione **Install Proxmox VE (Graphical)** |
| **EULA** | Aceitar |
| **Disco de destino** | Selecionar o único disco disponível (150 GB) |
| **País/Fuso** | Selecionar seu país e fuso horário |
| **Senha root** | Definir uma senha forte |
| **E-mail** | Pode ser fictício para labs |
| **Hostname** | Sugestão: `pve.local` |
| **IP de gerenciamento** | Definir um **IP fixo** acessível na sua rede |
| **Gateway** | IP do roteador/gateway da rede |
| **DNS** | Ex: `8.8.8.8` |

> 📝 **Anote o IP fixo configurado** — você vai precisar dele no `terraform.tfvars` e para acesso SSH.

Após a instalação (~5 minutos), o Proxmox reiniciará automaticamente.

### Remover o ISO após a instalação

Na sessão remota PowerShell:

```powershell
# Aguardar a VM reiniciar
Start-Sleep -Seconds 30

# Ejetar o DVD
Get-VMDvdDrive -VMName "proxmox" | Set-VMDvdDrive -Path $null

# Verificar estado
Get-VM -Name "proxmox"
```

---

## 8. Acessar a Interface Web do Proxmox

A interface web do Proxmox é acessada **na sua estação de gerenciamento** (não no servidor bare metal):

1. Abra o navegador da sua estação
2. Acesse: `https://<IP-DO-PROXMOX>:8006`
   > Exemplo: `https://192.168.1.100:8006`
3. Aceite o aviso de certificado auto-assinado
4. Faça login:
   - **Usuário:** `root`
   - **Senha:** a senha definida na instalação
   - **Realm:** `Linux PAM standard authentication`

---

## 9. Configurações pós-instalação via SSH

Acesse o Proxmox por SSH **da sua estação de gerenciamento**:

```bash
ssh root@<IP-DO-PROXMOX>
```

### 9.1 Configurar repositório community (sem subscription)

```bash
# Remover repositório enterprise (requer licença paga)
rm -f /etc/apt/sources.list.d/pve-enterprise.list

# Remover repositório ceph enterprise (se existir)
rm -f /etc/apt/sources.list.d/ceph.list

# Adicionar repositório community gratuito
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" \
  > /etc/apt/sources.list.d/pve-community.list

# Atualizar e fazer upgrade
apt update && apt full-upgrade -y
```

### 9.2 Desabilitar o aviso de subscription na UI (opcional, apenas labs)

```bash
sed -i.bak "s/Proxmox.Utils.checked_command(function() {/\/\//g" \
  /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
systemctl restart pveproxy
```

### 9.3 Verificar conectividade de rede

```bash
ping -c 4 8.8.8.8
```

> ⚠️ As 3 VMs do cluster RKE2 precisarão de acesso à internet para baixar os binários do RKE2 durante o cloud-init.

---

## 10. Criar o Template Ubuntu 22.04 Cloud Image

O Terraform vai clonar este template para criar as 3 VMs. Execute via SSH no Proxmox:

```bash
# 1. Instalar dependências
apt install -y wget qemu-utils libguestfs-tools

# 2. Baixar a cloud image do Ubuntu 22.04 LTS
wget -O /tmp/ubuntu-22.04-cloudimg.img \
  https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img

# 3. Instalar o qemu-guest-agent dentro da imagem
#    (necessário para o Terraform ler o IP da VM após o boot)
virt-customize -a /tmp/ubuntu-22.04-cloudimg.img \
  --install qemu-guest-agent \
  --truncate /etc/machine-id

# 4. Criar VM vazia (ID 9000) que será convertida em template
qm create 9000 \
  --name ubuntu-22.04-cloud \
  --memory 2048 \
  --cores 2 \
  --net0 virtio,bridge=vmbr0 \
  --agent enabled=1 \
  --ostype l26 \
  --serial0 socket \
  --vga serial0

# 5. Importar o disco da cloud image para o storage local-lvm
qm importdisk 9000 /tmp/ubuntu-22.04-cloudimg.img local-lvm

# 6. Configurar o disco como disco de boot
qm set 9000 \
  --scsihw virtio-scsi-pci \
  --scsi0 local-lvm:vm-9000-disk-0,discard=on \
  --boot c \
  --bootdisk scsi0

# 7. Adicionar drive de cloud-init
qm set 9000 --ide2 local-lvm:cloudinit

# 8. Converter a VM em template (operação irreversível)
qm template 9000

# 9. Limpar arquivo temporário
rm /tmp/ubuntu-22.04-cloudimg.img

echo "Template criado com sucesso!"
```

Verificar:

```bash
qm list
```

Saída esperada:
```
      VMID NAME                 STATUS     MEM(MB)    BOOTDISK(GB) PID
      9000 ubuntu-22.04-cloud   stopped    2048              30.00  0
```

---

## 11. Habilitar Snippets no Storage local

O Terraform precisa fazer upload dos arquivos cloud-init como **snippets** no Proxmox.

Via SSH no Proxmox:

```bash
# Habilitar tipo "snippets" no storage local
pvesm set local --content backup,iso,vztmpl,snippets

# Verificar
pvesm status
```

A coluna `type` do storage `local` deve listar `snippets`:

```
Name    Type     Status   Total      Used     Available  %
local   dir      active   ...        ...       ...       ...
```

Confirmar via API:

```bash
pvesh get /storage/local --output-format json | grep -i content
```

Deve conter `snippets` na lista de content types.

---

## 12. Configurar Acesso à API para o Terraform

### Opção A — Usar `root@pam` (mais simples, para labs)

```hcl
# terraform.tfvars
proxmox_username = "root@pam"
proxmox_password = "sua_senha_root"
```

### Opção B — Criar usuário Terraform dedicado (recomendado para produção)

Via SSH no Proxmox:

```bash
# Criar role com permissões necessárias
pveum role add TerraformRole \
  -privs "Datastore.AllocateSpace,Datastore.AllocateTemplate,Datastore.Audit,\
Pool.Allocate,Sys.Audit,Sys.Console,Sys.Modify,\
VM.Allocate,VM.Audit,VM.Clone,VM.Config.CDROM,VM.Config.Cloudinit,\
VM.Config.CPU,VM.Config.Disk,VM.Config.HWType,VM.Config.Memory,\
VM.Config.Network,VM.Config.Options,VM.Migrate,VM.Monitor,VM.PowerMgmt,SDN.Use"

# Criar usuário
pveum user add terraform@pve --password "SenhaSeguraAqui123!"

# Atribuir a role
pveum aclmod / -user terraform@pve -role TerraformRole

# Verificar
pveum user list
```

```hcl
# terraform.tfvars
proxmox_username = "terraform@pve"
proxmox_password = "SenhaSeguraAqui123!"
```

---

## 13. Validação Final

### Checklist completo

| # | Verificação | Como checar |
|---|---|---|
| ✅ | Servidor Hyper-V acessível remotamente | `Enter-PSSession -ComputerName <IP>` funciona |
| ✅ | VM `proxmox` existe e está rodando | `Get-VM -Name proxmox` → `State: Running` |
| ✅ | Nested virtualization habilitada | `Get-VMProcessor -VMName proxmox \| Select ExposeVirtualizationExtensions` → `True` |
| ✅ | Proxmox acessível via HTTPS da estação | `https://<IP>:8006` abre no navegador |
| ✅ | SSH no Proxmox funciona | `ssh root@<IP-PROXMOX>` conecta |
| ✅ | Template `ubuntu-22.04-cloud` existe | `qm list \| grep ubuntu-22.04-cloud` retorna ID 9000 |
| ✅ | Snippets habilitados no storage local | `pvesm status` mostra `local` com snippets |
| ✅ | API do Proxmox responde | teste abaixo |
| ✅ | `terraform.tfvars` preenchido | arquivo existe em `infra/terraform/terraform.tfvars` |

### Testar API do Proxmox (da sua estação de gerenciamento)

```bash
curl -sk https://<IP-DO-PROXMOX>:8006/api2/json/version | python3 -m json.tool
```

Saída esperada:
```json
{
  "data": {
    "version": "8.x.x",
    "release": "8",
    "repoid": "..."
  }
}
```

### Testar autenticação da API

```bash
curl -sk -X POST "https://<IP-DO-PROXMOX>:8006/api2/json/access/ticket" \
  -d "username=root@pam&password=SUA_SENHA" | python3 -m json.tool
```

Deve retornar um `ticket` e `CSRFPreventionToken` válidos.

---

## ✅ Próximo passo — Executar o Terraform

Com o ambiente preparado, volte para a sua máquina de desenvolvimento e execute:

```bash
cd infra/terraform

# Configurar variáveis (uma vez só)
cp terraform.tfvars.example terraform.tfvars
# Edite terraform.tfvars com:
#   proxmox_endpoint = "https://<IP-DO-PROXMOX>:8006"
#   proxmox_password = "sua_senha"
#   vm_ssh_public_key = "$(cat ~/.ssh/id_ed25519.pub)"

# Provisionar as 3 VMs
terraform init
terraform plan
terraform apply
```

Após ~7 minutos (criação das VMs + cloud-init):

```bash
# Ver IPs das VMs criadas
terraform output

# Acessar o node-1 e validar o cluster
ssh ubuntu@$(terraform output -raw node1_ip)
kubectl get nodes
```

---

*Para dúvidas técnicas sobre as decisões de arquitetura, consulte [`openspec/changes/terraform-proxmox-rke2-cluster/design.md`](openspec/changes/terraform-proxmox-rke2-cluster/design.md).*


---

## 1. Pré-requisitos

| Requisito | Detalhe |
|---|---|
| **SO host** | Windows 10/11 Pro ou Server 2019/2022 |
| **Hyper-V** | Habilitado nas funcionalidades do Windows |
| **RAM disponível** | Mínimo **14 GB** livres para a VM Proxmox |
| **Disco disponível** | Mínimo **150 GB** livres (VM Proxmox + 3 VMs internas) |
| **Processador** | Suporte a virtualização (Intel VT-x / AMD-V) habilitado na BIOS |

### Verificar se Hyper-V está habilitado

Abra o PowerShell como **Administrador** e execute:

```powershell
Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V
```

Se o estado for `Disabled`, habilite:

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
# Reinicie o Windows quando solicitado
```

---

## 2. Habilitar Nested Virtualization no Hyper-V

> ⚠️ **A VM do Proxmox deve estar desligada para executar este comando.**

No PowerShell como **Administrador**:

```powershell
# Substitua "proxmox" pelo nome exato que você vai dar à VM
Set-VMProcessor -VMName "proxmox" -ExposeVirtualizationExtensions $true
```

> 💡 Execute este comando **depois** de criar a VM (passo 4) e **antes** de inicializá-la.

Para verificar se foi aplicado:

```powershell
Get-VMProcessor -VMName "proxmox" | Select-Object ExposeVirtualizationExtensions
```

Deve retornar `True`.

---

## 3. Baixar o ISO do Proxmox VE

1. Acesse: **https://www.proxmox.com/en/downloads/proxmox-virtual-environment/iso**
2. Baixe a versão mais recente: `proxmox-ve_X.X-X.iso`
3. Salve em um local de fácil acesso no host Windows (ex: `C:\ISOs\`)

---

## 4. Criar a VM do Proxmox no Hyper-V

### Via Gerenciador do Hyper-V (interface gráfica)

1. Abra o **Gerenciador do Hyper-V**
2. Clique em **Novo → Máquina Virtual**
3. Preencha as configurações:

| Configuração | Valor recomendado |
|---|---|
| **Nome** | `proxmox` |
| **Geração** | Geração 2 |
| **RAM** | 14336 MB (14 GB) — desmarque memória dinâmica |
| **Rede** | Selecione um switch externo (para acesso à internet) |
| **Disco virtual** | 150 GB (VHDX, tamanho dinâmico) |
| **ISO de instalação** | Selecione o ISO do Proxmox baixado |

4. Conclua o assistente e **NÃO inicie a VM ainda**

### Ajustes adicionais obrigatórios (antes de iniciar)

No Hyper-V, clique com o botão direito na VM `proxmox` → **Configurações**:

- **Segurança → Inicialização Segura:** **Desmarque** "Habilitar Inicialização Segura" (Proxmox não suporta Secure Boot)
- **Processador:** Aumente para **4 processadores virtuais** se disponível

Depois, habilite a nested virtualization (PowerShell):

```powershell
Set-VMProcessor -VMName "proxmox" -ExposeVirtualizationExtensions $true
```

---

## 5. Instalar o Proxmox VE

1. Inicie a VM no Hyper-V
2. Na tela de boot, selecione **Install Proxmox VE (Graphical)**
3. Siga o instalador:

| Etapa | O que fazer |
|---|---|
| **EULA** | Aceitar |
| **Disco de destino** | Selecionar o único disco disponível |
| **País/Fuso** | Selecionar seu país e fuso horário |
| **Senha root** | Definir uma senha forte para o usuário `root` |
| **E-mail** | Inserir um e-mail (pode ser fictício para labs) |
| **Hostname** | Sugestão: `pve.local` |
| **Rede** | Definir um IP fixo na sua rede local |

> 📝 **Anote o IP que definir** — você vai precisar dele no `terraform.tfvars`.

4. Clique em **Install** e aguarde (~5 minutos)
5. Após concluir, remova o ISO nas configurações da VM no Hyper-V e reinicie

---

## 6. Acessar a Interface Web do Proxmox

Após a instalação e reinicialização:

1. No navegador do Windows host, acesse:
   ```
   https://<IP-DO-PROXMOX>:8006
   ```
   > Exemplo: `https://192.168.1.100:8006`

2. Aceite o aviso de certificado auto-assinado (clique em "Avançado" → "Prosseguir")
3. Faça login:
   - **Usuário:** `root`
   - **Senha:** a senha que você definiu na instalação
   - **Realm:** `Linux PAM standard authentication`

---

## 7. Configurações pós-instalação

### 7.1 Desabilitar o aviso de subscription (opcional, apenas para labs)

No terminal da VM Proxmox (ou via **Shell** na interface web):

```bash
sed -i.bak 's/NotFound/Active/g' /usr/share/perl5/PVE/API2/Subscription.pm
systemctl restart pveproxy
```

### 7.2 Atualizar os repositórios para uso sem subscription

```bash
# Remover repositório enterprise (requer subscription paga)
rm -f /etc/apt/sources.list.d/pve-enterprise.list

# Adicionar repositório community (gratuito)
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" \
  > /etc/apt/sources.list.d/pve-community.list

# Atualizar e fazer upgrade
apt update && apt upgrade -y
```

### 7.3 Verificar conectividade de rede

```bash
ping -c 4 8.8.8.8
```

As VMs internas precisarão de acesso à internet para baixar o RKE2.

---

## 8. Criar o Template Ubuntu 22.04 Cloud Image

O Terraform vai clonar este template para criar as 3 VMs do cluster.

Execute os comandos abaixo no **shell do Proxmox** (via interface web → Shell, ou SSH):

```bash
# 1. Baixar a cloud image do Ubuntu 22.04
wget -O /tmp/ubuntu-22.04-cloudimg.img \
  https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img

# 2. Instalar qemu-utils se necessário
apt install -y qemu-utils libguestfs-tools

# 3. Instalar o qemu-guest-agent dentro da imagem (necessário para o Terraform obter o IP)
virt-customize -a /tmp/ubuntu-22.04-cloudimg.img \
  --install qemu-guest-agent \
  --truncate /etc/machine-id

# 4. Criar uma VM vazia para ser o template (ID 9000)
qm create 9000 \
  --name ubuntu-22.04-cloud \
  --memory 2048 \
  --cores 2 \
  --net0 virtio,bridge=vmbr0 \
  --agent enabled=1 \
  --ostype l26 \
  --serial0 socket \
  --vga serial0

# 5. Importar o disco da cloud image para o storage local-lvm
qm importdisk 9000 /tmp/ubuntu-22.04-cloudimg.img local-lvm

# 6. Configurar o disco importado como disco de boot
qm set 9000 \
  --scsihw virtio-scsi-pci \
  --scsi0 local-lvm:vm-9000-disk-0,discard=on \
  --boot c \
  --bootdisk scsi0

# 7. Adicionar drive de cloud-init
qm set 9000 --ide2 local-lvm:cloudinit

# 8. Converter a VM em template
qm template 9000

# 9. Limpar o arquivo temporário
rm /tmp/ubuntu-22.04-cloudimg.img
```

Verificar se o template foi criado:

```bash
qm list | grep ubuntu-22.04-cloud
```

Saída esperada:
```
9000  ubuntu-22.04-cloud  template  2048   2   0.00  
```

---

## 9. Habilitar Snippets no Storage local

O Terraform (provider `bpg/proxmox`) precisa fazer upload dos arquivos cloud-init como **snippets**. É necessário habilitar este tipo de conteúdo no storage `local`.

### Via interface web

1. Acesse **Datacenter → Storage → local**
2. Clique em **Editar**
3. Em **Conteúdo**, marque a opção **Snippets**
4. Clique em **OK**

### Via shell (alternativa)

```bash
pvesm set local --content backup,iso,vztmpl,snippets
```

Verificar:

```bash
pvesm status
# A linha "local" deve conter "snippets" na coluna de conteúdo
```

---

## 10. Configurar Acesso à API para o Terraform

O Terraform se comunica com o Proxmox via API REST. Você pode usar o usuário `root@pam` com senha, mas o recomendado para produção é criar um usuário dedicado.

### Opção A — Usar root@pam (mais simples, para labs)

Apenas anote as credenciais para usar no `terraform.tfvars`:

```hcl
proxmox_username = "root@pam"
proxmox_password = "sua_senha_root"
```

### Opção B — Criar usuário Terraform dedicado (recomendado)

No shell do Proxmox:

```bash
# Criar role com as permissões necessárias
pveum role add TerraformRole \
  -privs "Datastore.AllocateSpace,Datastore.AllocateTemplate,Datastore.Audit,Pool.Allocate,Sys.Audit,Sys.Console,Sys.Modify,VM.Allocate,VM.Audit,VM.Clone,VM.Config.CDROM,VM.Config.Cloudinit,VM.Config.CPU,VM.Config.Disk,VM.Config.HWType,VM.Config.Memory,VM.Config.Network,VM.Config.Options,VM.Migrate,VM.Monitor,VM.PowerMgmt,SDN.Use"

# Criar usuário
pveum user add terraform@pve --password SenhaSeguraAqui

# Atribuir a role ao usuário (acesso a todo o datacenter)
pveum aclmod / -user terraform@pve -role TerraformRole
```

No `terraform.tfvars`:

```hcl
proxmox_username = "terraform@pve"
proxmox_password = "SenhaSeguraAqui"
```

---

## 11. Validação Final

Antes de executar o Terraform, verifique cada item:

| # | Verificação | Comando / Onde verificar |
|---|---|---|
| ✅ | Nested virtualization habilitada | `Get-VMProcessor -VMName "proxmox" \| Select ExposeVirtualizationExtensions` → `True` |
| ✅ | Proxmox acessível via HTTPS | `https://<IP>:8006` abre no navegador |
| ✅ | Template `ubuntu-22.04-cloud` existe | `qm list \| grep ubuntu-22.04-cloud` → mostra template |
| ✅ | Snippets habilitados no storage local | `pvesm status` → `local` tem `snippets` |
| ✅ | Credenciais API funcionando | `curl -sk -X GET "https://<IP>:8006/api2/json/version" -u "root@pam:senha" \| python3 -m json.tool` |
| ✅ | `terraform.tfvars` preenchido | Arquivo existe em `infra/terraform/terraform.tfvars` |

### Teste rápido da API

```bash
curl -sk https://<IP-DO-PROXMOX>:8006/api2/json/version | python3 -m json.tool
```

Saída esperada (exemplo):
```json
{
  "data": {
    "version": "8.x.x",
    "release": "8",
    "repoid": "..."
  }
}
```

---

## ✅ Próximo passo

Com o ambiente preparado, execute o Terraform:

```bash
cd infra/terraform

cp terraform.tfvars.example terraform.tfvars
# Edite terraform.tfvars com seu IP, credenciais e chave SSH pública

terraform init
terraform plan
terraform apply
```

Após ~7 minutos, valide o cluster:

```bash
ssh ubuntu@$(terraform output -raw node1_ip)
kubectl get nodes
```

---

*Para dúvidas técnicas sobre as decisões de arquitetura, consulte [`openspec/changes/terraform-proxmox-rke2-cluster/design.md`](openspec/changes/terraform-proxmox-rke2-cluster/design.md).*
