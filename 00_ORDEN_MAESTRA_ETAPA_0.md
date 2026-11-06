# ORDEN MAESTRA — ETAPA 0: CIMIENTOS, ESQUELETO FLUTTER Y CONTRATOS BASE

**Para:** Jefe Local (`Antigravity / Gemini 3.8 Flash High` — Instancia \#1)  
**Agente Ejecutor Asignado:** `Freebuff / DeepSeek V4.1 Flash Fast` (vía `orquestacion-agentes-ia`)  
**Rama de destino final:** `dev` (creada desde `main`)  
**Rama de trabajo de DeepSeek:** `feat/etapa0-cimientos`

---

## 📋 1\. Instrucciones para ti, Jefe Local (Orquestador)

Tu misión en esta **Etapa 0** es inicializar el tronco común del proyecto `asistencia_uniguajira` sin escribir tú mismo la lógica de negocio, delegando la construcción pesada a **DeepSeek V4.1 Flash Fast (Freebuff)** mediante tu skill `orquestacion-agentes-ia`.

Sigue estrictamente estos pasos en orden:

### Paso 1.1: Verificar la skill y el puente hacia Freebuff (`bridge.py`)

1. Lee las instrucciones de tu skill instalada en `~/.agents/skills/orquestacion-agentes-ia/SKILL.md` (o `/home/yoner/Desktop/Projects/Laboratory/skills/orquestacion-agentes-ia/SKILL.md`).  
2. **⚠️ ATENCIÓN CRÍTICA AL PATH DE `bridge.py`:** El script original `bridge.py` tiene por defecto `base_path="/home/yoner/.config/manicode/projects/Projects/chats/*"`. Si el usuario abrió Freebuff dentro de la carpeta `asistencia_uniguajira`, los chats se guardan en `/home/yoner/.config/manicode/projects/asistencia_uniguajira/chats/*` (o en `/home/yoner/.config/manicode/projects/*/chats/*`).  
   - Antes de enviar la orden, verifica con `ls -td ~/.config/manicode/projects/*/chats/* | head -1` dónde está escribiendo Freebuff su `chat-messages.json` actual.  
   - Si está en una subcarpeta distinta a `Projects`, usa un comodín `/home/yoner/.config/manicode/projects/*/chats/*` o ajusta la función `find_target_window()` / `find_latest_chat_dir()` para que detecte la ventana de `gnome-terminal` de Freebuff y su JSON real sin quedarse colgado.  
3. **Prohibido cerrar Freebuff:** Recuerda que Freebuff descuenta bloques de saldo por cada sesión iniciada. Nunca cierres el proceso de Freebuff en su terminal; inyecta todo sobre la sesión abierta.

### Paso 1.2: Preparar las ramas base en Git

1. Asegúrate de estar en la raíz del repositorio `asistencia_uniguajira` con `README.md` y `AGENTS.md` ya confirmados en la rama `main`.  
2. Crea y publica la rama `dev` a partir de `main`:

```sh
git checkout -b dev
```

3. Crea la rama de tarea para esta Etapa 0:

```sh
git checkout -b feat/etapa0-cimientos
```

   *(Como en la Etapa 0 solo trabaja 1 agente ejecutor —DeepSeek— para construir el tronco común, puede trabajar directamente sobre el directorio principal en la rama `feat/etapa0-cimientos`. Los `git worktree` se activarán a partir de la Etapa 1 cuando entren varios agentes en paralelo).*

### Paso 1.3: Inyectar el Prompt Técnico a DeepSeek vía `bridge.py`

Envía a Freebuff/DeepSeek **exactamente** el bloque de la **Sección 2** de este documento (puedes guardarlo en un archivo temporal `/tmp/prompt_etapa0.txt` y pasarlo con `cat /tmp/prompt_etapa0.txt | python3 .../bridge.py --timeout 600`).

---

## 🚀 2\. Prompt Técnico Exacto para Inyectar a DeepSeek (Agente 1\)

```
Actúa como Core & Protocol Engineer para el proyecto `asistencia_uniguajira` (Etapa 0: Cimientos y Contratos Base).
Primero lee `README.md` y `AGENTS.md` en la raíz del repositorio y respeta todas sus restricciones (cero reconocimiento facial, cero ultrasonido, cero TODOs o mocks falsos, cero compilaciones paralelas).

Estamos en la rama `feat/etapa0-cimientos`. Ejecuta de principio a fin las siguientes tareas en este directorio:

1. INICIALIZACIÓN DE FLUTTER (PRESERVANDO ARCHIVOS EXISTENTES):
   - Si aún no existe `pubspec.yaml`, ejecuta `flutter create --org co.edu.uniguajira --project-name asistencia_uniguajira --platforms=android .` (asegúrate de NO borrar ni sobrescribir el contenido de nuestro `README.md` ni `AGENTS.md`; si `flutter create` modifica `README.md`, restaura nuestro `README.md` con `git checkout README.md`).

2. CONFIGURACIÓN DE `pubspec.yaml`:
   Configura las dependencias necesarias para el alcance aprobado y ejecuta `flutter pub get`:
   - `sqflite` y `path` (Base de datos local Offline-First)
   - `crypto` (Criptografía HMAC-SHA256)
   - `flutter_blue_plus` y `flutter_ble_peripheral` (Escaneo y emisión BLE)
   - `permission_handler` (Permisos de Bluetooth y ubicación en Android)
   - `file_picker`, `csv` y `excel` (Importación y exportación de listas .csv y .xlsx)
   - `mobile_scanner` y `qr_flutter` (Enrolamiento local por QR del primer día)
   - `google_sign_in`, `googleapis` y `http` (Sincronización opcional con Google Sheets @uniguajira.edu.co)
   - `intl` y `uuid` (Formateo de fechas e identificadores)
   - En `dev_dependencies`: `flutter_test`, `flutter_lints` y `sqflite_common_ffi` (CRÍTICO: `sqflite_common_ffi` es obligatorio para que las pruebas unitarias de SQLite corran en Linux Mint sin necesitar un celular conectado).

3. ESTRUCTURA DE DIRECTORIOS (`lib/`):
   Crea la siguiente arquitectura limpia por capas y features:
   - `lib/core/constants/app_constants.dart` (Constantes globales: ventana de rotación HMAC de 30s, tamaño de Bitmap de 8 bytes / 64 bits, RSSI mínimo por defecto `-75 dBm`, dominio `@uniguajira.edu.co`).
   - `lib/core/models/` (Contratos inmutables con `toMap()`, `fromMap()`, `copyWith()`):
     * `course_model.dart`: `id` (String/UUID), `code` (String), `name` (String), `groupCode` (String), `semester` (String), `courseSecret` (String hex de 32 bytes para HMAC), `spreadsheetId` (String? opcional para Google Sheets), `createdAt` (String ISO8601).
     * `student_model.dart`: `id` (String/UUID), `courseId` (String), `studentCode` (String - código Uniguajira), `fullName` (String), `email` (String?), `bitIndex` (int de 0 a 63, único por curso), `personalSecret` (String hex derivado para HMAC), `enrolledAt` (String? ISO8601).
     * `session_model.dart`: `id` (String/UUID), `courseId` (String), `startedAt` (String ISO8601), `closedAt` (String? ISO8601), `roomPin` (String de 2 dígitos para evitar fraude de pasillo), `bitmapHex` (String hex de 16 caracteres = 8 bytes representando los 64 bits de asistencia), `actHash` (String? SHA-256 del acta cerrada), `syncedToCloud` (int 0 o 1).
     * `attendance_record_model.dart`: `id` (String/UUID), `sessionId` (String), `studentId` (String), `bitIndex` (int 0..63), `method` (String: `'BLE_HMAC'` o `'MANUAL_INVERTED'`), `rssiAvg` (double?), `recordedAt` (String ISO8601), `hmacTag` (String?).
   - `lib/data/local/app_database.dart`:
     * Singleton de SQLite usando `sqflite` (y compatible con `databaseFactoryFfi` para tests en Linux).
     * Creación de las 4 tablas relacionales (`courses`, `students`, `sessions`, `attendance_records`) con claves foráneas activadas (`PRAGMA foreign_keys = ON`), restricción `UNIQUE(course_id, bit_index)` y `UNIQUE(course_id, student_code)` en `students`, y restricción `UNIQUE(session_id, student_id)` en `attendance_records`.
     * Métodos CRUD base limpios y tipados para insertar y consultar cursos, estudiantes (validando el límite de 64 posiciones por grupo para el Bitmap de 8 bytes), sesiones y registros de asistencia.
   - `lib/features/teacher/teacher_placeholder_screen.dart` y `lib/features/student/student_placeholder_screen.dart`:
     * Pantallas iniciales limpias (sin errores de lint) conectadas desde un selector de rol en `lib/main.dart` ("Modo Docente" / "Modo Estudiante") con los colores institucionales de Uniguajira, listas para que en las Etapas 1, 2 y 3 los agentes de UI construyan encima sin chocar en `main.dart`.

4. PRUEBA UNITARIA DE CIMIENTOS (`test/app_database_test.dart`):
   - Reemplaza el `widget_test.dart` por defecto con `test/app_database_test.dart` usando `sqflite_common_ffi` en memoria (`inMemoryDatabasePath`).
   - La prueba debe verificar:
     a) Creación de un curso.
     b) Inserción de estudiantes con asignación de `bitIndex` (0..63) y rechazo de duplicados de `(course_id, bit_index)`.
     c) Creación de una sesión con `roomPin` de 2 dígitos y actualización de `attendance_records`.

5. VERIFICACIÓN Y COMMIT:
   - Ejecuta `flutter analyze --no-pub` y corrige cualquier warning o error hasta que salga "No issues found!".
   - Ejecuta `flutter test` y verifica que `test/app_database_test.dart` pase al 100%.
   - Haz `git add .` y `git commit -m "feat(etapa0): initialize flutter skeleton, sqlite schema and core models"` en la rama `feat/etapa0-cimientos`. No hagas merge a `dev` ni `main`. Reporta el resultado final.
```

---

## 🔍 3\. Auditoría Binaria del Jefe Local (Cierre de Etapa 0\)

Cuando `bridge.py` te devuelva la respuesta final de DeepSeek (`isComplete: true`), tú (**Jefe Local**) debes ejecutar en tu terminal:

1. `git status` y `git log -n 2` para confirmar el commit en `feat/etapa0-cimientos`.  
2. `flutter analyze --no-pub` (Debe dar **0 errores y 0 warnings**).  
3. `flutter test` (Debe pasar **100 % en verde**).  
4. `grep -rn "TODO\|FIXME" lib/ test/` (Debe estar vacío).  
- **Si falla algún punto:** Inyecta de nuevo a DeepSeek con `bridge.py` el error exacto para que lo corrija en la misma sesión.  
- **Si pasa los 4 puntos:** Ejecuta el merge hacia `dev` y `main` (para dejar el tronco común sellado):

```sh
git checkout dev
git merge --no-ff feat/etapa0-cimientos -m "merge: etapa 0 cimientos aprobados en dev"
git checkout main
git merge --no-ff dev -m "release: etapa 0 tronco comun estable"
git checkout dev
```

Finalmente, entrega un reporte ejecutivo corto a Yoner confirmando que el tronco común está en `dev` y `main`.