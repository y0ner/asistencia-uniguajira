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
