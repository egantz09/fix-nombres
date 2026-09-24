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
# Modo --revert: deshace los renombrados usando un log previo generado
# con --apply (busca las líneas RENAME|origen|destino).
#
# Uso:
#   ./fix-nombres.sh                          # dry-run sobre ./
#   ./fix-nombres.sh /ruta/a/musica           # dry-run sobre una ruta
#   ./fix-nombres.sh --apply /ruta/...        # aplica cambios
#   ./fix-nombres.sh --revert                 # dry-run del revert (último log)
#   ./fix-nombres.sh --revert <log>           # dry-run del revert (log dado)
#   ./fix-nombres.sh --revert --apply         # aplica el revert
#   ./fix-nombres.sh --help                   # ayuda
#
set -euo pipefail

# ---------- Configuración ----------
APPLY=0
REVERT=0
TARGET="."
REVERT_LOG=""
LOGFILE=""

# Parseo de argumentos (acepta --apply, --revert [log], --help, ruta)
ARGS=("$@")
i=0
while [ $i -lt ${#ARGS[@]} ]; do
    arg="${ARGS[$i]}"
    case "$arg" in
        --apply)  APPLY=1 ;;
        --revert) REVERT=1
                  # Si el siguiente argumento existe y no empieza por --, es el log
                  next=$((i+1))
                  if [ $next -lt ${#ARGS[@]} ]; then
                      cand="${ARGS[$next]}"
                      if [ "${cand:0:2}" != "--" ] && [ -f "$cand" ]; then
                          REVERT_LOG="$cand"
                          i=$next
                      fi
                  fi ;;
        -h|--help)
            grep '^#' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        --apply) APPLY=1 ;;
        *) TARGET="$arg" ;;
    esac
    i=$((i+1))
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
        -e 's/[íÍìÌÎïÏ]/i/g' \
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
has_non_ascii() {
    printf '%s' "$1" | LC_ALL=C grep -qP '[^\x00-\x7F]' 2>/dev/null
}

# =============================================================
# MODO REVERT
# =============================================================
if [ "$REVERT" -eq 1 ]; then

    # Si no se especificó log, usar el más reciente
    if [ -z "$REVERT_LOG" ]; then
        REVERT_LOG=$(ls -t renombres_*.log 2>/dev/null | head -1 || true)
        if [ -z "$REVERT_LOG" ]; then
            echo "❌ No encuentro ningún renombres_*.log en el directorio actual."
            echo "   Uso:  $0 --revert <archivo.log> [--apply]"
            exit 1
        fi
        echo "ℹ️  Usando log más reciente: $REVERT_LOG"
    fi

    if [ ! -f "$REVERT_LOG" ]; then
        echo "❌ El log '$REVERT_LOG' no existe."
        exit 1
    fi

    LOGFILE="revert_$(date +%Y%m%d_%H%M%S).log"

    {
        echo "Registro de REVERT - $(date)"
        echo "Log fuente: $REVERT_LOG"
        echo "Modo: $([ "$APPLY" -eq 1 ] && echo APLICAR || echo DRY-RUN)"
        echo "-----------------------------------------------"
    } | tee "$LOGFILE"

    # Validación: ¿el log tiene marcadores RENAME?
    if ! grep -q '^RENAME|' "$REVERT_LOG"; then
        echo "❌ El log '$REVERT_LOG' no contiene marcadores RENAME|."
        echo "   Solo se pueden revertir logs generados con --apply desde"
        echo "   la versión que soporta --revert."
        exit 1
    fi

    REVERTED=0
    PENDING=0
    SKIPPED=0
    ERRORS=0

    # Leemos marcadores RENAME|origen|destino en orden INVERSO
    # (tac) para deshacer de lo más profundo a lo más superficial.
    # Esto importa si se renombraron directorios: queremos restaurar
    # primero los hijos y luego el padre.
    while IFS= read -r line; do
        # Formato: RENAME|<origen>|<destino>
        origen="${line#RENAME|}"
        origen="${origen%%|*}"
        destino="${line##*|}"

        echo "🔄 Revertir:" | tee -a "$LOGFILE"
        echo "   Actual : $destino" | tee -a "$LOGFILE"
        echo "   Volver : $origen" | tee -a "$LOGFILE"

        # ¿Existe el destino? (es lo que se renombró)
        if [ ! -e "$destino" ]; then
            echo "   ⏭️  El destino no existe (¿ya revertido?). Se omite." | tee -a "$LOGFILE"
            SKIPPED=$((SKIPPED+1))
            echo | tee -a "$LOGFILE"
            continue
        fi

        # ¿Existe ya el origen? No queremos sobrescribir
        if [ -e "$origen" ]; then
            echo "   ❌ Ya existe '$origen'. Se omite para no sobrescribir." | tee -a "$LOGFILE"
            SKIPPED=$((SKIPPED+1))
            echo | tee -a "$LOGFILE"
            continue
        fi

        # ¿El directorio del origen es escribible?
        origen_dir=$(dirname "$origen")
        if [ ! -d "$origen_dir" ] || [ ! -w "$origen_dir" ]; then
            echo "   ⛔ Sin permiso para escribir en: $origen_dir" | tee -a "$LOGFILE"
            ERRORS=$((ERRORS+1))
            echo | tee -a "$LOGFILE"
            continue
        fi

        if [ "$APPLY" -eq 1 ]; then
            mv_output=$(mv -- "$destino" "$origen" 2>&1)
            rc=$?
            if [ $rc -eq 0 ]; then
                echo "   ✅ Revertido." | tee -a "$LOGFILE"
                REVERTED=$((REVERTED+1))
            else
                case $rc in
                    1)   motivo="error general de mv" ;;
                    13)  motivo="permiso denegado (EACCES)" ;;
                    30)  motivo="sistema de archivos de solo lectura (EROFS)" ;;
                    36)  motivo="nombre demasiado largo (ENAMETOOLONG)" ;;
                    122) motivo="cuota de disco excedida (EDQUOT)" ;;
                    *)   motivo="código $rc" ;;
                esac
                echo "   ❌ Error al revertir [$motivo]: $mv_output" | tee -a "$LOGFILE"
                ERRORS=$((ERRORS+1))
            fi
        else
            echo "   🕓 Pendiente de revertir (dry-run)." | tee -a "$LOGFILE"
            PENDING=$((PENDING+1))
        fi
        echo | tee -a "$LOGFILE"
    done < <(grep '^RENAME|' "$REVERT_LOG" | tac)

    # Resumen del revert
    {
        echo "-----------------------------------------------"
        if [ "$APPLY" -eq 1 ]; then
            echo "Resumen (REVERT APLICADO):"
            echo "  ↩️  Revertidos        : $REVERTED"
            echo "  ⏭️  Omitidos           : $SKIPPED"
            echo "  ❌ Errores            : $ERRORS"
        else
            echo "Resumen (REVERT DRY-RUN — nada fue modificado):"
            echo "  🕓 Pendientes         : $PENDING"
            echo "  ⏭️  Omitidos           : $SKIPPED"
            echo "  ❌ Errores            : $ERRORS"
        fi
        echo "✅ Proceso completado. Log: $LOGFILE"
    } | tee -a "$LOGFILE"

    if [ "$APPLY" -eq 0 ]; then
        echo
        echo "ℹ️  Esto fue un dry-run. Nada se ha modificado."
        if [ "$PENDING" -gt 0 ]; then
            echo "ℹ️  Hay $PENDING renombrado(s) pendiente(s) de revertir."
            echo "    Para aplicarlos:  $0 --revert $REVERT_LOG --apply"
        fi
    fi
    exit 0
fi

# =============================================================
# MODO NORMAL (fix)
# =============================================================
LOGFILE="renombres_$(date +%Y%m%d_%H%M%S).log"

# ---------- Cabecera del log ----------
{
    echo "Registro de renombres - $(date)"
    echo "Directorio: $TARGET"
    echo "Modo: $([ "$APPLY" -eq 1 ] && echo APLICAR || echo DRY-RUN)"
    echo "Transliterador: $([ "$HAVE_UCONV" -eq 1 ] && echo 'uconv (ICU)' || echo 'iconv (fallback)')"
    echo "-----------------------------------------------"
} | tee "$LOGFILE"

RENAMED=0
PENDING=0
SKIPPED=0
ERRORS=0
WARNINGS=0

# ---------- Recorrido ----------
while IFS= read -r -d '' path; do
    dir=$(dirname "$path")
    base=$(basename "$path")
    fixed_base=$(sanitize "$base")

    if has_non_ascii "$fixed_base"; then
        echo "   ⚠️  Quedan caracteres no-ASCII tras la limpieza en: $fixed_base" \
            | tee -a "$LOGFILE"
        WARNINGS=$((WARNINGS+1))
    fi

    [ "$base" = "$fixed_base" ] && continue

    newpath="$dir/$fixed_base"

    echo "⚠️  Original : $path" | tee -a "$LOGFILE"
    echo "➡️  Nuevo    : $newpath" | tee -a "$LOGFILE"

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
    fi

    if [ -e "$newpath" ]; then
        echo "   ❌ Ya existe '$newpath'. Se omite." | tee -a "$LOGFILE"
        SKIPPED=$((SKIPPED+1)); continue
    fi

    if [ "$APPLY" -eq 1 ]; then
        mv_output=$(mv -- "$path" "$newpath" 2>&1)
        rc=$?
        if [ $rc -eq 0 ]; then
            echo "   ✅ Renombrado." | tee -a "$LOGFILE"
            RENAMED=$((RENAMED+1))
            # Marcador para --revert (se escribe SOLO en el log, no en pantalla)
            echo "RENAME|$path|$newpath" >> "$LOGFILE"
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
else
    if [ "$RENAMED" -gt 0 ]; then
        echo
        echo "↩️  Para deshacer estos cambios:"
        echo "    $0 --revert $LOGFILE"
        echo "    $0 --revert $LOGFILE --apply"
    fi
fi