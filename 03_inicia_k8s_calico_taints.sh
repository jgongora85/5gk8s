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
    echo "[1/6] Validando requisitos del sistema..."
    
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

check_kubeconfig() {
    echo "[1/4] Validando acceso al clúster de Kubernetes..."
    
    # Intentar usar el KUBECONFIG del usuario que llamó a sudo o el de root
    USER_HOME=$(eval echo "~${SUDO_USER}")
    
    if [ -f "$USER_HOME/.kube/config" ]; then
        export KUBECONFIG="$USER_HOME/.kube/config"
    elif [ -f "/etc/kubernetes/admin.conf" ]; then
        export KUBECONFIG="/etc/kubernetes/admin.conf"
    fi

    if ! kubectl cluster-info &> /dev/null; then
        echo "[ERROR] No se puede acceder al clúster. Asegúrate de que Kubernetes esté corriendo y KUBECONFIG esté bien configurado."
        exit 1
    fi
    echo "[OK] Conexión con el clúster establecida."
}
# --- EJECUCIÓN ---
main() {
    check_root
    check_requirements

    echo "[2/6] Inicializando el Control Plane..."
    if kubeadm init --pod-network-cidr=$POD_CIDR; then
        echo "[OK] Cluster inicializado."
    else
        echo "[ERROR] Falló kubeadm init."
        exit 1
    fi

    echo "[3/6] Configurando kubeconfig para el usuario..."
    USER_HOME=$(eval echo "~${SUDO_USER}")
    mkdir -p "$USER_HOME/.kube"
    cp -i /etc/kubernetes/admin.conf "$USER_HOME/.kube/config"
    chown "$(id -u ${SUDO_USER}):$(id -g ${SUDO_USER})" "$USER_HOME/.kube/config"
    export KUBECONFIG=/etc/kubernetes/admin.conf
    echo "[4/6] Instalando Helm ..."
    check_kubeconfig
    echo "[2/4] Descargando e instalando Helm..."
    
    # Crear un directorio temporal seguro
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR" || exit

    # Descargar el script oficial de instalación de Helm
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
    chmod 700 get_helm.sh
    
    # Ejecutar la instalación
    if [ -n "$HELM_VERSION" ]; then
        ./get_helm.sh --version "$HELM_VERSION"
    else
        ./get_helm.sh
    fi
    
    # Limpieza
    cd ~ || exit
    rm -rf "$TEMP_DIR"

    echo "[3/4] Validando la instalación local de Helm..."
    if ! command -v helm &> /dev/null; then
        echo "[ERROR] Helm no se instaló correctamente en el sistema."
        exit 1
    fi
    
    HELM_BIN_VERSION=$(helm version --short)
    echo "[OK] Helm instalado correctamente. Versión: $HELM_BIN_VERSION"

    echo "[4/4] Validando integración de Helm con el clúster..."
    
    # Prueba A: Intentar listar los releases (Debe responder vacío o con datos, pero no dar error)
    if helm list -A &> /dev/null; then
        echo "[OK] Helm puede comunicarse con la API de Kubernetes."
    else
        echo "[ERROR] Helm no pudo comunicarse con el clúster."
        exit 1
    fi

    # Prueba B: Añadir un repositorio oficial de prueba y actualizarlo
    echo " -> Probando conectividad con repositorios Helm de towards5gs-helm..."
    helm repo add towards5gs 'https://raw.githubusercontent.com/Orange-OpenSource/towards5gs-helm/main/repo/'
    if helm repo update &> /dev/null; then
        echo "[OK] Repositorios actualizados y listos para usar."
    else
        echo "[ADVERTENCIA] No se pudieron actualizar los repositorios de Helm (Verifica tu conexión a internet)."
    fi

    echo "------------------------------------------------------------"
    echo "¡Proceso completado!"
    echo "Helm está listo para ser usado por el usuario: ${SUDO_USER:-root}"
    echo "Puedes probar buscando un paquete ejecuntado: helm search repo bitnami"
    echo "------------------------------------------------------------"

    echo "[6/6] Instalando Calico CNI..."
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/$CALICO_VERSION/manifests/tigera-operator.yaml
    curl -O  https://raw.githubusercontent.com/projectcalico/calico/$CALICO_VERSION/manifests/custom-resources.yaml
    sed -ie "s/192.168.0.0/$POD_CIDR1/g" custom-resources.yaml
    kubectl create -f custom-resources.yaml
    echo "[6/6] Configurando modo Single-Node (Quitando Taints)..."
    # Kubernetes aplica un taint por defecto para que no se ejecuten pods en el master.
    # El comando siguiente quita ese "bloqueo" usando el símbolo "-" al final.
    kubectl taint nodes --all node-role.kubernetes.io/control-plane- 
    kubectl taint nodes --all node-role.kubernetes.io/master- 
    # Instalar Multus CNI
    echo "[6/6] Instalando Multus CNI..."
    git clone https://github.com/k8snetworkplumbingwg/multus-cni.git ; cd multus-cni
    cat ./deployments/multus-daemonset-thick.yml | kubectl apply -f -
    echo "------------------------------------------------------------"
    echo "¡Listo! El nodo maestro ahora puede ejecutar tus cargas de trabajo."
    echo "Verifica con: kubectl get nodes -o wide"
    echo "------------------------------------------------------------"
}

main
