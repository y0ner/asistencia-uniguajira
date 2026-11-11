# Brief O1-A · Bluetooth confiable en celulares reales

- **Rama:** `fix/ble-runtime` · **Worktree:** `../worktrees/fix-ble-runtime`
- **Lee primero:** `AGENTS.md` (reglas obligatorias).
- **Objetivo:** que el anuncio y el escaneo Bluetooth funcionen de forma sostenida en 2 celulares Android reales durante una clase completa, y que cualquier fallo se vea en pantalla.

## Contexto (por qué falla hoy)

1. `BleAttendanceService.startAdvertisingPacket` llama a `_peripheral.start(...)` **sin detener el anuncio anterior**. El docente reemite el eco cada `AppConstants.teacherEchoIntervalSeconds` (= 1 s) y el estudiante cada cambio de *tick* (30 s). En Android, cada `start()` registra un anunciante nuevo; a los pocos ciclos el sistema responde `ADVERTISE_FAILED_TOO_MANY_ADVERTISERS` y el mapa de bits deja de actualizarse.
2. Los errores se ocultan: `student_live_beacon_screen.dart` tiene `catch (_) { // Ignorar … }` en `_updateAdvertisingPacket` y varios `catch (_) {}`.
3. Si la pantalla se apaga, Android pausa el escaneo sin filtro: hay que mantenerla encendida durante la sesión.
4. Los permisos de Bluetooth (`bluetoothScan`, `bluetoothAdvertise`, `bluetoothConnect`; y `locationWhenInUse` solo en Android ≤ 11) hoy solo se piden en el diálogo de diagnóstico de `main.dart`.
5. Las pantallas en vivo tienen botones "Simular…" que no deben existir en producción.

API del plugin, para consultarla (solo lectura): `~/.pub-cache/hosted/pub.dev/flutter_ble_peripheral-3.2.0/` y `~/.pub-cache/hosted/pub.dev/flutter_blue_plus-1.34.5/`.

## Archivos permitidos

- `lib/data/services/ble_attendance_service.dart`
- `lib/data/services/attendance_session_controller.dart` (solo la parte de BLE: `_publishTeacherEcho`, `_scheduleEchoTimer`, `_tryStartScan`, `_stopBleRuntime` y la exposición de errores)
- `lib/data/services/ble_permission_service.dart` (**nuevo**)
- `lib/features/teacher/live_attendance_session_screen.dart`
- `lib/features/student/student_live_beacon_screen.dart`
- `test/ble_attendance_service_test.dart`, `test/attendance_session_controller_test.dart`, `test/ble_permission_service_test.dart` (**nuevo**)

## Qué hacer

1. **Anuncio sin fugas.** En `BleAttendanceService`, serializa las llamadas (una cola o un `Future` encadenado) y, si ya hay un anuncio activo, **detenlo y espera** antes de iniciar el siguiente. Verifica en la API del plugin si `start()` informa el resultado (estado o `isAdvertising`) y úsalo para confirmar que el anuncio quedó activo.
2. **Reemitir solo si cambia algo.** Si el paquete de 16 bytes es idéntico al que ya se está anunciando, no reinicies el anuncio. El eco docente solo cambia cuando cambia el mapa de bits o la rotación; con esto el reinicio pasa de 1 por segundo a 1 por cambio real.
3. **Errores visibles.** Agrega al servicio un `Stream<BleRuntimeIssue>` (o equivalente), con un tipo y un mensaje en español, para fallos de anuncio, de escaneo o de adaptador apagado. El controlador y las dos pantallas en vivo lo muestran en un banner. Elimina todos los `catch (_) {}` de las dos pantallas: o se muestra el error o se registra con un motivo explícito.
4. **Permisos en el flujo normal.** Crea `BlePermissionService` con:
   - `Future<BlePermissionResult> ensureReady()`: pide los permisos según la versión de Android (12 o superior: scan, advertise y connect; 11 o inferior: ubicación) y verifica que el adaptador Bluetooth esté encendido (`FlutterBluePlus.adapterState`; en Android ofrece `FlutterBluePlus.turnOn()`).
   - Devuelve qué falta y si el permiso quedó denegado de forma permanente (para ofrecer "Abrir ajustes" con `openAppSettings()`).
   - Debe poder probarse sin hardware: inyecta las dependencias (funciones o interfaces) en el constructor.

   Llámalo **antes** de iniciar la sesión del docente y antes de empezar a emitir el estudiante. Si falta algo, muestra qué falta y un botón para resolverlo; no inicies el BLE.
5. **Pantalla encendida.** Con `wakelock_plus` (ya está en `pubspec.yaml`): `WakelockPlus.enable()` al entrar a cada pantalla en vivo y `disable()` al salir o al cerrar o confirmar la sesión.
6. **Quitar simulaciones de producción.** Elimina de las dos pantallas los botones "Simular…" y los textos "Usa el botón de simulación…". `injectSimulatedPacket` se queda en el servicio solo para las pruebas.

## Criterios de aceptación

- [ ] Una prueba demuestra que 50 llamadas seguidas a `startAdvertisingPacket` con paquetes distintos producen, en el *peripheral* falso, el patrón exacto `stop → start` sin dos `start` seguidos.
- [ ] Una prueba demuestra que reanunciar el mismo paquete no llama a `start()` otra vez.
- [ ] Una prueba demuestra que un fallo de `start()` llega al `Stream` de problemas con un mensaje en español.
- [ ] Hay pruebas de `BlePermissionService` para: todo concedido, uno denegado, denegado de forma permanente y adaptador apagado.
- [ ] `grep -rn "Simular" lib/features` no devuelve nada.
- [ ] `grep -n "catch (_) {}" lib/features/teacher/live_attendance_session_screen.dart lib/features/student/student_live_beacon_screen.dart` no devuelve nada.
- [ ] `flutter analyze --no-pub` sin problemas.

## Qué se probará en los 2 celulares (lo hace el humano)

Sesión docente de 10 minutos con la pantalla bloqueada a mano a los 5 minutos: el estudiante debe quedar confirmado antes y después. Con el Bluetooth apagado, la app debe pedir encenderlo.
