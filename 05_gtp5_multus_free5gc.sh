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
