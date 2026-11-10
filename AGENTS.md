# Manual operativo para agentes de IA — Asistencia Uniguajira

Rige cómo trabajan los agentes de IA en este repositorio. Si algo de este
archivo choca con una instrucción de un brief, gana este archivo.

---

## 1. Roles

| Rol | Quién | Qué hace |
|---|---|---|
| **Dueños del producto y QA de hardware** | Yoner y Álvaro (humanos) | Aprueban cada oleada y prueban los `.apk` en **2 celulares Android reales**. Ninguna oleada se da por terminada sin esa prueba. |
| **Agente jefe** | Claude Code | Escribe los briefs, crea las ramas y los *worktrees*, abre los Pull Requests, hace la revisión de código, corre `flutter analyze` y `flutter test` y decide el *merge* a `dev`. |
| **Agentes trabajadores** | Gemini (CLI `agy`) | Implementan **una tarea por rama**, en su propio *worktree*, tocando solo los archivos que dice su brief. |

La fuente de verdad del producto es `Proyecto grado/PROPUESTA_OFICIAL.md`
(fuera de este repo). Si un brief y la propuesta se contradicen, se detiene el
trabajo y se pregunta al agente jefe.

---

## 2. Flujo de trabajo (una tarea = una rama = un PR)

1. El agente jefe crea la rama desde `dev` y su *worktree*:
   ```bash
   git worktree add ../worktrees/<rama> -b <rama> dev
   ```
2. El agente trabajador recibe su brief (`docs/agentes/briefs/<id>.md`) y
   trabaja **solo dentro de** `../worktrees/<rama>`.
3. Al terminar, el trabajador hace *commits* pequeños con mensajes en español
   (`fix(ble): …`, `feat(flavors): …`) y **no hace push**.
4. El agente jefe hace push, abre el PR hacia `dev` con
   `gh pr create --base dev` y lo revisa con la lista de la sección 4.
5. Si algo falla, el agente jefe devuelve al trabajador el error exacto y el
   archivo y la línea. El trabajador corrige en la misma rama.
6. Con la revisión aprobada y el CI en verde, el agente jefe hace *squash merge*
   a `dev` y elimina el *worktree*.
7. `main` solo recibe `dev` cuando Yoner y Álvaro aprueban la prueba con
   2 celulares reales.

---

## 3. Reglas para los agentes trabajadores

1. **Aislamiento:** solo se modifican los archivos que el brief lista en
   "Archivos permitidos". Si hace falta tocar otro, se detiene y se reporta.
2. **Sin merge ni push:** ningún trabajador ejecuta `git merge`, `git push`,
   `git rebase` sobre `dev`/`main` ni cambia de rama.
3. **Sin compilaciones pesadas en paralelo** (el PC tiene 16 GB de RAM):
   el trabajador puede correr `flutter analyze --no-pub` en su *worktree*, pero
   **no** `flutter test` ni `flutter build`. Las pruebas las corre el agente
   jefe, una rama a la vez.
4. **Sin dependencias nuevas:** no se agregan paquetes a `pubspec.yaml`.
   Si hace falta uno, se pide al agente jefe (el *sandbox* no tiene red).
5. **Código completo:** se rechaza cualquier entrega con `// TODO`, `// FIXME`,
   métodos vacíos, datos falsos quemados en el código o errores silenciados
   (`catch (_) {}` sin informar al usuario ni registrar el error).
6. **Pruebas:** cada cambio de lógica en `lib/core/` o `lib/data/` llega con
   su prueba en `test/`.
7. **Diseño:** las pantallas usan los tokens de `lib/theme/` (colores,
   espaciados, radios). Nada de colores ni medidas sueltas.
8. **Idioma:** comentarios, mensajes al usuario y commits en español.

### Alcance prohibido (no se implementa nunca)

- GPS, geolocalización, geovallas o ubicación simulada como mecanismo de asistencia.
- QR dinámico como mecanismo de asistencia (el QR solo sirve para inscribirse).
- Servidor propio, *backend* o base de datos en la nube distinta del Google Drive del docente.
- Reconocimiento facial, ultrasonido, OCR de capturas.
- Conexión o *scraping* al sistema académico de la universidad.
- Promesas en la interfaz como "100 % seguro" o "imposible de suplantar".

---

## 4. Lista de revisión de cada PR (agente jefe)

Un PR se aprueba solo si cumple **todo**:

1. **[Aislamiento]** Solo cambió los archivos permitidos por su brief.
2. **[Integridad]** Sin `TODO`, `FIXME`, simulaciones en pantallas de producción ni errores silenciados.
3. **[Análisis estático]** `flutter analyze --no-pub` → 0 errores y 0 *warnings*.
4. **[Pruebas]** `flutter test` → 100 % en verde (local y en el CI de GitHub).
5. **[Criterios del brief]** Cada criterio de aceptación del brief está cumplido y se puede señalar en el diff.
6. **[Hardware]** Si el cambio toca Bluetooth, permisos o *flavors*: queda anotado en el PR qué se debe probar en los 2 celulares reales.

---

## 5. Comandos útiles

```bash
./run.sh analyze                     # análisis estático
./run.sh test                        # todas las pruebas
flutter run --flavor docente -t lib/main_docente.dart        # (tras la Oleada 1)
flutter run --flavor estudiante -t lib/main_estudiante.dart  # (tras la Oleada 1)
adb devices                          # celulares conectados
```
