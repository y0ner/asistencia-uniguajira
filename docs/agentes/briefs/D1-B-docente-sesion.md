# Brief D1-B · Docente · Sesión en vivo

- **Rama:** `feat/ui-docente-sesion` · **Worktree:** `../worktrees/feat-ui-docente-sesion`
- **Lee primero:** `AGENTS.md`, `docs/agentes/briefs/D1-comun.md`, `docs/diseno/SISTEMA.md`.
- **Mockup:** `docs/diseno/mockups/B-Sesion.html`.
- **Objetivo:** que el profesor vea de un vistazo quién llegó y quién falta, con nombres.

## Archivos permitidos

- `lib/features/teacher/live_attendance_session_screen.dart`
- `test/ui/docente_sesion_test.dart` (**nuevo**)

## Qué se conserva (lógica)

Constructor completo, `_initializeSession`, `_reloadRecords`, `_handleToggleManual`,
la nota de observación, `_handleCloseAndSignSession`, la verificación de permisos
y Bluetooth antes de iniciar, el *wakelock*, las suscripciones a eventos y a
problemas de Bluetooth, el refresco periódico y la confirmación al salir.

## Qué desaparece

Las dos pestañas ("radar" y lista invertida), la cuadrícula del mapa de bits y
cualquier dato técnico en pantalla (RSSI, rotación, *tick*, huellas, bytes).
Quita el `TabController` si queda sin uso.

## Cómo debe quedar

`UiPage` con:

1. **Barra:** `UiTopBar(title: nombre de la clase, close: true, backTooltip: 'Salir de la sesión',
   trailing: UiPill(label: 'En vivo · <UiFormat.time>', dot: true))`.
2. **Tarjeta de resumen** (`UiCard`, radio `UiRadius.xl`): a la izquierda
   `UiProgressRing.count(count: llegaron, total: estudiantes)`; a la derecha, en columna:
   "PIN de la clase", `UiPinDisplay(pin: PIN de 2 dígitos)`, "Díctalo en voz alta".
3. **Avisos** (solo si hay un problema de Bluetooth): `UiBanner` con el mensaje del
   problema y su acción si la tiene.
4. **Filtros:** `UiFilterPills` con "Todos N", "Faltan N" y "Llegaron N" ("Llegaron"
   incluye Bluetooth y a mano).
5. **Buscar** (`TextField` con "Buscar estudiante"): solo si la clase tiene más de 12 estudiantes.
6. **Lista** (`ListView.builder` dentro de una tarjeta con separadores; filas `UiPersonRow`):
   - **Llegó por Bluetooth:** detalle "<hora> · Bluetooth", `UiStatusChip(status: present)`.
     Quien llegó hace menos de 10 s: `highlighted: true`, chip `solid: true` y detalle
     "Acaba de llegar · Bluetooth".
   - **A mano:** `avatarTone: UiTone.manual`, detalle "<hora> · <nota, o 'A mano'>",
     `UiStatusChip(status: manual)`. Al tocar la fila: hoja con "Editar nota" y "Quitar marca".
   - **Aún no llega:** `avatarTone: UiTone.neutral`, detalle "Aún no llega" y
     `UiButton(label: 'Marcar', variant: outline, compact: true, expand: false)`.
     "Marcar" registra la asistencia a mano y luego ofrece la nota en una hoja:
     título "Nota (opcional)", campo con ejemplo "No trajo celular", botones "Guardar" y "Omitir".
   - Orden en "Todos": primero los recién llegados, luego el orden actual de la lista.
   - Lista filtrada vacía: `UiEmptyState` pequeño ("Ya llegaron todos" / "Aún no llega nadie").
7. **Con cero llegados:** sobre la lista, `UiBanner(tone: info, message: 'Dicta el PIN y pide
   a tus estudiantes que acerquen el celular al tuyo.')`.
8. **Abajo:** `UiButton(label: 'Cerrar y firmar la sesión')`. Confirma con `showUiConfirm`:
   título "¿Cerrar la sesión?", mensaje "Llegaron X de Y. Los Z que faltan quedarán con falta.
   Después de firmar no se puede cambiar.", botón "Cerrar y firmar".
9. **Antes de iniciar:**
   - Abriendo: indicador con "Abriendo la sesión…".
   - Falta un permiso o el Bluetooth está apagado: título claro ("El Bluetooth está apagado" /
     "Falta un permiso"), una frase de qué hacer y los botones que ya existen con estos textos:
     "Encender Bluetooth", "Abrir ajustes", "Volver a intentar".
   - Error al abrir: `UiEmptyState` con "No se pudo abrir la sesión" y "Volver a intentar".
10. **Salir con la sesión abierta:** `showUiConfirm` — "¿Salir de la sesión?",
    "La sesión sigue abierta. Puedes volver desde la clase.", botones "Salir" y "Seguir aquí".

## Criterios de aceptación (además de los comunes)

- [ ] `grep -n "TabBar\|TabController\|_buildBitmapGrid\|_buildRadarBleTab" <archivo>` no devuelve nada.
- [ ] `test/ui/docente_sesion_test.dart` con servicios falsos: (a) con Bluetooth apagado
      muestra "El Bluetooth está apagado" y "Encender Bluetooth"; (b) con todo listo y 3
      estudiantes muestra el PIN, "Todos 3" y un botón "Marcar" por estudiante. Claro y oscuro,
      360 × 640, letra al 130 %, sin excepciones.
