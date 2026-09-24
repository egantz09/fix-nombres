#!/bin/bash
#
# fix-nombres.sh — Detecta y corrige nombres de ficheros/directorios
# con caracteres corruptos, acentos, diéresis y otros caracteres especiales.
#
# Usa uconv (ICU) si está disponible; si no, cae a iconv; y siempre
# aplica una red de seguridad con sed para los casos más comunes.
#
# Avisa en el log si tras la limpieza aún quedan bytes no-ASCII.
# Registra errores de acceso (lectura, escritura, permisos).
# En dry-run, cuenta y muestra cuántos nombres quedan pendientes de aplicar.
#
# Uso:
#   ./fix-nombres.sh                    # dry-run sobre ./
#   ./fix-nombres.sh /ruta/a/musica     # dry-run sobre una ruta
#   ./fix-nombres.sh --apply /ruta/...  # aplica cambios
#   ./fix-nombres.sh --help             # ayuda
#
set -euo pipefail

# ---------- Configuración ----------
APPLY=0
TARGET="."
LOGFILE="renombres_$(date +%Y%m%d_%H%M%S).log"

for arg in "$@"; do
    case "$arg" in
        --apply) APPLY=1 ;;
        -h|--help)
            grep '^#' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) TARGET="$arg" ;;
    esac
done

# Locale UTF-8 para tratar correctamente los acentos
export LC_ALL="${LC_ALL:-C.UTF-8}"

# Detecta una vez si uconv está disponible
HAVE_UCONV=0
if command -v uconv >/dev/null 2>&1; then
    HAVE_UCONV=1
fi

# ---------- Función de limpieza ----------
sanitize() {
    local name="$1"

    # 1) Reparar bytes inválidos (típico de nombres corruptos de ZIP/FAT/Latin-1)
    if ! printf '%s' "$name" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; then
        name=$(printf '%s' "$name" | iconv -f LATIN1 -t UTF-8//TRANSLIT 2>/dev/null \
               || printf '%s' "$name")
    fi

    # 2) Transliteración: preferir uconv (ICU), que cubre mucho más
    if [ "$HAVE_UCONV" -eq 1 ]; then
        name=$(printf '%s' "$name" | uconv -x "Any-Latin; Latin-ASCII" 2>/dev/null \
               || printf '%s' "$name")
    else
        name=$(printf '%s' "$name" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null \
               || printf '%s' "$name")
    fi

    # 3) Red de seguridad: reemplazos manuales por si lo anterior no cubrió todo
    name=$(printf '%s' "$name" | sed \
        -e 's/[áÁàÀâÂäÄ]/a/g' \
        -e 's/[éÉèÈêÊëË]/e/g' \
        -e 's/[íÍìÌîÎïÏ]/i/g' \
        -e 's/[óÓòÒôÔöÖ]/o/g' \
        -e 's/[úÚùÙûÛüÜ]/u/g' \
        -e 's/[ñÑ]/n/g' \
        -e 's/[çÇ]/c/g' \
        -e 's/ß/ss/g' \
        -e 's/[æÆ]/ae/g' \
        -e 's/[œŒ]/oe/g' \
        -e 's/[øØ]/o/g' \
        -e 's/[åÅ]/a/g' \
        -e 's/[ðÐ]/d/g' \
        -e 's/[þÞ]/th/g')

    printf '%s' "$name"
}

# ---------- Comprobación de no-ASCII ----------
# Devuelve 0 si el nombre contiene algún byte fuera de ASCII imprimible.
has_non_ascii() {
    printf '%s' "$1" | LC_ALL=C grep -qP '[^\x00-\x7F]' 2>/dev/null
}

# ---------- Cabecera del log ----------
{
    echo "Registro de renombres - $(date)"
    echo "Directorio: $TARGET"
    echo "Modo: $([ "$APPLY" -eq 1 ] && echo APLICAR || echo DRY-RUN)"
    echo "Transliterador: $([ "$HAVE_UCONV" -eq 1 ] && echo 'uconv (ICU)' || echo 'iconv (fallback)')"
    echo "-----------------------------------------------"
} | tee "$LOGFILE"

# ---------- Contadores ----------
RENAMED=0
PENDING=0
SKIPPED=0
ERRORS=0
WARNINGS=0

# ---------- Recorrido ----------
# -depth    : primero los hijos, luego los padres (permite renombrar carpetas)
# -print0   : separa por NUL → soporta espacios y saltos de línea
# 2> >(...) : captura errores de find (p. ej. directorios sin permiso de lectura)
while IFS= read -r -d '' path; do
    dir=$(dirname "$path")
    base=$(basename "$path")
    fixed_base=$(sanitize "$base")

    # Comprobación de no-ASCII sobre el resultado ANTES de decidir si cambia
    if has_non_ascii "$fixed_base"; then
        echo "   ⚠️  Quedan caracteres no-ASCII tras la limpieza en: $fixed_base" \
            | tee -a "$LOGFILE"
        WARNINGS=$((WARNINGS+1))
    fi

    # Sin cambios → siguiente
    [ "$base" = "$fixed_base" ] && continue

    newpath="$dir/$fixed_base"

    echo "⚠️  Original : $path" | tee -a "$LOGFILE"
    echo "➡️  Nuevo    : $newpath" | tee -a "$LOGFILE"

    # --- Comprobaciones de ACCESO ---
    if [ ! -d "$dir" ]; then
        echo "   ⛔ El directorio padre no existe o no es accesible: $dir" | tee -a "$LOGFILE"
        ERRORS=$((ERRORS+1)); continue
    fi

    if [ ! -x "$dir" ]; then
        echo "   ⛔ Sin permiso de acceso (x) al directorio: $dir" | tee -a "$LOGFILE"
        ERRORS=$((ERRORS+1)); continue
    fi

    if [ ! -w "$dir" ]; then
        echo "   ⛔ Sin permiso de escritura en el directorio: $dir" | tee -a "$LOGFILE"
        ERRORS=$((ERRORS+1)); continue
    fi

    if [ ! -r "$path" ]; then
        echo "   ⚠️  Sin permiso de lectura sobre el origen: $path" | tee -a "$LOGFILE"
        # renombrar no requiere leer el contenido → seguimos
    fi

    # --- Destino ya existente ---
    if [ -e "$newpath" ]; then
        echo "   ❌ Ya existe '$newpath'. Se omite." | tee -a "$LOGFILE"
        SKIPPED=$((SKIPPED+1)); continue
    fi

    # --- Intento real (solo con --apply) ---
    if [ "$APPLY" -eq 1 ]; then
        mv_output=$(mv -- "$path" "$newpath" 2>&1)
        rc=$?
        if [ $rc -eq 0 ]; then
            echo "   ✅ Renombrado." | tee -a "$LOGFILE"
            RENAMED=$((RENAMED+1))
        else
            case $rc in
                1)   motivo="error general de mv" ;;
                13)  motivo="permiso denegado (EACCES)" ;;
                30)  motivo="sistema de archivos de solo lectura (EROFS)" ;;
                36)  motivo="nombre demasiado largo (ENAMETOOLONG)" ;;
                122) motivo="cuota de disco excedida (EDQUOT)" ;;
                *)   motivo="código $rc" ;;
            esac
            echo "   ❌ Error al renombrar [$motivo]: $mv_output" | tee -a "$LOGFILE"
            ERRORS=$((ERRORS+1))
        fi
    else
        # DRY-RUN: este nombre pasó todas las comprobaciones y se renombraría
        echo "   🕓 Pendiente de aplicar (dry-run)." | tee -a "$LOGFILE"
        PENDING=$((PENDING+1))
    fi
    echo | tee -a "$LOGFILE"
done < <(find "$TARGET" -depth -print0 2> >(while IFS= read -r line; do
            printf '⛔ find: %s\n' "$line" | tee -a "$LOGFILE"
        done))

# ---------- Resumen ----------
{
    echo "-----------------------------------------------"
    if [ "$APPLY" -eq 1 ]; then
        echo "Resumen (APLICADO):"
        echo "  ✅ Renombrados        : $RENAMED"
        echo "  ⏭️  Omitidos           : $SKIPPED"
        echo "  ⚠️  Avisos no-ASCII   : $WARNINGS"
        echo "  ❌ Errores            : $ERRORS"
    else
        echo "Resumen (DRY-RUN — nada fue modificado):"
        echo "  🕓 Pendientes         : $PENDING"
        echo "  ⏭️  Omitidos           : $SKIPPED"
        echo "  ⚠️  Avisos no-ASCII   : $WARNINGS"
        echo "  ❌ Errores            : $ERRORS"
    fi
    echo "✅ Proceso completado. Log: $LOGFILE"
} | tee -a "$LOGFILE"

if [ "$APPLY" -eq 0 ]; then
    echo
    echo "ℹ️  Esto fue un dry-run. Nada se ha modificado."
    if [ "$PENDING" -gt 0 ]; then
        echo "ℹ️  Hay $PENDING nombre(s) pendiente(s) de renombrar."
        echo "    Para aplicarlos:  $0 --apply $TARGET"
    else
        echo "ℹ️  No hay nada que renombrar: todos los nombres ya están limpios."
    fi
fi
