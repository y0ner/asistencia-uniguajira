# Brief D3-A · Docente · Inicio igual a la guía

- **Rama:** `feat/ui-inicio-completo` · **Worktree:** `../worktrees/feat-ui-inicio-completo`
- **Lee primero:** `AGENTS.md`, `docs/agentes/briefs/D1-comun.md`, `docs/diseno/SISTEMA.md`.
- **Referencia exacta (imagen):** `docs/diseno/referencias/docente-inicio.png`. Así debe quedar.
- **Datos:** `lib/data/services/course_overview_service.dart` (`CourseOverviewService.loadAll()`
  devuelve un `CourseOverview` por clase). No calcules porcentajes ni conteos en la pantalla.

## Archivos permitidos

- `lib/features/teacher/courses_dashboard_screen.dart`
- `test/ui/docente_inicio_test.dart` (puedes editarla: es la prueba de esta pantalla)

## Qué cambia respecto a hoy

1. **Tarjeta "Sesión en curso"** (`UiHeroCard`) entre el saludo y "Tus clases", **solo si alguna
   clase tiene `openSession`** (si hay varias, la más reciente):
   - `UiPill(label: 'Sesión en curso', dot: true, background: c.veil, foreground: c.onPrimary)`;
   - nombre de la clase (`UiText.h2`);
   - "19 de 32 estudiantes ya llegaron" (`openSession.presentCount` de `studentCount`;
     "1 estudiante ya llegó" en singular; con 0: "Aún no llega nadie");
   - `UiProgressBar(value: openSession.ratio, onHero: true, semanticLabel: …)`;
   - `UiButton(label: 'Volver a la sesión', variant: onHero, trailingIcon: Icons.arrow_forward_rounded, compact: true)`
     que abre `LiveAttendanceSessionScreen(course: …, database: …)` y al volver recarga.
2. **Tarjeta de cada clase:** avatar, nombre, "Grupo 01 · 32 estudiantes" y, **a la derecha**:
   - con `attendancePercent`: el número ("91 %", `UiText.title`) y debajo "asistencia" (`UiText.label`, muted);
   - sin estudiantes: `UiPill(label: 'Nueva', tone: UiTone.manual)` y el subtítulo "Grupo 01 · Falta agregar estudiantes";
   - con estudiantes pero sin sesiones cerradas: "Sin sesiones" en `UiText.label` muted.
   El nombre usa hasta 2 líneas. **Se quita el botón "…"** de la tarjeta: eliminar la clase pasa a la
   pantalla de la clase (lo hace otro brief). Borra `_showCourseOptionsSheet` y `_confirmDeleteCourse`
   si quedan sin uso.
3. Lo demás (encabezado con escudo, saludo, crear clase, estado vacío, error) queda igual.
4. Recargar (`loadAll`) al volver de la pantalla de una clase y de la sesión.

## Criterios de aceptación (además de los comunes)

- [ ] Prueba con base en memoria: (a) una clase con sesión abierta y 1 de 2 llegados muestra
      "Sesión en curso", "1 de 2 estudiantes ya llegaron" y "Volver a la sesión"; (b) una clase con una
      sesión cerrada muestra su porcentaje y "asistencia"; (c) sin sesiones abiertas no aparece
      "Sesión en curso". Claro y oscuro, 360 × 640, letra al 130 %, sin excepciones.
- [ ] `grep -n "Opciones de la clase" lib/features/teacher/courses_dashboard_screen.dart` no devuelve nada.
