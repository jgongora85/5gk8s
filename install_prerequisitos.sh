#!/bin/bash
# Colores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' 

echo -e "${BLUE}=== Iniciando actualización e instalación de paquetes para Kubernetes ===${NC}"

# 1. Actualización del sistema
echo -n "Actualizando repositorios y sistema... "
sudo apt-get update -y && sudo apt-get upgrade -y > /dev/null 2>&1
echo -e "${GREEN}[OK]${NC}"

# 5. Instalación de Containerd
echo -n "Instalando y configurando Containerd (Cgroup Systemd)... "
sudo apt-get install -y containerd > /dev/null 2>&1
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd
if systemctl is-active --quiet containerd; then
    echo -e "${GREEN}[OK]${NC}"
else
    echo -e "${RED}[ERROR: Containerd no inició]${NC}"
fi

# 6. Repositorio y Binarios de Kubernetes
echo -n "Instalando Kubeadm, Kubelet y Kubectl... "
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg > /dev/null 2>&1
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg > /dev/null 2>&1
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
sudo apt-get update -y > /dev/null 2>&1
sudo apt-get install -y kubelet kubeadm kubectl > /dev/null 2>&1
sudo apt-mark hold kubelet kubeadm kubectl > /dev/null 2>&1

if command -v kubeadm &> /dev/null; then
    echo -e "${GREEN}[OK]${NC}"
else
    echo -e "${RED}[ERROR: Falló la instalación de binarios]${NC}"
    exit 1
fi
kubeadm config images pull
echo -e "\n${BLUE}=== COMPROBACIÓN FINAL ===${NC}"
echo -e "Versión de Kubeadm: $(kubeadm version -o short)"
echo -e "Estado de Containerd: $(systemctl is-active containerd)"
echo -e "Swap activo: $([[ $(swapon --show | wc -l) -eq 0 ]] && echo "No (Correcto)" || echo "Sí (Incorrecto)")"

echo -e "\n${GREEN}¡Listo! El nodo está preparado para ser inicializado.${NC}"
