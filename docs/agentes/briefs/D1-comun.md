# Reglas comunes de la Oleada D (rediseño de pantallas)

Aplican a todos los briefs `D1-*` y `D2-*`, además de `AGENTS.md`.

1. **Lee primero, completos:** `docs/diseno/SISTEMA.md`, el mockup HTML que cita
   tu brief (es la especificación de estructura y textos; no es código para
   copiar) y `lib/ui/gallery/ui_gallery_screen.dart` (cómo se usa cada componente).
2. **Solo cambia cómo se ve y cómo se organiza la pantalla.** Conserva la
   lógica: los métodos que llaman a servicios, base de datos, controladores y
   Bluetooth, sus `try/catch`, las suscripciones, los `dispose`, el *wakelock*
   y los parámetros del constructor. No cambies nada en `lib/core`, `lib/data`
   ni `lib/ui`.
3. **Reescribe `build` y los `_build…` con los componentes de `lib/ui`.** Borra
   los widgets y métodos de presentación que queden sin uso. No dejes
   importaciones de `lib/theme`.
4. **Textos:** sigue la tabla "Cómo se le habla a la persona" de `SISTEMA.md`.
   Fechas, horas y saludos con `UiFormat`.
5. **Debe aguantar** claro y oscuro, un celular de 360 × 640 y la letra del
   sistema al 130 % sin desbordes.
6. **Prueba nueva obligatoria** en `test/ui/<nombre>_test.dart` (el nombre lo da
   tu brief). Como mínimo: dibuja la pantalla en claro y en oscuro a 360 × 640
   con `textScaleFactor` 1.3 y verifica `tester.takeException() == null` y los
   textos clave. Carga la letra como lo hace `test/ui/ui_gallery_test.dart`
   (`_loadFigtree`) y usa `UiTheme.light()` / `UiTheme.dark()`. Para la base de
   datos en memoria mira `test/app_database_test.dart`; para servicios falsos
   de Bluetooth, `test/attendance_session_controller_test.dart` y
   `test/ble_permission_service_test.dart`.
7. **Comandos permitidos:** `flutter analyze --no-pub` y
   `flutter test test/ui/<tu_archivo>_test.dart` (solo ese archivo). Nada más.
8. **No toques pruebas existentes.** Si crees que tu cambio rompe alguna
   (porque busca un texto viejo), dilo en tu respuesta final con el nombre de
   la prueba y el texto; el agente jefe la ajusta.
9. Si algo del diseño no se puede lograr con los componentes de `lib/ui`, crea
   un widget privado en tu archivo usando solo tokens y repórtalo.

## Criterios comunes de aceptación

- [ ] `grep -n "theme/theme.dart\|AppColors\|AppSpacing\|AppRadii\|AppMotion" <tus archivos>` no devuelve nada.
- [ ] `grep -nP "Color\(0x|(?<![A-Za-z])Colors\.(?!transparent)|fontSize:" <tus archivos>` no devuelve nada. `UiColors.of(context)` es correcto: úsalo directo, sin alias ni extensiones para esquivar la búsqueda.
- [ ] `grep -niE "BLE|roster|enrol|token|hash|hmac|json|criptogr" <tus archivos>` solo aparece en nombres de código, nunca en textos visibles.
- [ ] `flutter analyze --no-pub` sin problemas.
- [ ] Tu prueba nueva pasa.
