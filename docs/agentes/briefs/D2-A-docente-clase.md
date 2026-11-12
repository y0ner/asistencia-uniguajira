# Brief D2-A · Docente · Clase y estudiantes

- **Rama:** `feat/ui-docente-clase` · **Worktree:** `../worktrees/feat-ui-docente-clase`
- **Lee primero:** `AGENTS.md`, `docs/agentes/briefs/D1-comun.md`, `docs/diseno/SISTEMA.md`.
- **Mockup:** `docs/diseno/mockups/B-Curso.html`.
- **Ejemplo ya migrado:** `lib/features/teacher/courses_dashboard_screen.dart`.

## Archivos permitidos

- `lib/features/teacher/course_detail_screen.dart`
- `lib/features/teacher/roster_import_modal.dart`
- `test/ui/docente_clase_test.dart` (**nuevo**)

## Qué se conserva (lógica)

Constructores, `_loadData`, `_openImportModal`, el QR de cada estudiante
(su contenido no cambia), `_onStartBleSession`, `_openReportsScreen`,
`_viewSessionActa`, y en el modal: pegar del portapapeles, elegir archivo,
agregar uno por uno y el resumen del resultado.

## Cómo debe quedar la pantalla de la clase

`UiPage` **sin pestañas**:

1. `UiTopBar(title: nombre, subtitle: 'SIST-401 · Grupo 01 · 2026-2', onBack)`.
2. `UiHeroCard(onTap)` con "Tomar asistencia" (`UiText.h2`) y debajo
   "32 estudiantes" (`UiFormat.count`); a la derecha un círculo `onPrimary` con
   `Icons.arrow_forward_rounded` en `primary`. Si hay una sesión abierta, el título
   es "Volver a la sesión". Si la clase no tiene estudiantes, en lugar de esta
   tarjeta va `UiBanner(tone: info, message: 'Agrega a tus estudiantes para poder tomar asistencia.',
   actionLabel: 'Agregar estudiantes')`.
3. Tres `UiStatTile` en fila: sesiones, asistencia (porcentaje, si la pantalla ya
   tiene el dato; si no, omite esa ficha) y estudiantes.
4. `UiSectionTitle('Últimas sesiones')` y un `UiListGroup` de `UiNavRow`:
   título `UiFormat.longDate(fecha)`, subtítulo "Llegaron 29 de 32" (o "Sesión abierta"),
   al tocar abre la sesión firmada. Sin sesiones: texto "Aún no has tomado asistencia en esta clase."
5. Abajo (`UiPage.bottom`): dos `UiButton(variant: tonal)` en fila: "Estudiantes"
   (`Icons.person_outline_rounded`) y "Reportes" (`Icons.bar_chart_rounded`).

## Estudiantes (pantalla aparte dentro del mismo archivo)

"Estudiantes" abre una pantalla nueva (widget privado, `Navigator.push`):

- `UiTopBar(title: 'Estudiantes', subtitle: nombre de la clase, onBack)`.
- Lista (`ListView.builder`) de `UiPersonRow(name, subtitle: código o identificación)`
  con un `UiRoundIconButton(Icons.qr_code_rounded, tooltip: 'Código para unirse')` que
  muestra el QR de ese estudiante en un diálogo: título con el nombre, el QR sobre fondo
  blanco, y el texto "Pídele que abra Asistencia Estudiante, toque «Unirme a una clase» y
  apunte a este código." **No muestres** el contenido del código como texto.
- Vacío: `UiEmptyState(icon: Icons.group_add_outlined, title: 'Aún no hay estudiantes',
  message: 'Agrégalos pegando la lista, desde un archivo o uno por uno.', actionLabel: 'Agregar estudiantes')`.
- Abajo: `UiButton(label: 'Agregar estudiantes', icon: Icons.add_rounded)`.

## Agregar estudiantes (`roster_import_modal.dart`)

Misma función, tres maneras elegidas con `UiFilterPills`: "Pegar lista",
"Desde archivo" y "Uno por uno". Título "Agregar estudiantes". Explica cada una
en una frase ("Copia la lista desde Excel o el SMA y pégala aquí."). Botones
`UiButton`. El resumen final dice "Se agregaron N estudiantes" y, si hubo
filas con problema, cuántas y por qué, en palabras normales.

## Criterios de aceptación (además de los comunes)

- [ ] `grep -n "TabBar\|TabController" <tus archivos>` no devuelve nada.
- [ ] `test/ui/docente_clase_test.dart`: clase sin estudiantes (muestra el aviso) y clase con 2
      estudiantes (muestra "Tomar asistencia", "Estudiantes", "Reportes"); al tocar "Estudiantes"
      aparecen los dos nombres. Claro y oscuro, 360 × 640, letra al 130 %, sin excepciones.
