#!/bin/bash

# Definir la versión deseada
VERSION="v0.8.10"

echo "--- Iniciando instalación de gtp5g $VERSION ---"

# 1. Actualizar repositorios e instalar dependencias
sudo apt update
sudo apt install -y git gcc make binutils \
    linux-headers-$(uname -r) \
    build-essential

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
#7 instalando multus
echo "--- Iniciando instalación de Multus CNI con Calico ---"
# 1. Clonar el repositorio de referencia de Multus (Quickstart)
git clone https://github.com/k8snetworkplumbingwg/multus-cni.git && cd multus-cni
# 2. Aplicar el DaemonSet de Multus
# Este YAML está configurado para auto-detectar Calico como red primaria
echo "--- Aplicando manifiesto de Multus ---"
cat ./deployments/multus-daemonset.yml |kubectl apply -f -
# 3. Esperar a que Multus esté listo
echo "--- Esperando a que los pods de Multus estén en estado Running ---"
kubectl wait --for=condition=Ready pods -l app=multus-cni -n kube-system --timeout=120s
echo "--- Multus instalado correctamente ---"
echo "--- Verificando pods ---"
kubectl get pods -n kube-system | grep multus
echo "--- Instalación finalizada ---"
