# Plan de trabajo con agentes

Cada tarea tiene un brief en `briefs/`. El flujo y las reglas están en `../../AGENTS.md`.

## Oleada 1 · Dejar la app lista para la primera prueba con 2 celulares

| Brief | Rama | Objetivo |
|---|---|---|
| [O1-A](briefs/O1-A-ble-runtime.md) | `fix/ble-runtime` | Anuncio BLE sin fugas, errores visibles, permisos en el flujo normal, pantalla encendida, sin botones "Simular" |
| [O1-B](briefs/O1-B-flavors.md) | `feat/flavors` | Dos apps (Docente y Estudiante) desde el mismo código |
| [O1-C](briefs/O1-C-compartir-excel.md) | `feat/compartir-excel` | Compartir o abrir el Excel desde el celular del docente |

**Orden de merge:** O1-A → O1-C → O1-B (O1-B mueve `main.dart` y es la que más archivos toca).

**Primera prueba con 2 celulares:** al terminar la Oleada 1, con la inscripción por QR individual que ya existe.

## Oleada 2 · Después de la prueba

- **Inscripción con un solo QR por curso + código estudiantil** y credencial amarrada al teléfono. Cambia el protocolo de inscripción, así que primero se escribe su especificación; no se hace en paralelo con O1-A porque ambos tocan el Bluetooth.
- **Calibración de los 20–30 cm** con las mediciones de RSSI tomadas en los celulares reales (hoy el umbral es −75 dBm, que equivale a uno o dos metros).
- **Respaldo y restauración reales en Google Drive** (requiere el proyecto de Google Cloud y la huella SHA-1 de cada app).

## Oleada D · Rediseño (versión B)

Diseño aprobado el 11 de noviembre de 2026. Guía: `docs/diseno/SISTEMA.md`.
Reglas comunes: `docs/agentes/briefs/D1-comun.md`.

| Brief | Pantalla | Archivo |
|---|---|---|
| D0 (agente jefe) | Base: tokens, tema, componentes, letra y escudo | `lib/ui/**` |
| D1-A | Docente · Inicio | `courses_dashboard_screen.dart` |
| D1-B | Docente · Sesión en vivo | `live_attendance_session_screen.dart` |
| D1-C | Estudiante · Marcar asistencia | `student_live_beacon_screen.dart` |
| D2-A | Docente · Clase y estudiantes | `course_detail_screen.dart`, `roster_import_modal.dart` |
| D2-B | Estudiante · Inicio y unirse | `student_courses_screen.dart`, `student_qr_enrollment_screen.dart` |
| D2-C | Docente · Reportes y sesión firmada | `course_reports_screen.dart`, `signed_acta_dialog.dart` |

Las pantallas no comparten archivos: cada oleada corre en paralelo. Al terminar
la D2 se borra `lib/theme` y las extensiones heredadas de `UiTheme`.
