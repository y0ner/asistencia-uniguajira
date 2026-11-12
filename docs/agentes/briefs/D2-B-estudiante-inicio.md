# Brief D2-B · Estudiante · Inicio y "Unirme a una clase"

- **Rama:** `feat/ui-estudiante-inicio` · **Worktree:** `../worktrees/feat-ui-estudiante-inicio`
- **Lee primero:** `AGENTS.md`, `docs/agentes/briefs/D1-comun.md`, `docs/diseno/SISTEMA.md`.
- **Mockup:** `docs/diseno/mockups/B-Est-Inicio.html`.
- **Ejemplo ya migrado:** `lib/features/teacher/courses_dashboard_screen.dart`.

## Archivos permitidos

- `lib/features/student/student_courses_screen.dart`
- `lib/features/student/student_qr_enrollment_screen.dart`
- `test/ui/estudiante_inicio_test.dart` (**nuevo**)

## Qué se conserva (lógica)

Constructores, `_loadEnrollments`, `_openQrScanner`, `_openLiveBeaconScreen`,
quitar una clase, y en la pantalla del QR: cámara, linterna, cambiar de cámara,
`_handleBarcodeDetected`, pegar el código y `_processEnrollmentPayload`.
Borra `StudentBleAttendancePreviewDialog` si queda sin uso.

## Inicio

`UiPage`:

1. `UiBrandHeader` con `UiRoundIconButton(Icons.tune_rounded, tooltip: 'Ajustes y diagnóstico')`
   que abre el diagnóstico actual.
2. `UiPageHeading(overline: 'Hola, <primer nombre>' si la pantalla lo tiene; si no, la fecha con
   UiFormat.longDate, title: '¿A qué clase llegaste?')`.
3. Una `UiCard` (radio 22) por clase: `UiAvatar(square)`, nombre (`UiText.title`), debajo el
   código y el grupo; un `UiRoundIconButton(Icons.more_horiz_rounded, tooltip: 'Opciones de la clase')`
   que abre una hoja con "Salir de esta clase" (confirmación con `showUiConfirm(destructive: true)`:
   "¿Salir de esta clase?", "Para volver tendrás que pedirle el código a tu profesor.").
   Debajo, `UiButton(label: 'Marcar asistencia', compact: true)`: `primary` en la primera
   tarjeta y `tonal` en las demás.
4. Sin clases: `UiEmptyState(icon: Icons.qr_code_scanner_rounded, title: 'Aún no estás en ninguna clase',
   message: 'Pídele a tu profesor el código QR de la clase y únete.', actionLabel: 'Unirme a una clase')`.
5. Abajo: `UiButton(label: 'Unirme a una clase', icon: Icons.qr_code_scanner_rounded, variant: outline)`
   (no se muestra con la lista vacía).

## Unirme a una clase

`UiPage` **sin pestañas**:

1. `UiTopBar(title: 'Unirme a una clase', onBack)`.
2. La cámara en un recuadro con esquinas `UiRadius.xxl` y un marco guía; debajo
   "Apunta al código QR que te muestra tu profesor." y dos `UiRoundIconButton`
   (linterna y cambiar de cámara).
3. Si la cámara falla o no hay permiso: `UiBanner(tone: warning)` que lo explica, con la acción que ya existe.
4. Abajo: `UiButton(label: 'Pegar el código', variant: outline)` → hoja con un campo
   "Código de la clase", "Pegar" y "Unirme". (Es el pegado manual de hoy, sin la palabra JSON.)
5. Al unirse: diálogo o pantalla con `UiHeroCard`: "¡Listo!", "Ya estás en <clase>" y
   `UiButton(label: 'Ir a mis clases', variant: onHero)`.
6. Código inválido: `UiBanner(tone: error, message: 'Ese código no es de una clase. Pídele a tu profesor que te lo muestre de nuevo.')`.

## Criterios de aceptación (además de los comunes)

- [ ] `grep -n "TabBar\|TabController" <tus archivos>` no devuelve nada.
- [ ] `test/ui/estudiante_inicio_test.dart`: sin clases muestra "Aún no estás en ninguna clase"; con una
      clase muestra su nombre y "Marcar asistencia". Claro y oscuro, 360 × 640, letra al 130 %, sin excepciones.
