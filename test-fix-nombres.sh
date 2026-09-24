#!/bin/bash
#
# test-fix-nombres.sh — Crea un entorno de prueba con casos problemáticos
# y ejecuta fix-nombres.sh en dry-run y en modo real.
#
set -euo pipefail

SCRIPT="./fix-nombres.sh"
BASE="/tmp/test_fix-nombres"

if [ ! -x "$SCRIPT" ]; then
    echo "❌ No encuentro $SCRIPT o no es ejecutable."
    echo "   Asegúrate de estar en la carpeta correcta y hacer: chmod +x fix-nombres.sh"
    exit 1
fi

echo "🧹 Limpiando pruebas anteriores..."
rm -rf "$BASE"
mkdir -p "$BASE"

echo "📁 Creando estructura de prueba en $BASE ..."

# --- Caso 1: carpeta y ficheros con acentos ---
mkdir -p "$BASE/Música Española/Álbum Ñandú"
touch "$BASE/Música Española/Álbum Ñandú/Canción número 1.mp3"
touch "$BASE/Música Española/Álbum Ñandú/otra canción con acentós.mp3"

# --- Caso 2: espacios múltiples y caracteres raros ---
mkdir -p "$BASE/con   espacios    raros"
touch "$BASE/con   espacios    raros/fichero   con    espacios.txt"

# --- Caso 3: nombre que empieza por guion (rompe mv sin --) ---
touch "$BASE/Música Española/-archivo raro.mp3"

# --- Caso 4: nombre con diéresis y ñ ---
touch "$BASE/Música Española/Über Straße.mp3"

# --- Caso 5: colisión tras limpiar (dos nombres que se vuelven iguales) ---
touch "$BASE/Música Española/Canción.mp3"
touch "$BASE/Música Española/Cancion.mp3"

# --- Caso 6: directorio anidado con acentos ---
mkdir -p "$BASE/Pequeña/Sub carpeta niños"
touch "$BASE/Pequeña/Sub carpeta niños/niño juguetón.txt"

# --- Caso 7: directorio sin permiso de escritura ---
mkdir -p "$BASE/solo_lectura"
touch "$BASE/solo_lectura/Canción bloqueada.mp3"
chmod 555 "$BASE/solo_lectura"

# --- Caso 8: directorio sin permiso de lectura (find fallará) ---
mkdir -p "$BASE/sin_acceso"
touch "$BASE/sin_acceso/Canción secreta.mp3"
chmod 000 "$BASE/sin_acceso"

echo "✅ Estructura creada."
echo
echo "───────────── CONTENIDO INICIAL ─────────────"
find "$BASE" -print | sed "s|$BASE|.|"
echo "─────────────────────────────────────────────"
echo

read -rp "▶️  Pulsa ENTER para ejecutar el DRY-RUN..."
echo
"$SCRIPT" "$BASE"
echo

read -rp "▶️  Pulsa ENTER para APLICAR los cambios..."
echo
"$SCRIPT" --apply "$BASE"
echo

echo "───────────── CONTENIDO FINAL ─────────────"
find "$BASE" -print 2>/dev/null | sed "s|$BASE|.|" || true
echo "───────────────────────────────────────────"
echo

echo "📄 Últimos logs generados:"
ls -t renombres_*.log 2>/dev/null | head -3

# Restaurar permisos para poder borrar sin sudo
chmod -R u+rwX "$BASE" 2>/dev/null || true

echo
echo "ℹ️  Para limpiar todo después:  rm -rf $BASE"
echo "ℹ️  Para revisar el log:        cat \$(ls -t renombres_*.log | head -1)"
