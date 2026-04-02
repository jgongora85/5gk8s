#!/bin/bash

# --- CONFIGURACIÓN ---
NAMESPACE="monitoring"
RELEASE_NAME="prometheus-stack"

# --- FUNCIONES DE VALIDACIÓN ---
check_root() {
    if [[ $EUID -ne 0 ]]; then
       echo "[ERROR] Este script debe ejecutarse como root (sudo)."
       exit 1
    fi
}

check_prerequisites() {
    echo "[1/5] Validando prerrequisitos..."
    
    # Comprobar kubectl
    if ! command -v kubectl &> /dev/null; then
        echo "[ERROR] kubectl no está instalado."
        exit 1
    fi

    # Comprobar Helm
    if ! command -v helm &> /dev/null; then
        echo "[ERROR] Helm no está instalado. Ejecuta primero el script anterior."
        exit 1
    fi

    # Cargar kubeconfig del usuario
    USER_HOME=$(eval echo "~${SUDO_USER}")
    if [ -f "$USER_HOME/.kube/config" ]; then
        export KUBECONFIG="$USER_HOME/.kube/config"
    elif [ -f "/etc/kubernetes/admin.conf" ]; then
        export KUBECONFIG="/etc/kubernetes/admin.conf"
    fi

    # Validar conexión al clúster
    if ! kubectl cluster-info &> /dev/null; then
        echo "[ERROR] No se puede acceder al clúster de Kubernetes."
        exit 1
    fi
    echo "[OK] Herramientas y conexión listas."
}

# --- EJECUCIÓN ---
main() {
    check_root
    check_prerequisites

    echo "[2/5] Añadiendo repositorios de Helm..."
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update &> /dev/null

    echo "[3/5] Creando Namespace y desplegando el Stack..."
    kubectl create namespace $NAMESPACE 

    # Instalamos el stack completo
    helm upgrade --install $RELEASE_NAME prometheus-community/kube-prometheus-stack \
      --namespace $NAMESPACE \
      --wait \
      --timeout 5m0s

    if [ $? -ne 0 ]; then
        echo "[ERROR] Falló la instalación del stack de Prometheus."
        exit 1
    fi
    echo "[OK] Stack instalado correctamente."

    echo "[4/5] Extrayendo credenciales de Grafana..."
    # El password por defecto viene codificado en un secreto de K8s
    ADMIN_PASSWORD=$(kubectl get secret --namespace $NAMESPACE ${RELEASE_NAME}-grafana -o jsonpath="{.data.admin-password}" | base64 --decode)

    echo "[5/5] Creando reenvíos de puertos en segundo plano (Port-Forward)..."
    
    # Matar port-forwards previos si existen
    pkill -f "port-forward" || true
    
    # Reenvío para Grafana (Puerto 3000)
    kubectl port-forward --namespace $NAMESPACE service/${RELEASE_NAME}-grafana 3000:80 --address 0.0.0.0 &> /dev/null &
    
    # Reenvío para Prometheus (Puerto 9090)
    kubectl port-forward --namespace $NAMESPACE service/${RELEASE_NAME}-kube-prom-prometheus 9090:9090 --address 0.0.0.0 &> /dev/null &
    
    echo "------------------------------------------------------------"
    echo "¡Proceso completado exitosamente!"
    echo ""
    echo " ACCESO A GRAFANA:"
    echo "   -> URL: http://<IP_DE_TU_SERVIDOR>:3000"
    echo "   -> Usuario: admin"
    echo "   -> Contraseña: $ADMIN_PASSWORD"
    echo ""
    echo " ACCESO A PROMETHEUS:"
    echo "   -> URL: http://<IP_DE_TU_SERVIDOR>:9090"
    echo ""
    echo "Nota: El script ha dejado activos dos túneles en segundo plano"
    echo "para que puedas acceder desde fuera de la máquina."
    echo "------------------------------------------------------------"
}

main
