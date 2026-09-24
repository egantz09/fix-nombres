# fix-nombres.sh

Script en Bash para **detectar y corregir nombres de ficheros y directorios** con caracteres corruptos, acentos, diéresis y otros caracteres especiales. Ideal para limpiar bibliotecas de música, fotos, documentales o cualquier colección de archivos heredada de sistemas con codificaciones mixtas (ZIP, FAT, descargas antiguas, etc.).

![Bash](https://img.shields.io/badge/bash-%3E%3D4.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-lightgrey)

---

## ✨ Características

- 🔤 **Elimina acentos y diéresis**: `Canción.mp3` → `Cancion.mp3`.
- 🌍 **Transliteración robusta**: usa [`uconv`](https://manpages.debian.org/testing/icu-devtools/uconv.1.en.html) (ICU) si está disponible, con fallback a `iconv`.
- 🩹 **Repara nombres corruptos** (mojibake Latin-1 → UTF-8), típicos de nombres que se ven como `Producci�n`.
- 📂 **Procesa directorios y ficheros**, incluidos nombres anidados con acentos.
- 🔒 **Comprueba permisos** antes de tocar nada: lectura, escritura, acceso (`x`), sistema de archivos de solo lectura.
- 🛡️ **Nunca sobrescribe**: si el destino ya existe, lo omite y lo registra.
- 📝 **Log detallado con timestamp** (`renombres_YYYYMMDD_HHMMSS.log`).
- 🧪 **Modo dry-run por defecto**: no modifica nada hasta que uses `--apply`.
- 🕓 **Contador de pendientes** en dry-run, para saber cuántos nombres se renombrarían.
- ⚠️ **Aviso de bytes no-ASCII** que sobrevivan a la limpieza (emojis, griego, cirílico…).
- 🧱 **Soporta espacios, saltos de línea y nombres que empiezan por `-`** gracias a `find -print0`, `read -d ''` y `mv --`.
- 🧭 **`-depth`**: renombra primero los hijos y luego los directorios padre, evitando romper rutas.
- ↩️ **Modo `--revert`**: deshace los renombrados usando el log, en orden inverso.

---

## 📦 Requisitos

- **Bash** ≥ 4.0
- **coreutils** (`find`, `mv`, `sed`, `dirname`, `basename`)
- **`iconv`** (viene con `glibc` o `libiconv` en macOS)
- **`uconv`** (opcional, pero muy recomendado)

### Instalar `uconv` (ICU)

```bash
# Debian / Ubuntu
sudo apt install icu-devtools

# Fedora / RHEL / CentOS
sudo dnf install icu

# Arch Linux / Manjaro
sudo pacman -S icu

# macOS (Homebrew)
brew install icu4c
# Puede que necesites añadir al PATH:
# export PATH="/opt/homebrew/opt/icu4c/bin:$PATH"
```

Si `uconv` no está instalado, el script funciona igual usando `iconv` como fallback (con menor cobertura de transliteración).

---

## 🚀 Instalación

```bash
# 1. Clona el repositorio
git clone https://github.com/tu-usuario/fix-nombres.git
cd fix-nombres

# 2. Da permisos de ejecución
chmod +x fix-nombres.sh

# 3. (Opcional) Muévelo a tu PATH
sudo mv fix-nombres.sh /usr/local/bin/fix-nombres
```

---

## 🧑‍💻 Uso

```bash
# Dry-run sobre el directorio actual (no modifica nada)
./fix-nombres.sh

# Dry-run sobre una ruta concreta
./fix-nombres.sh /ruta/a/musica

# Aplicar los cambios
./fix-nombres.sh --apply /ruta/a/musica

# Deshacer usando el log más reciente (dry-run)
./fix-nombres.sh --revert

# Deshacer usando un log concreto (dry-run)
./fix-nombres.sh --revert renombres_20260922_174123.log

# Aplicar el revert
./fix-nombres.sh --revert --apply

# Aplicar el revert con log concreto
./fix-nombres.sh --revert renombres_20260922_174123.log --apply

# Ver la ayuda
./fix-nombres.sh --help
```

### Ejemplo de salida (dry-run)

```
Registro de renombres - Tue Sep 22 17:41:23 UTC 2026
Directorio: /home/programacion/
Modo: DRY-RUN
Transliterador: uconv (ICU)
-----------------------------------------------
⚠️  Original : /home/programacion/.../ALFABETO FAMILIAR (Producci�n para Internet)
➡️  Nuevo    : /home/programacion/.../ALFABETO FAMILIAR (Produccion para Internet)
   🕓 Pendiente de aplicar (dry-run).

-----------------------------------------------
Resumen (DRY-RUN — nada fue modificado):
  🕓 Pendientes         : 3
  ⏭️  Omitidos           : 0
  ⚠️  Avisos no-ASCII   : 0
  ❌ Errores            : 0
✅ Proceso completado. Log: renombres_20260922_174123.log

ℹ️  Esto fue un dry-run. Nada se ha modificado.
ℹ️  Hay 3 nombre(s) pendiente(s) de renombrar.
    Para aplicarlos:  ./fix-nombres.sh --apply /home/programacion/
```

### Ejemplo de salida (aplicado)

```
Resumen (APLICADO):
  ✅ Renombrados        : 3
  ⏭️  Omitidos           : 0
  ⚠️  Avisos no-ASCII   : 0
  ❌ Errores            : 0
```

---

## 📋 Qué limpia exactamente

| Tipo | Ejemplo original | Resultado |
|---|---|---|
| Acentos | `Canción.mp3` | `Cancion.mp3` |
| Diéresis | `Über.mp3` | `Uber.mp3` |
| Ñ | `Ñandú.mp3` | `Nandu.mp3` |
| Alemán `ß` | `Straße.mp3` | `Strasse.mp3` |
| Ligaduras | `Ægir œuf.mp3` | `AEgir oeuf.mp3` |
| Escandinavo | `østers ångström.mp3` | `osters angstrom.mp3` |
| Mojibake Latin-1 | `Producci�n.mp3` | `Produccion.mp3` |
| Griego (con uconv) | `Μουσική.mp3` | `Mousike.mp3` |
| Cirílico (con uconv) | `Музыка.mp3` | `Muzyka.mp3` |

Los caracteres **no cubiertos** (emojis, símbolos) se dejan tal cual y se **reportan como aviso** en el log para que decidas si actuar manualmente.

---

## 🛡️ Seguridad

- **Dry-run por defecto**: no se mueve nada hasta que pases `--apply`.
- **Nunca sobrescribe**: si el destino existe, lo registra como omitido.
- **Log con timestamp**: cada ejecución genera un log nuevo, nunca se pisa.
- **Comprueba permisos**: si no puedes leer o escribir en un directorio, lo registra en vez de fallar silenciosamente.
- **`mv --`**: evita que nombres que empiezan por `-` se interpreten como opciones.

### Recomendaciones

1. **Haz copia de seguridad** antes de aplicar sobre bibliotecas grandes.
2. **Ejecuta primero el dry-run** y revisa el log.
3. Si aparecen muchos `⛔ find: Permission denied`, ejecuta con `sudo` **solo después de revisar** el dry-run.

---

## ↩️ Revertir cambios

El script guarda en el log una línea por cada renombrado exitoso, con el formato:

```
RENAME|<origen>|<destino>
```

Eso permite **deshacer** los cambios con `--revert`. Por defecto es dry-run; hay que
combinarlo con `--apply` para aplicarlo de verdad.

```bash
# Ver qué se revertiría usando el log más reciente
./fix-nombres.sh --revert

# Ver qué se revertiría usando un log concreto
./fix-nombres.sh --revert renombres_20260922_174123.log

# Aplicar el revert
./fix-nombres.sh --revert --apply
```

### Ejemplo de salida (revert aplicado)

```
Registro de REVERT - Tue Sep 22 17:55:01 UTC 2026
Log fuente: renombres_20260922_174123.log
Modo: APLICAR
-----------------------------------------------
🔄 Revertir:
   Actual : /home/programacion/.../ALFABETO FAMILIAR (Produccion para Internet)
   Volver : /home/programacion/.../ALFABETO FAMILIAR (Producci�n para Internet)
   ✅ Revertido.

-----------------------------------------------
Resumen (REVERT APLICADO):
  ↩️  Revertidos        : 3
  ⏭️  Omitidos           : 0
  ❌ Errores            : 0
✅ Proceso completado. Log: revert_20260922_175501.log
```

### Notas importantes

- **Solo funciona con logs generados con `--apply`** por la versión que ya soporta
  `--revert` (los logs antiguos no llevan marcadores `RENAME|` y se rechazan).
- **No sobrescribe**: si el nombre original ya existe, se omite y se registra.
- **Revertir directorios**: se procesan en orden inverso (primero los hijos,
  luego los padres) para no romper rutas.
- Cada revert genera un log nuevo `revert_YYYYMMDD_HHMMSS.log`.

---

## 🧪 Probar con el script de test

El repositorio incluye `test-fix-nombres.sh`, que crea un entorno con casos problemáticos (acentos, ß, griego, cirílico, espacios múltiples, permisos denegados, colisiones) y ejecuta el script en dry-run y modo real:

```bash
chmod +x test-fix-nombres.sh
./test-fix-nombres.sh
```

---

## 📂 Estructura del repositorio

```
fix-nombres/
├── fix-nombres.sh          # Script principal
├── test-fix-nombres.sh     # Entorno de prueba con casos variados
├── README.md               # Este archivo
└── LICENSE                 # MIT (opcional)
```

Los logs generados (`renombres_*.log` y `revert_*.log`) están ignorados por
`.gitignore` y no se suben al repositorio.

---

## ⚠️ Limitaciones

- **No es un renombrador en masa con regex**: solo normaliza acentos y caracteres corruptos.
- **Solo revierte lo que el propio script renombró**, y solo si conservas el log correspondiente. No puede deshacer cambios manuales ni de otras herramientas.
- **Requiere permisos** sobre los directorios afectados para renombrar.
- **Límite del sistema de archivos**: nombres de más de 255 bytes o rutas de más de 4096 bytes fallarán (`ENAMETOOLONG`), y se registrará en el log.
- **Emojis y alfabetos no cubiertos por ICU** permanecen (se avisa con `⚠️`).

---

## 🗺️ Roadmap / Ideas futuras

- [x] Flag `--revert` para deshacer usando el log.
- [ ] `--exclude` para ignorar carpetas (`.git`, `node_modules`, etc.).
- [ ] Modo `--interactive` (preguntar uno a uno).
- [ ] Opción `--collapse-spaces` para normalizar espacios múltiples.
- [ ] Soporte para normalización Unicode NFC/NFD (típico en macOS).
- [ ] Empaquetado como script instalable vía `curl | bash`.

Las contribuciones y sugerencias son bienvenidas vía *issues* o *pull requests*.

---

## 🤝 Contribuir

1. Haz un fork del repositorio.
2. Crea una rama: `git checkout -b feature/mi-mejora`.
3. Haz commit de tus cambios: `git commit -am 'Añade X'`.
4. Push a tu fork: `git push origin feature/mi-mejora`.
5. Abre un Pull Request.

---

## 📄 Licencia

Distribuido bajo la licencia **MIT**. Consulta `LICENSE` para más información.

---

## 🙏 Agradecimientos

- A [ICU](https://icu.unicode.org/) por las tablas de transliteración de `uconv`.
- A la comunidad de [GNU coreutils](https://www.gnu.org/software/coreutils/) por las herramientas base.
- A todos los que han sufrido con nombres como `Producci�n` y han sobrevivido para contarlo.

---

## 💬 Contacto

Si el script te ha sido útil, ⭐ al repositorio. Si encuentras un bug o quieres proponer una mejora, abre un *issue*.