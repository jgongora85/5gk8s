#!/bin/bash

# --- CONFIGURACIÓN ---
POD_CIDR="10.244.0.0/16"
POD_CIDR1="10.244.0.0" 
CALICO_VERSION="v3.27.0"

# --- FUNCIONES DE VALIDACIÓN ---
check_root() {
    if [[ $EUID -ne 0 ]]; then
       echo "[ERROR] Este script debe ejecutarse como root (sudo)."
       exit 1
    fi
}

check_requirements() {
    echo "[1/5] Validando requisitos del sistema..."
    
    if ! command -v kubeadm &> /dev/null; then
        echo "[ERROR] kubeadm no está instalado."
        exit 1
    fi

    # Desactivar Swap (Obligatorio para K8s)
    swapoff -a
    sed -i '/swap/s/^/#/' /etc/fstab

    # Cargar módulos y configurar sysctl
    modprobe overlay && modprobe br_netfilter
    cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
    sysctl --system &> /dev/null
}

# --- EJECUCIÓN ---
main() {
    check_root
    check_requirements

    echo "[2/5] Inicializando el Control Plane..."
    if kubeadm init --pod-network-cidr=$POD_CIDR; then
        echo "[OK] Cluster inicializado."
    else
        echo "[ERROR] Falló kubeadm init."
        exit 1
    fi

    echo "[3/5] Configurando kubeconfig para el usuario..."
    USER_HOME=$(eval echo "~${SUDO_USER}")
    mkdir -p "$USER_HOME/.kube"
    cp -i /etc/kubernetes/admin.conf "$USER_HOME/.kube/config"
    chown "$(id -u ${SUDO_USER}):$(id -g ${SUDO_USER})" "$USER_HOME/.kube/config"
    export KUBECONFIG=/etc/kubernetes/admin.conf

    echo "[4/5] Instalando Calico CNI..."
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/$CALICO_VERSION/manifests/tigera-operator.yaml
    curl -O  https://raw.githubusercontent.com/projectcalico/calico/$CALICO_VERSION/manifests/custom-resources.yaml
    sed -ie 's/192.168.0.0/$POD_CIDR1/g' custom-resources.yaml
    kubectl create -f custom-resources.yaml
    echo "[5/5] Configurando modo Single-Node (Quitando Taints)..."
    # Kubernetes aplica un taint por defecto para que no se ejecuten pods en el master.
    # El comando siguiente quita ese "bloqueo" usando el símbolo "-" al final.
    kubectl taint nodes --all node-role.kubernetes.io/control-plane- 
    kubectl taint nodes --all node-role.kubernetes.io/master- 

    echo "------------------------------------------------------------"
    echo "¡Listo! El nodo maestro ahora puede ejecutar tus cargas de trabajo."
    echo "Verifica con: kubectl get nodes -o wide"
    echo "------------------------------------------------------------"
}

main
