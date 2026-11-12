# Brief D2-C · Docente · Reportes y sesión firmada

- **Rama:** `feat/ui-docente-reportes` · **Worktree:** `../worktrees/feat-ui-docente-reportes`
- **Lee primero:** `AGENTS.md`, `docs/agentes/briefs/D1-comun.md`, `docs/diseno/SISTEMA.md`.
- **Ejemplos ya migrados:** `lib/features/teacher/live_attendance_session_screen.dart`.

## Archivos permitidos

- `lib/features/teacher/course_reports_screen.dart`
- `lib/features/teacher/signed_acta_dialog.dart`
- `test/ui/docente_reportes_test.dart` (**nuevo**)

## Qué se conserva (lógica)

Constructor, `_loadReportData`, `_resolveExportDirectory`, `_checkLatestExportedFile`,
`_exportOfficialExcelWorkbook`, `_shareExportedFile` y el método estático
`CourseReportsScreen.showExportSuccessDialog` **con la misma firma y los botones
"Compartir" y "Cerrar"** (lo usa `test/report_share_service_test.dart`).
`SignedActaDialog.show` y `showFromJson` conservan su firma.

## Qué desaparece de la pantalla

- La pestaña de sincronización con la nube y todo su contenido (el servicio
  `CloudSyncService` no se toca; solo deja de mostrarse).
- El historial de sesiones (ya vive en la pantalla de la clase) y el botón de reanudar sesión.
- Huellas, firmas HMAC, mapas de bits, PIN e índices en la vista principal.

## Reportes

`UiPage` **sin pestañas**:

1. `UiTopBar(title: 'Reportes', subtitle: nombre de la clase, onBack)`.
2. Tres `UiStatTile`: "sesiones", "asistencia" (porcentaje promedio) y "en riesgo"
   (con `tone: UiTone.absent` si es mayor que cero).
3. `UiFilterPills`: "Todos N", "En alerta N", "En riesgo N" (los mismos tres estados que
   ya calcula la pantalla: normal, alerta y pérdida).
4. Lista (`ListView.builder` en tarjeta con separadores) de `UiPersonRow`:
   subtítulo "Fue a 10 de 12 · 2 faltas", y a la derecha una `UiPill` con el porcentaje:
   tono `tint` (bien), `manual` (en alerta) o `absent` (en riesgo).
5. Sin sesiones cerradas: `UiEmptyState(icon: Icons.bar_chart_rounded, title: 'Aún no hay datos',
   message: 'Cuando cierres tu primera sesión verás aquí el resumen de la clase.')`.
6. Abajo: `UiButton(label: 'Enviar Excel', icon: Icons.ios_share_rounded)` que exporta y abre
   el diálogo de éxito. Si ya hay un archivo exportado, encima va
   `UiButton(label: 'Compartir el último Excel', variant: tonal, compact: true)`.
7. Diálogo de éxito (`showExportSuccessDialog`): título "Excel listo", el nombre del archivo
   y su tamaño, botones "Compartir" (principal) y "Cerrar". Sin ruta ni huella a la vista.
8. Errores: `showUiSnack` con "No se pudo crear el Excel. Inténtalo de nuevo."

## Sesión firmada (`signed_acta_dialog.dart`)

Diálogo de pantalla completa o hoja alta:

1. Título "Sesión firmada" y la fecha con `UiFormat.longDate` y la hora.
2. Tres `UiStatTile`: "llegaron", "a mano" y "faltaron".
3. Lista de estudiantes con `UiPersonRow` y `UiStatusChip` (`present`, `manual`, `absent`).
4. Al final, un `ExpansionTile` cerrado "Detalles de la firma" con la firma y un botón
   "Copiar". Si la firma no es válida: `UiBanner(tone: error, message: 'La firma de esta sesión no coincide. Puede haber sido modificada.')`.
5. Botón "Cerrar".

## Criterios de aceptación (además de los comunes)

- [ ] `grep -n "TabBar\|TabController\|_handleInstitutionalSync\|_buildInstitutionalSyncTab" <archivo>` no devuelve nada.
- [ ] `test/report_share_service_test.dart` sigue pasando (puedes correr ese archivo además del tuyo).
- [ ] `test/ui/docente_reportes_test.dart`: clase sin sesiones (muestra "Aún no hay datos") y el diálogo
      de éxito ("Excel listo", "Compartir", "Cerrar"). Claro y oscuro, 360 × 640, letra al 130 %, sin excepciones.
