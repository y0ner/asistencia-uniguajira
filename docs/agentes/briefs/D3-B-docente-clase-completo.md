# Brief D3-B · Docente · Clase igual a la guía

- **Rama:** `feat/ui-clase-completo` · **Worktree:** `../worktrees/feat-ui-clase-completo`
- **Lee primero:** `AGENTS.md`, `docs/agentes/briefs/D1-comun.md`, `docs/diseno/SISTEMA.md`.
- **Referencia exacta (imagen):** `docs/diseno/referencias/docente-clase.png`. Así debe quedar.
- **Datos:** `CourseOverviewService.load(courseId)` en `lib/data/services/course_overview_service.dart`.
  No calcules porcentajes ni conteos en la pantalla.

## Archivos permitidos

- `lib/features/teacher/course_detail_screen.dart`
- `lib/features/teacher/course_reports_screen.dart` (**solo** el parámetro nuevo del punto 5)
- `test/ui/docente_clase_test.dart` (puedes editarla: es la prueba de esta pantalla)

## Qué cambia respecto a hoy

1. **Barra:** `UiTopBar` con `trailing: UiRoundIconButton(Icons.more_horiz_rounded, tooltip: 'Opciones de la clase')`
   que abre `showUiSheet` con dos filas `UiNavRow`: "Agregar estudiantes" (abre el modal que ya existe)
   y "Eliminar clase" (texto en `c.absentText`). Eliminar confirma con
   `showUiConfirm(destructive: true, title: '¿Eliminar esta clase?', message: 'Se borran sus estudiantes y sus sesiones. No se puede deshacer.', confirmLabel: 'Eliminar')`,
   llama a `AppDatabase.deleteCourse` y cierra la pantalla devolviendo `true`.
2. **Tarjeta "Tomar asistencia"** como hoy, con subtítulo "32 estudiantes" (`UiFormat.count`).
   No inventes "con celular vinculado": ese dato no existe en el celular del docente.
3. **Tres fichas** (`UiStatTile`) en fila: `closedSessionCount` "sesiones"; asistencia
   ("91 %", o "—" si `attendancePercent` es nulo) "asistencia"; `atRiskCount` "en riesgo"
   con `tone: UiTone.absent` solo si es mayor que cero. La fila entera es tocable y abre Reportes
   (`Semantics(button: true, label: 'Ver reportes')`).
4. **Últimas sesiones** (`UiSectionTitle`) en `UiListGroup` con una fila por `recentSessions`:
   a la izquierda `UiFormat.longDate(fecha)` en `UiText.bodyStrong`; a la derecha "29 de 32"
   (`UiText.label`, muted) y una `UiProgressBar(value: ratio, height: 6)` de 52 de ancho.
   La sesión abierta muestra `UiPill(label: 'En vivo', dot: true)` en lugar de la barra y al tocarla
   vuelve a la sesión; las cerradas abren la sesión firmada como hoy.
   Sin sesiones: "Aún no has tomado asistencia en esta clase."
5. **Abajo:** dos `UiButton(variant: tonal)` con íconos: "Estudiantes" (`Icons.person_outline_rounded`)
   y "Enviar Excel" (`Icons.ios_share_rounded`). "Enviar Excel" abre `CourseReportsScreen` con un
   parámetro nuevo `exportOnOpen: true` que, al terminar de cargar, llama una vez a
   `_exportOfficialExcelWorkbook()`. Si con letra al 130 % los dos botones no caben en una fila,
   ponlos uno debajo del otro (usa `LayoutBuilder` o `Wrap`), nunca cortes el texto.
6. Recargar al volver de la sesión, de Reportes y de Estudiantes.

## Criterios de aceptación (además de los comunes)

- [ ] Prueba con base en memoria: clase con 2 estudiantes, una sesión cerrada (1 llegó) y una abierta:
      muestra "1 de 2", "En vivo", la ficha "en riesgo" y "Enviar Excel"; las opciones muestran
      "Eliminar clase" y la confirmación. Claro y oscuro, 360 × 640, letra al 130 %, sin excepciones.
- [ ] `test/report_share_service_test.dart` sigue pasando (puedes correrlo además de tu prueba).
