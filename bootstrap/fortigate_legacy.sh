#!/bin/bash
# ============================================================
#  FortiGate 60E — Script bash de configuration (legacy)
#
#  ⚠️  Ce script est conservé à titre de référence.
#  La méthode recommandée est le playbook Ansible (site.yml)
#  qui gère les secrets via Ansible Vault et est idempotent.
#
#  Usage (si Ansible non disponible) :
#    chmod +x fortigate_legacy.sh
#    ./fortigate_legacy.sh
# ============================================================

# --- VARIABLES À ADAPTER ---
FGT_HOST=""           # IP de gestion du FortiGate   ex: 192.168.99.99
FGT_USER=""           # Utilisateur admin             ex: admin
FGT_PASS=""           # Mot de passe admin

GW_WAN1=""            # Gateway FAI 1                 ex: 203.0.113.1
GW_WAN2=""            # Gateway FAI 2                 ex: 203.0.114.1

IP_WAN1=""            # IP fixe WAN1 avec masque      ex: 203.0.113.2/30
IP_WAN2=""            # IP fixe WAN2 avec masque      ex: 203.0.114.2/30
# ----------------------------

# ============================================================
#  GUARDRAILS - Validation des variables obligatoires
# ============================================================
ERRORS=0

check_var() {
    local var_name="$1"
    local var_value="$2"
    local example="$3"
    if [[ -z "$var_value" ]]; then
        echo "  [✗] $var_name est vide  →  ex: $example"
        ERRORS=$((ERRORS + 1))
    else
        echo "  [✓] $var_name = $var_value"
    fi
}

check_ip() {
    local var_name="$1"
    local var_value="$2"
    local example="$3"
    if [[ -z "$var_value" ]]; then
        echo "  [✗] $var_name est vide  →  ex: $example"
        ERRORS=$((ERRORS + 1))
    elif ! [[ "$var_value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$ ]]; then
        echo "  [✗] $var_name invalide ($var_value)  →  ex: $example"
        ERRORS=$((ERRORS + 1))
    else
        echo "  [✓] $var_name = $var_value"
    fi
}

echo "========================================"
echo " FortiGate 60E — Configuration (legacy)"
echo "========================================"
echo ""
echo "--- Validation des variables ---"
check_ip  "FGT_HOST" "$FGT_HOST" "192.168.99.99"
check_var "FGT_USER" "$FGT_USER" "admin"
check_var "FGT_PASS" "$FGT_PASS" "monMotDePasse"
check_ip  "GW_WAN1"  "$GW_WAN1"  "203.0.113.1"
check_ip  "GW_WAN2"  "$GW_WAN2"  "203.0.114.1"
check_ip  "IP_WAN1"  "$IP_WAN1"  "203.0.113.2/30"
check_ip  "IP_WAN2"  "$IP_WAN2"  "203.0.114.2/30"

if [[ $ERRORS -gt 0 ]]; then
    echo ""
    echo "  ⛔ $ERRORS variable(s) manquante(s) ou invalide(s)."
    echo "  Corrige le script avant de relancer."
    echo "========================================"
    exit 1
fi

echo ""
echo "  ✅ Variables valides. Démarrage..."
echo "========================================"

# Vérifier sshpass
if ! command -v sshpass &> /dev/null; then
    echo "[!] Installation de sshpass..."
    sudo apt-get install -y sshpass 2>/dev/null
fi

# Fonction d'envoi de commandes FortiOS
fgt_cmd() {
    sshpass -p "$FGT_PASS" ssh -o StrictHostKeyChecking=no \
        -o ConnectTimeout=10 "$FGT_USER@$FGT_HOST" "$1"
}

echo ""
echo "[1/6] Configuration Dual WAN..."
fgt_cmd "
config system interface
    edit wan1
        set mode static
        set ip $IP_WAN1
        set allowaccess ping
        set role wan
        set description FAI-Principal
    next
    edit wan2
        set mode static
        set ip $IP_WAN2
        set allowaccess ping
        set role wan
        set description FAI-Backup
    next
end
"

echo "[2/6] Routes statiques avec failover..."
fgt_cmd "
config router static
    edit 1
        set dst 0.0.0.0 0.0.0.0
        set gateway $GW_WAN1
        set device wan1
        set distance 10
    next
    edit 2
        set dst 0.0.0.0 0.0.0.0
        set gateway $GW_WAN2
        set device wan2
        set distance 20
    next
end
"

echo "[3/6] Health Check SLA..."
fgt_cmd "
config system link-monitor
    edit monitor-wan1
        set srcintf wan1
        set server 8.8.8.8 1.1.1.1
        set interval 5
        set failtime 3
        set recoverytime 5
        set update-static-route enable
    next
    edit monitor-wan2
        set srcintf wan2
        set server 8.8.8.8 1.1.1.1
        set interval 5
        set failtime 3
        set recoverytime 5
        set update-static-route enable
    next
end
"

echo "[4/6] Interfaces LAN..."
fgt_cmd "
config system interface
    edit port3
        set ip 192.168.10.1 255.255.255.0
        set allowaccess ping https ssh
        set role lan
        set description Zone-Corp
    next
    edit port4
        set ip 192.168.20.1 255.255.255.0
        set allowaccess ping
        set role lan
        set description Zone-Guest
    next
    edit port5
        set ip 192.168.30.1 255.255.255.0
        set allowaccess ping
        set role lan
        set description Zone-IoT
    next
end
"

echo "[5/6] DHCP par zone..."
fgt_cmd "
config system dhcp server
    edit 1
        set interface port3
        set default-gateway 192.168.10.1
        set netmask 255.255.255.0
        set dns-server1 1.1.1.1
        set dns-server2 8.8.8.8
        config ip-range
            edit 1
                set start-ip 192.168.10.100
                set end-ip 192.168.10.200
            next
        end
    next
    edit 2
        set interface port4
        set default-gateway 192.168.20.1
        set netmask 255.255.255.0
        set dns-server1 1.1.1.1
        config ip-range
            edit 1
                set start-ip 192.168.20.100
                set end-ip 192.168.20.200
            next
        end
    next
    edit 3
        set interface port5
        set default-gateway 192.168.30.1
        set netmask 255.255.255.0
        set dns-server1 1.1.1.1
        config ip-range
            edit 1
                set start-ip 192.168.30.100
                set end-ip 192.168.30.200
            next
        end
    next
end
"

echo "[6/6] Firewall policies..."
fgt_cmd "
config firewall policy
    edit 1
        set name Corp_to_WAN1
        set srcintf port3
        set dstintf wan1
        set srcaddr all
        set dstaddr all
        set action accept
        set schedule always
        set service ALL
        set nat enable
        set logtraffic all
    next
    edit 2
        set name Corp_to_WAN2
        set srcintf port3
        set dstintf wan2
        set srcaddr all
        set dstaddr all
        set action accept
        set schedule always
        set service ALL
        set nat enable
        set logtraffic all
    next
    edit 3
        set name Guest_to_WAN1
        set srcintf port4
        set dstintf wan1
        set srcaddr all
        set dstaddr all
        set action accept
        set schedule always
        set service HTTP HTTPS DNS
        set nat enable
        set logtraffic all
    next
    edit 4
        set name Guest_to_WAN2
        set srcintf port4
        set dstintf wan2
        set srcaddr all
        set dstaddr all
        set action accept
        set schedule always
        set service HTTP HTTPS DNS
        set nat enable
        set logtraffic all
    next
    edit 5
        set name IoT_to_WAN1
        set srcintf port5
        set dstintf wan1
        set srcaddr all
        set dstaddr all
        set action accept
        set schedule always
        set service HTTP HTTPS DNS
        set nat enable
        set logtraffic all
    next
    edit 6
        set name IoT_to_WAN2
        set srcintf port5
        set dstintf wan2
        set srcaddr all
        set dstaddr all
        set action accept
        set schedule always
        set service HTTP HTTPS DNS
        set nat enable
        set logtraffic all
    next
end
"

echo ""
echo "========================================"
echo " ✅ Configuration terminée !"
echo "========================================"
echo ""
echo "  port3 Corp    : 192.168.10.0/24"
echo "  port4 Guest   : 192.168.20.0/24"
echo "  port5 IoT     : 192.168.30.0/24"
echo "  wan1 Principal: distance 10"
echo "  wan2 Backup   : distance 20"
echo "========================================"
