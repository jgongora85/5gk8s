#!/bin/bash

# Definir la versión deseada para gtp5g
VERSION="v0.8.10"
# Variables para free5gc
NAMESPACE="free5gc"
NAMESPACE_UERANSIM="an"
RELEASE_NAME="f5gc"
PV_PATH="/mnt/data/mongodb" # Directorio en el nodo worker
INTERFACE_FISICA="enp1s0"
echo "--- Iniciando instalación de gtp5g $VERSION ---"

# 1. Actualizar repositorios e instalar dependencias
#sudo apt update
# 2. Limpiar instalaciones previas (si existen)
if lsmod | grep -q "gtp5g"; then
    echo "Removiendo módulo gtp5g existente..."
    sudo rmmod gtp5g
fi

# 3. Clonar el repositorio oficial
if [ -d "gtp5g" ]; then
    rm -rf gtp5g
fi

git clone -b $VERSION https://github.com/free5gc/gtp5g.git
cd gtp5g

# 4. Cambiar a la versión específica v0.8.10
git checkout $VERSION

# 5. Compilar e instalar
echo "Compilando el módulo..."
make clean
make
sudo make install

# 6. Verificar la instalación
echo "--- Verificación ---"
if lsmod | grep -q "gtp5g"; then
    echo "¡Éxito! El módulo gtp5g $VERSION se ha instalado y cargado correctamente."
    modinfo gtp5g | grep version
else
    echo "Error: El módulo no se cargó correctamente."
    exit 1
fi
cd ..
#7 instalando multus
echo "--- Iniciando instalación de Multus CNI con Calico ---"
# 8. Clonar el repositorio de referencia de Multus (Quickstart)
git clone https://github.com/k8snetworkplumbingwg/multus-cni.git && cd multus-cni
# 9. Aplicar el DaemonSet de Multus
# Este YAML está configurado para auto-detectar Calico como red primaria
echo "--- Aplicando manifiesto de Multus ---"
cat ./deployments/multus-daemonset.yml |kubectl apply -f -
# 10. Esperar a que Multus esté listo
echo "--- Esperando a que los pods de Multus estén en estado Running ---"
kubectl wait --for=condition=Ready pods -l app=multus-cni -n kube-system --timeout=120s
echo "--- Multus instalado correctamente ---"
echo "--- Verificando pods ---"
kubectl get pods -n kube-system | grep multus
echo "--- Instalación finalizada ---"
cd ..
# 11 instalación free5gc

echo "=== 1. Preparando entorno y Namespace ==="
sudo mkdir -p $PV_PATH
sudo chmod 777 $PV_PATH
kubectl create ns $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
kubectl create ns $NAMESPACE_UERANSIM --dry-run=client -o yaml | kubectl apply -f -
echo "=== 2. Creando Manifiesto de Persistencia (PV y PVC) ==="
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: mongodb-pv
  labels:
    type: local
spec:
  storageClassName: manual
  capacity:
    storage: 8Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: "$PV_PATH"
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: datadir-mongodb-0
  namespace: $NAMESPACE
spec:
  storageClassName: manual
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 8Gi
EOF

echo "=== 3. Configurando Repositorios Helm ==="
helm repo add towards5gs 'https://raw.githubusercontent.com/Orange-OpenSource/towards5gs-helm/main/repo/'
helm repo update

#echo "=== 4. Instalando MongoDB con el PVC creado ==="
#helm -n $NAMESPACE install mongodb towards5gs/mongodb \
  
helm pull towards5gs/free5gc
helm pull towards5gs/ueransim
tar -zxvf ueransim-2.0.17.tgz 
tar -zxvf free5gc-1.1.7.tgz

echo "=== 5. Instalando free5GC (Control Plane y User Plane) ==="
# Nota: Asegúrate de tener el módulo gtp5g instalado en el kernel del nodo
#helm -n $NAMESPACE install $RELEASE_NAME towards5gs/free5gc
helm install -n $NAMESPACE free5gc \
--set global.n4network.masterIf=$INTERFACE_FISICA \
--set global.n3network.masterIf=$INTERFACE_FISICA \
--set global.n6network.masterIf=$INTERFACE_FISICA \
--set global.n6network.subnetIP="192.168.122.0" \
--set global.n6network.gatewayIP="192.168.122.1" \
--set upf.n6if.ipAddress="192.168.122.220" \
--set global.n2network.masterIf=$INTERFACE_FISICA \
--set global.n3network.masterIf=$INTERFACE_FISICA \
--set global.n4network.masterIf=$INTERFACE_FISICA \
--set global.n6network.masterIf=$INTERFACE_FISICA \
--set global.n9network.masterIf=$INTERFACE_FISICA \
--set mongodb.image.repository=bitnamilegacy/mongodb \
--set mongodb.image.tag=4.4.4 \
free5gc
echo "=== 5. Instalando ueransim"
helm --install an -n $NAMESPACE_UERANSIM \
--set global.n2network.masterIf=$INTERFACE_FISICA \
--set global.n3network.masterIf=$INTERFACE_FISICA \
ueransim

echo "=== 6. Verificando el estado del despliegue ==="
sleep 2
kubectl get all -n $NAMESPACE
echo "------------------------------------------------------------"
echo "Despliegue finalizado."
echo "Para acceder a la WebUI usa: kubectl port-forward -n $NAMESPACE svc/webui-service 5000:5000"
