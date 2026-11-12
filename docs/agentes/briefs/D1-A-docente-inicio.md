# Brief D1-A · Docente · Inicio ("Tus clases")

- **Rama:** `feat/ui-docente-inicio` · **Worktree:** `../worktrees/feat-ui-docente-inicio`
- **Lee primero:** `AGENTS.md`, `docs/agentes/briefs/D1-comun.md`, `docs/diseno/SISTEMA.md`.
- **Mockup:** `docs/diseno/mockups/B-Main.html`.
- **Objetivo:** rehacer la pantalla de inicio del docente con el diseño B.

## Archivos permitidos

- `lib/features/teacher/courses_dashboard_screen.dart`
- `test/ui/docente_inicio_test.dart` (**nuevo**)

## Qué se conserva (lógica)

Constructor (`database`), `_loadCourses`, `_generateRandomSecretHex`, la creación
y eliminación de clases, `_navigateToCourseDetail` y la apertura del diagnóstico
(`showHardwareDiagnosticDialog`).

## Cómo debe quedar

`UiPage` con:

1. **Encabezado:** `UiBrandHeader`, con un `UiRoundIconButton` (`Icons.tune_rounded`,
   tooltip "Ajustes y diagnóstico") que abre el diagnóstico actual.
2. **Saludo:** `UiPageHeading(overline: UiFormat.longDate(hoy), title: '<saludo>, profe')`
   con `UiFormat.greeting`.
3. **Lista "Tus clases"** (`UiSectionTitle` + una `UiCard` por clase, radio 18, con `onTap`):
   `UiAvatar(name: nombre, square: true)`, nombre (`UiText.title`), debajo
   "Grupo 01 · 32 estudiantes" (`UiFormat.count`). Si la clase no tiene
   estudiantes: "Grupo 01 · Falta agregar estudiantes" y `UiPill(label: 'Nueva', tone: UiTone.manual)`.
   A la derecha, un `UiRoundIconButton` (`Icons.more_horiz_rounded`, tooltip
   "Opciones de la clase") que abre una hoja (`showUiSheet`) con "Eliminar clase".
   Eliminar pide confirmación con `showUiConfirm(destructive: true)`: título
   "¿Eliminar esta clase?", mensaje "Se borran sus estudiantes y sus sesiones. No se puede deshacer."
4. **Sin clases:** `UiEmptyState(icon: Icons.school_outlined, title: 'Aún no tienes clases',
   message: 'Crea tu primera clase para empezar a tomar asistencia.', actionLabel: 'Crear mi primera clase')`.
5. **Abajo** (`UiPage.bottom`): `UiButton(label: 'Nueva clase', icon: Icons.add_rounded, variant: outline)`.
   Con la lista vacía no se muestra (ya está el botón del estado vacío).
6. **Crear clase:** hoja inferior (`showUiSheet`) con título "Nueva clase" y los campos
   "Nombre de la clase" (ej. Bases de Datos II), "Código" (ej. SIST-401), "Grupo" (ej. 01)
   y "Semestre" (ej. 2026-2). **Quita** el campo "ID Google Sheets" (guarda `null`).
   Botón "Crear clase". Validación en palabras normales ("Escribe el nombre de la clase").
   Al crear: `showUiSnack(context, 'Clase creada.')`.
7. **Cargando:** indicador centrado. **Error al cargar:** `UiBanner(tone: error)` con
   "No se pudieron cargar tus clases." y la acción "Volver a intentar".

No incluyas la tarjeta "Sesión en curso" del mockup: se agrega después.

## Criterios de aceptación (además de los comunes)

- [ ] `test/ui/docente_inicio_test.dart`: con base de datos en memoria, (a) vacía muestra
      "Aún no tienes clases"; (b) con una clase insertada muestra su nombre y "Tus clases";
      ambos casos en claro y oscuro, 360 × 640, letra al 130 %, sin excepciones.
- [ ] `find.byType(CoursesDashboardScreen)` sigue funcionando (no cambies el nombre de la clase).
