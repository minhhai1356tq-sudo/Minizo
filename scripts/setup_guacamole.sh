#!/usr/bin/env bash
# setup_guacamole.sh - Apache Guacamole for Google Colab
# Uso: bash setup_guacamole.sh

set -Eeuo pipefail

GUAC_VERSION="1.5.5"
GUAC_DIR="/opt/guacamole"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🌐 Instalando Apache Guacamole ${GUAC_VERSION}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ============================================================
# [0/5] APT
# ============================================================

echo "   ↳ [0/5] Actualizando APT..."

export DEBIAN_FRONTEND=noninteractive

apt-get update -y

# Intentar habilitar Universe si existe add-apt-repository
if command -v add-apt-repository >/dev/null 2>&1; then
    add-apt-repository -y universe >/dev/null 2>&1 || true
    apt-get update -y
fi

echo "      ✅ APT actualizado"

# ============================================================
# [1/5] JAVA
# ============================================================

echo "   ↳ [1/5] Instalando Java..."

if apt-cache show openjdk-17-jre-headless >/dev/null 2>&1; then
    apt-get install -y --no-install-recommends \
        openjdk-17-jre-headless
elif apt-cache show openjdk-11-jre-headless >/dev/null 2>&1; then
    apt-get install -y --no-install-recommends \
        openjdk-11-jre-headless
else
    echo "❌ No se encontró Java compatible"
    exit 1
fi

echo "      ✅ Java: $(java -version 2>&1 | head -1)"

# ============================================================
# [2/5] DEPENDENCIAS
# ============================================================

echo "   ↳ [2/5] Instalando dependencias de compilación..."

# uuid-dev es la opción estándar documentada por Apache.
apt-get install -y --no-install-recommends \
    build-essential \
    pkg-config \
    curl \
    ca-certificates \
    tar \
    gzip \
    autoconf \
    automake \
    libtool \
    libtool-bin \
    libcairo2-dev \
    libjpeg-turbo8-dev \
    libpng-dev \
    uuid-dev \
    libpango1.0-dev \
    libssh2-1-dev \
    libvncserver-dev \
    libwebsockets-dev \
    libpulse-dev \
    libssl-dev \
    libvorbis-dev \
    libwebp-dev \
    libavcodec-dev \
    libavformat-dev \
    libavutil-dev \
    libswscale-dev

echo "      ✅ Dependencias principales instaladas"

# ------------------------------------------------------------
# FreeRDP es OPCIONAL.
# Se intenta instalar para conservar soporte RDP.
# Si no está disponible, seguimos con VNC.
# ------------------------------------------------------------

if apt-cache show freerdp2-dev >/dev/null 2>&1; then
    echo "   ↳ Instalando FreeRDP..."
    apt-get install -y --no-install-recommends freerdp2-dev || \
        echo "      ⚠️ FreeRDP no pudo instalarse; continuando sin RDP"
else
    echo "      ⚠️ freerdp2-dev no disponible; continuando con VNC"
fi

# ============================================================
# [3/5] GUACD
# ============================================================

echo "   ↳ [3/5] Compilando guacd..."
echo "      Esto puede tardar varios minutos."

cd /tmp

rm -rf \
    "guacamole-server-${GUAC_VERSION}" \
    guacamole-server.tar.gz

echo "      ↳ Descargando fuente..."

curl -fL --retry 3 --retry-delay 2 \
    -o guacamole-server.tar.gz \
    "https://archive.apache.org/dist/guacamole/${GUAC_VERSION}/source/guacamole-server-${GUAC_VERSION}.tar.gz"

test -s guacamole-server.tar.gz

echo "      ✅ Descarga completada"

tar -xzf guacamole-server.tar.gz

cd "guacamole-server-${GUAC_VERSION}"

echo "      ↳ Ejecutando configure..."

./configure \
    --with-init-dir=/etc/init.d \
    --disable-guacenc

echo ""
echo "      ↳ Compilando..."
echo ""

make -j"$(nproc)"

echo ""
echo "      ↳ Instalando..."

make install

ldconfig

if ! command -v guacd >/dev/null 2>&1; then
    echo "❌ guacd no se pudo instalar"
    exit 1
fi

echo "      ✅ guacd: $(command -v guacd)"

cd /tmp

rm -rf \
    "guacamole-server-${GUAC_VERSION}" \
    guacamole-server.tar.gz

# ============================================================
# [4/5] TOMCAT
# ============================================================

echo "   ↳ [4/5] Instalando Tomcat..."

if apt-cache show tomcat9 >/dev/null 2>&1; then

    apt-get install -y --no-install-recommends tomcat9

    echo "      ✅ Tomcat 9 instalado por APT"

else

    echo "      ⚠️ tomcat9 no está disponible por APT"
    echo "      ↳ Descargando Tomcat 9 manualmente..."

    TOMCAT_VERSION="9.0.122"
    TOMCAT_DIR="/opt/tomcat9"

    rm -rf "${TOMCAT_DIR}"
    mkdir -p "${TOMCAT_DIR}"

    cd /tmp

    curl -fL --retry 3 --retry-delay 2 \
        -o apache-tomcat.tar.gz \
        "https://dlcdn.apache.org/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz"

    test -s apache-tomcat.tar.gz

    tar -xzf apache-tomcat.tar.gz

    cp -a \
        "apache-tomcat-${TOMCAT_VERSION}/." \
        "${TOMCAT_DIR}/"

    rm -rf \
        "apache-tomcat-${TOMCAT_VERSION}" \
        apache-tomcat.tar.gz

    echo "      ✅ Tomcat instalado en ${TOMCAT_DIR}"

fi

# ============================================================
# PATHS TOMCAT
# ============================================================

if [ -d /var/lib/tomcat9 ]; then
    TOMCAT_WEBAPPS="/var/lib/tomcat9/webapps"
else
    TOMCAT_WEBAPPS="/opt/tomcat9/webapps"
fi

mkdir -p "${TOMCAT_WEBAPPS}"

# ============================================================
# [5/5] GUACAMOLE WEB APP
# ============================================================

echo "   ↳ [5/5] Desplegando Guacamole web app..."

mkdir -p "${GUAC_DIR}"
mkdir -p /etc/guacamole

echo "      ↳ Descargando Guacamole ${GUAC_VERSION}.war..."

curl -fL --retry 3 --retry-delay 2 \
    -o /tmp/guacamole.war \
    "https://archive.apache.org/dist/guacamole/${GUAC_VERSION}/binary/guacamole-${GUAC_VERSION}.war"

test -s /tmp/guacamole.war

echo "      ✅ WAR descargado"

rm -rf "${TOMCAT_WEBAPPS}/ROOT"

cp /tmp/guacamole.war \
    "${TOMCAT_WEBAPPS}/ROOT.war"

rm -f /tmp/guacamole.war

# ============================================================
# CONFIG BÁSICA GUACAMOLE
# ============================================================

cat > /etc/guacamole/guacamole.properties <<'EOF'
guacd-hostname: 127.0.0.1
guacd-port: 4822
log-level: info
EOF

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ Apache Guacamole instalado"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "📌 guacd:"
command -v guacd

echo ""
echo "📌 Java:"
java -version 2>&1 | head -3

echo ""
echo "📌 Guacamole WAR:"
ls -lh "${TOMCAT_WEBAPPS}/ROOT.war"

echo ""
echo "✅ Setup completado."
