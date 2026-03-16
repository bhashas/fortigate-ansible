# 🔐 FortiGate 60E + Cisco SG350 — Network Automation with Ansible

> Projet d'automatisation réseau d'infrastructure bureau segmentée en 3 zones (Corp / Guest / IoT)  
> Stack : **Ansible · Ansible Vault · GitHub Actions · FortiOS · Cisco IOS**

---

## 🎯 Objectif du projet

Automatiser de A à Z la configuration d'une infrastructure réseau bureau sécurisée :
- Dual WAN avec failover automatique (FortiGate 60E)
- Segmentation réseau en 3 zones isolées (Cisco SG350)
- Déploiement 100% Ansible — zéro intervention manuelle post-bootstrap
- Secrets chiffrés via Ansible Vault (AES-256)
- Pipeline CI/CD GitHub Actions (lint → dry-run → deploy)

---

## 🏗️ Architecture

```
Internet
  ├── FAI 1 ──► wan1 (distance 10 — Principal)   ┐
  └── FAI 2 ──► wan2 (distance 20 — Backup)      ┼── FortiGate 60E
                                                   │
                              port3 (Corp)  ───────┤ 192.168.10.0/24
                              port4 (Guest) ───────┤ 192.168.20.0/24
                              port5 (IoT)   ───────┘ 192.168.30.0/24
                                   │
                             Cisco SG350
                        ┌──────────┴──────────┐
                   VLAN 10              VLAN 20 / 30
                 Postes Corp          Guest / IoT devices

Management
  └── VLAN 99 (192.168.99.0/24)
        ├── Ubuntu Ansible (192.168.99.10)
        ├── FortiGate MGMT (192.168.99.99)
        └── SG350 SVI      (192.168.99.254)
```

---

## 🔒 Sécurité & bonnes pratiques

| Pratique | Implémentation |
|----------|---------------|
| Secrets chiffrés | Ansible Vault AES-256 |
| Zéro mot de passe en clair | `vault.yml` chiffré, jamais pushé en clair |
| Isolation management | VLAN 99 dédié, inaccessible depuis Corp/Guest/IoT |
| Isolation inter-VLAN | Deny implicite FortiOS — aucun flux inter-zone sans policy explicite |
| Failover WAN | Health check SLA (ping 8.8.8.8 + 1.1.1.1) — bascule en 15 secondes |
| Agentless | Ansible se connecte en SSH natif — aucun agent sur les équipements |
| Pipeline sécurisé | `VAULT_PASSWORD` stocké dans GitHub Secrets, jamais dans le code |

---

## 📁 Structure du projet

```
fortigate-ansible/
├── .github/
│   └── workflows/
│       └── deploy.yml          # Pipeline CI/CD GitHub Actions
├── inventory/
│   └── hosts.yml               # Inventaire FortiGate + SG350
├── group_vars/
│   ├── fortigate/
│   │   ├── vars.yml            # Variables réseau (IPs, policies, DHCP)
│   │   └── vault.yml           # Credentials chiffrés (Ansible Vault)
│   └── sg350/
│       ├── vars.yml            # VLANs, ports access/uplink
│       └── vault.yml           # Credentials chiffrés (Ansible Vault)
├── roles/
│   ├── fortigate/
│   │   └── tasks/
│   │       ├── main.yml        # Entry point
│   │       ├── wan.yml         # Dual WAN + SLA failover
│   │       ├── lan.yml         # Interfaces physiques port3/4/5
│   │       ├── dhcp.yml        # Serveurs DHCP par zone
│   │       └── policies.yml    # Firewall policies NAT
│   └── sg350/
│       └── tasks/
│           └── main.yml        # VLANs + ports access + uplink
├── site.yml                    # Playbook principal
├── .gitignore
└── README.md
```

---

## ⚙️ Pipeline CI/CD

```
Pull Request ──► Lint YAML + Ansible syntax check
                 └── Dry-run --check (simule sans appliquer)

Merge → main ──► Déploiement réel automatique
```

```yaml
# Extrait .github/workflows/deploy.yml
jobs:
  lint     → yamllint + ansible-lint + syntax-check
  dry_run  → ansible-playbook --check  (PR + staging)
  deploy   → ansible-playbook          (main uniquement)
```

---

## 🚀 Utilisation

### Prérequis
```bash
pip install ansible ansible-lint
ansible-galaxy collection install fortinet.fortios cisco.ios
```

### Chiffrer les secrets
```bash
ansible-vault encrypt group_vars/fortigate/vault.yml
ansible-vault encrypt group_vars/sg350/vault.yml
```

### Dry-run
```bash
ansible-playbook site.yml \
  --vault-password-file ~/.vault_pass \
  --check -v
```

### Déploiement
```bash
ansible-playbook site.yml \
  --vault-password-file ~/.vault_pass
```

### Déploiement ciblé
```bash
# FortiGate uniquement
ansible-playbook site.yml --limit fortigate60e --vault-password-file ~/.vault_pass

# SG350 uniquement
ansible-playbook site.yml --limit cisco_sg350 --vault-password-file ~/.vault_pass
```

---

## 🔧 Bootstrap initial (console série)

Avant le premier lancement Ansible, chaque équipement nécessite une configuration minimale via port console (RJ45 → USB, 9600 bauds) :

**FortiGate 60E**
```bash
config system interface
    edit mgmt
        set ip 192.168.99.99 255.255.255.0
        set allowaccess ssh https ping
    next
end
config system global
    set admin-ssh-port 22
end
```

**Cisco SG350**
```bash
vlan 99
 name Management
interface vlan 99
 ip address 192.168.99.254 255.255.255.0
ip ssh server
crypto key generate rsa
```

Une fois SSH accessible → Ansible prend le relais, le câble console n'est plus nécessaire.

---

## 📋 Zones réseau

| Zone | Port FortiGate | Réseau | Accès Internet | Inter-VLAN |
|------|---------------|--------|----------------|------------|
| Corp | port3 | 192.168.10.0/24 | ✅ Complet | ❌ Isolé |
| Guest | port4 | 192.168.20.0/24 | ✅ HTTP/HTTPS | ❌ Isolé |
| IoT | port5 | 192.168.30.0/24 | ✅ HTTP/HTTPS | ❌ Isolé |
| Management | MGMT | 192.168.99.0/24 | ❌ | Admin only |

---

## 🛠️ Stack technique

![Ansible](https://img.shields.io/badge/Ansible-EE0000?style=flat&logo=ansible&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-2088FF?style=flat&logo=github-actions&logoColor=white)
![FortiGate](https://img.shields.io/badge/FortiGate-EE3124?style=flat&logo=fortinet&logoColor=white)
![Cisco](https://img.shields.io/badge/Cisco-1BA0D7?style=flat&logo=cisco&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=flat&logo=python&logoColor=white)

---

## 👤 Auteur

**Ton Nom**  
Ingénieur Réseaux & Télécoms — Cloud & DevSecOps  
[LinkedIn](https://linkedin.com/in/TONPROFIL) · [GitHub](https://github.com/TONPROFIL)
