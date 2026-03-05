#!/bin/bash
echo -e "=== Iniciando configuración de Ubuntu 20.04 para Kubernetes ==="

#Deshabilitar swap
echo -n "Desactivando SWAP (requisito de K8s)... "
sudo sed -i '/swap/ s/^/#/' /etc/fstab
swapoff -a
if [[ $(swapon --show | wc -l) -eq 0 ]]; then
    echo -e "[OK]"
else
    echo -e "[ERROR: No se pudo desactivar el swap]"
fi

# Cargar módulos de kernel de filtrado de red
echo -n "Cargando módulos overlay y br_netfilter... "
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay && sudo modprobe br_netfilter
echo -e "[OK]"

# parámetros sysctl para red
echo -n "Configurando sysctl para IP Forwarding e IPTables... "
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system > /dev/null 2>&1
echo -e "[OK]"
