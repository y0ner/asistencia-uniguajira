# Manual Operativo para Agentes de IA — Asistencia Uniguajira

Este documento rige el comportamiento, los roles, el puente de orquestación desatendida y los límites estrictos de los agentes de inteligencia artificial que operan en las terminales locales del proyecto `asistencia_uniguajira`.

---

## 👥 Jerarquía y Topología de Terminales

1. **Product Owners & QA Hardware Leads (Humanos — Yoner y Álvaro):**  
   - Autoridad máxima del proyecto. Aprueban las etapas, supervisan las ventanas de terminal y ejecutan las pruebas físicas de `.apk` en dispositivos Android reales al cierre de cada etapa.  
2. **Principal System Architect & Spec Director (Gemini Web):**  
   - Diseña los planos arquitectónicos, contratos de datos y órdenes técnicas cerradas (`Specs`) de cada etapa para evitar alucinaciones de código.  
3. **Lead Release & Integration Orchestrator — Jefe Local (Antigravity / Gemini 3.8 Flash High — Instancia \#1):**  
   - **Rol:** Orquestador y Auditor Senior. **NO escribe lógica de negocio.**  
   - **Skill Obligatoria:** Debe consultar y utilizar siempre la skill local `orquestacion-agentes-ia` (`~/.agents/skills/orquestacion-agentes-ia/SKILL.md` o `/home/yoner/Desktop/Projects/Laboratory/skills/orquestacion-agentes-ia/scripts/bridge.py`) para delegar tareas a **Freebuff (DeepSeek V4.1 Flash Fast)** de forma desatendida vía X11 (`xclip` \+ `xdotool`) y monitorear la finalización real leyendo `~/.config/manicode/projects/.../chat-messages.json` hasta `"isComplete": true`.  
   - **Responsabilidades:** Administrar las ramas `main` y `dev`, gestionar directorios aislados mediante `git worktree` (cuando haya trabajo paralelo en Etapas 1–4), inyectar los prompts a los agentes trabajadores mediante `bridge.py`, ejecutar la auditoría binaria de Pull Requests (`flutter analyze --no-pub` y `flutter test`) de forma secuencial y autorizar el *merge* hacia `dev` y `main`.  
4. **Core & Protocol Engineer — Agente Trabajador Principal (Freebuff / DeepSeek V4.1 Flash Fast 10/17):**  
   - **Rol:** Motor lógico, criptográfico y de persistencia (`lib/core/` y `lib/data/`).  
   - **Regla Crítica de Saldo (4h/día):** Freebuff descuenta bloques de saldo por cada sesión iniciada. **PROHIBIDO cerrar o reiniciar el proceso de Freebuff entre comandos.** El Jefe Local debe reutilizar siempre la misma ventana activa de `gnome-terminal` inyectando las órdenes con `bridge.py`.  
   - **Ajuste de Ruta JSON en `bridge.py`:** Si Freebuff fue abierto dentro de la carpeta `asistencia_uniguajira`, el archivo de sesión se guarda en `~/.config/manicode/projects/asistencia_uniguajira/chats/<timestamp>/chat-messages.json` (o `.../Projects/chats/...` según desde dónde se lanzó). El Jefe Local debe verificar con `ls -td ~/.config/manicode/projects/*/chats/* | head -1` que `bridge.py` esté apuntando al directorio activo correcto.  
5. **Escuadrón UI & QA (Instancias adicionales de Gemini 3.8 Flash High — Etapas 1 a 4):**  
6. **Gemini \#2 (UI Docente):** Aislado en `lib/features/teacher/` (Cursos, Radar BLE en vivo, Lista Invertida, Acta).  
   - **Gemini \#3 (UI Estudiante):** Aislado en `lib/features/student/` (Escáner QR de enrolamiento, PIN verbal de 2 dígitos, Sello Verde).  
   - **Gemini \#4 (QA & Unit Tests):** Aislado en `test/`.  
   - **Gemini \#5 (Fixer / Configuración Nativa):** Aislado en `android/` (`AndroidManifest.xml`, `build.gradle`) cuando se requiera.

---

## 🚫 Restricciones Absolutas (Prohibido)

1. **Cero inventos de alcance:** Queda terminantemente prohibido implementar o crear carpetas para:  
   - Reconocimiento facial o visión artificial por cámara (`MediaPipe`, `MobileFaceNet`).  
   - Ultrasonido acústico de alta frecuencia (`18.5 - 20 kHz`, `FSK`, `FFT`, `Goertzel`).  
   - Motor complejo de OCR sobre capturas con distancia difusa `Jaro-Winkler`.  
   - Conexiones directas o *scraping* hacia el sistema SMA de la Universidad de La Guajira.  
2. **Cero *Merges* directos a `main` o `dev` por trabajadores:** Ningún agente trabajador tiene permiso para ejecutar `git merge` o `git push` directo sobre `main` o `dev`. Todo trabajo se realiza en una rama aislada por tarea (ej. `feat/etapa0-cimientos`, `feat/etapa1-ingesta`).  
3. **Cero colisión de carpetas Git:** Dos agentes jamás deben modificar archivos ni cambiar de rama simultáneamente sobre el mismo directorio físico. En la **Etapa 0** trabaja únicamente DeepSeek en secuencia. En las **Etapas 1 a 4**, si dos agentes operan en paralelo, el Jefe Local debe aislarlos con `git worktree add ../worktrees/<nombre-rama> <nombre-rama>`.  
4. **Cero compilaciones en paralelo (Protección de 16 GB RAM):** Los agentes trabajadores tienen prohibido ejecutar `flutter test`, `flutter analyze` o `flutter build apk` al mismo tiempo. Solo el Jefe Local ejecuta las validaciones de manera secuencial.  
5. **Cero código incompleto (*Mocks* o `TODO`):** Se rechaza automáticamente cualquier entrega que contenga comentarios `// TODO`, `// FIXME`, métodos vacíos o datos falsos quemados en código (*hardcoded*) donde debe ir persistencia real en SQLite.

---

## ✅ Lista de Chequeo Binaria para PR Review (Jefe Local)

Antes de aprobar el paso de una rama de tarea hacia `dev`, el Jefe Local verificará estrictamente estos 4 puntos:

1. **\[Aislamiento\]:** ¿El agente modificó únicamente los archivos asignados a su misión sin romper contratos ajenos?  
2. **\[Integridad\]:** ¿El código está 100 % libre de `TODO`, `FIXME` y simulaciones falsas?  
3. **\[Análisis Estático\]:** ¿El comando `flutter analyze --no-pub` arroja exactamente **0 errores y 0 warnings**?  
4. **\[Pruebas Unitarias\]:** ¿El comando `flutter test` sobre el módulo entregado pasa al 100 %?

Si falla cualquiera de los 4 puntos, el Jefe Local rechaza la integración e inyecta de vuelta a través de `bridge.py` el error exacto de consola para su corrección inmediata.