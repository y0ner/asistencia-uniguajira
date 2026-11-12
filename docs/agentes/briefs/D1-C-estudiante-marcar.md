# Brief D1-C · Estudiante · Marcar asistencia (PIN → Acercar → ¡Presente!)

- **Rama:** `feat/ui-estudiante-marcar` · **Worktree:** `../worktrees/feat-ui-estudiante-marcar`
- **Lee primero:** `AGENTS.md`, `docs/agentes/briefs/D1-comun.md`, `docs/diseno/SISTEMA.md`.
- **Mockup:** `docs/diseno/mockups/B-Est-Marcar.html` (tiene los tres pasos).
- **Objetivo:** tres pasos claros y numerados para que el estudiante quede registrado.

## Archivos permitidos

- `lib/features/student/student_live_beacon_screen.dart`
- `test/ui/estudiante_marcar_test.dart` (**nuevo**)

## Qué se conserva (lógica)

Constructor completo, `StudentBeaconPhase`, `_startBroadcasting`, `_startTicker`,
`_updateAdvertisingPacket`, `_handleIncomingPacket`, `_onConfirmed`,
`_cancelBroadcasting`, la verificación de permisos y Bluetooth, el *wakelock* y
la suscripción a problemas de Bluetooth.

## Qué desaparece

"Sello Criptográfico Oficial", el botón "Copiar", cualquier huella, token o
dato técnico, y el teclado del sistema para el PIN.

## Cómo debe quedar

`UiPage` con `UiTopBar(title: nombre de la clase, onBack: …, below: UiStepBar(current: n, total: 3),
trailing: texto 'Paso n de 3' en UiText.label y color muted)`.

### Paso 1 · PIN

- `UiPageHeading(title: 'Escribe el PIN que dictó tu profesor')`.
- `UiPinEntry(value: lo escrito, hasError: …)` con margen lateral `UiSpace.page`.
- `UiPinKeypad` (margen lateral 28). Máximo 2 dígitos; borrar quita el último.
- Abajo: `UiButton(label: 'Continuar')`, habilitado con 2 dígitos. Si el PIN es menor
  que 10: `hasError` y el texto "El PIN tiene dos dígitos, entre 10 y 99."
- Si falta un permiso o el Bluetooth está apagado al continuar: misma vista de aviso que
  hoy, con los textos "El Bluetooth está apagado" / "Falta un permiso" y los botones
  "Encender Bluetooth", "Abrir ajustes", "Volver a intentar".

### Paso 2 · Acercar

- `UiPageHeading(title: 'Acerca tu celular al del profesor')`.
- `UiCard(tone: UiTone.tint, radius: UiRadius.xxl)` con:
  - arriba, un `Wrap` (no `Row`) con `UiPill(label: 'PIN 47', background: surface, foreground: ink)`
    y `UiPill(label: 'Buscando al profesor', dot: true, tone: UiTone.primary)`;
  - `UiTwoPhones(signal: 0–3, searching: true)`. Calcula `signal` con la intensidad de la
    última señal recibida del profesor, si la pantalla ya la tiene; si no, usa 1;
  - una línea: "Señal débil: acércate más" / "Señal media: acércate un poco más" /
    "Señal fuerte: ya casi", y el tiempo transcurrido con `UiFormat.elapsed`.
- Texto: "Deja esta pantalla abierta. Te avisamos apenas quedes registrado."
- Si pasan 45 s sin confirmación: `UiBanner(tone: warning, message: 'Aún no te encuentra.
  Revisa que el PIN sea el correcto y acércate al celular del profesor.')`.
- Problemas de Bluetooth: `UiBanner` con su mensaje.
- Abajo: `UiButton(label: 'Cambiar PIN', variant: outline)` (cancela y vuelve al paso 1).

### Paso 3 · ¡Presente!

- `UiHeroCard(motifSize: 220)` con un círculo `onPrimary` de 64 con `Icons.check_rounded`
  en `primary`, "Asistencia registrada" (`UiText.bodyStrong`) y "¡Presente!"
  (`UiText.display` dentro de `FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft)`).
- `UiListGroup` con `UiInfoRow`: "Clase" → nombre; "Fecha y hora" → `UiFormat.shortDateTime`;
  "Confirmó" → "El celular del profesor".
- Texto: "Ya puedes guardar el celular."
- Al entrar a este paso: `HapticFeedback.mediumImpact()`.
- Abajo: `UiButton(label: 'Listo')` que vuelve a la pantalla anterior.

## Criterios de aceptación (además de los comunes)

- [ ] `grep -n "Sello\|Copiar\|TextField" <archivo>` no devuelve nada.
- [ ] `test/ui/estudiante_marcar_test.dart` con servicios falsos: (a) el paso 1 muestra el
      título y "Continuar" deshabilitado; al tocar 4 y 7 se habilita; (b) con "0" y "5"
      muestra "El PIN tiene dos dígitos, entre 10 y 99."; claro y oscuro, 360 × 640,
      letra al 130 %, sin excepciones.
