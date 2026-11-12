# Sistema de diseño · Asistencia Uniguajira (versión B)

Diseño aprobado por Yoner el 11 de noviembre de 2026. Reemplaza por completo el
diseño anterior (`lib/theme`, azul rey y dorado), que **no** correspondía a la
identidad de la universidad.

- **Cómo se ve:** `docs/diseno/muestrario-claro.png` y `muestrario-oscuro.png`.
- **Pantallas de referencia** (HTML; léelas como especificación de estructura,
  tamaños y textos): `docs/diseno/mockups/B-*.html`.
- **Código:** `lib/ui/` (se importa con `import '…/ui/ui.dart';`). Fechas, horas y saludos: `UiFormat` (`lib/ui/ui_format.dart`); no uses `DateFormat` para textos visibles.
- **Ejemplo de uso de cada componente:** `lib/ui/gallery/ui_gallery_screen.dart`.

## 1. Principios

1. **Amable y claro.** La usan profesores y estudiantes con prisa. Frases
   completas y cotidianas, tarjetas redondeadas, botones grandes.
2. **Una acción principal por pantalla**, abajo, al alcance del pulgar
   (`UiPage.bottom`). Lo demás es secundario.
3. **El color significa algo.** Sale del escudo de la universidad:
   | Color | Significado | Tokens |
   |---|---|---|
   | Turquesa | acción principal, presente, en vivo | `primary`, `tint`, `UiTone.tint/primary` |
   | Ocre | marcado a mano, algo que requiere atención | `UiTone.manual` |
   | Coral | falta, riesgo, error | `UiTone.absent` |
   El estado **nunca** se comunica solo con color: lleva ícono y palabra (`UiStatusChip`).
4. **Explicar con un dibujo** donde alguien se puede perder (`UiTwoPhones`, `UiEmptyState`).
5. **Claro y oscuro por igual.** La app sigue el modo del celular.

## 2. Cómo se le habla a la persona

Tuteo, frases cortas, sin tecnicismos. Mayúscula solo al inicio de la frase.

| No escribas | Escribe |
|---|---|
| Curso, cursos enrolados | Clase, tus clases |
| Enrolar, enrolamiento | Unirme a una clase |
| Roster | Estudiantes, lista de estudiantes |
| BLE, sesión BLE, baliza, emisión | Bluetooth (solo si hace falta), sesión |
| Token, JSON, hash, HMAC, sello criptográfico, payload | (no se muestra) |
| Acta firmada criptográficamente | Sesión cerrada y firmada |
| Pendiente | Aún no llega |
| Ausente | Falta |
| Manual, registro manual | A mano |
| ERROR: …, Exception… | Qué pasó y qué hacer: "No se pudo guardar. Inténtalo de nuevo." |

Fechas y horas en palabras: "Miércoles 11 de noviembre", "8:41 a. m.".
Nunca prometas "100 % seguro" ni "imposible de suplantar".

## 3. Tokens (`lib/ui/tokens`)

- **Colores:** `UiColors.of(context)` → `background`, `surface`, `ink`, `muted`,
  `line`, `primary`, `onPrimary`, `primaryText`, `tint`, `tintText`, `veil`,
  `manualBg/Text`, `absentBg/Text`, `presentDot`, `manualDot`, `absentDot`.
  Para pares fondo/texto: `c.tone(UiTone.x)`.
- **Texto:** `UiText.display`, `h1`, `h2`, `title`, `body`, `bodyStrong`,
  `label`, `caption`, `button`, `numberXl`, `numberLg`, `numberMd`. No llevan
  color: usa `.copyWith(color: c.ink)` o `c.muted`. No cambies `fontSize`.
- **Espacios:** `UiSpace.xs(4) sm(8) md(12) lg(16) xl(20) xxl(24) xxxl(32)`;
  margen lateral de pantalla: `UiSpace.page`.
- **Radios:** `UiRadius.sm(12) md(16) lg(20) xl(24) xxl(28) pill`.
- **Tamaños:** `UiSize.touch(44)`, `button(56)`, `buttonCompact(48)`.
- **Movimiento:** `UiMotion.fast/base/slow` y `UiMotion.curve`. Respeta
  `MediaQuery.disableAnimationsOf(context)`.

## 4. Componentes (`lib/ui/components`)

| Componente | Para qué |
|---|---|
| `UiPage(header, body, bottom)` | Estructura de **toda** pantalla. |
| `UiBrandHeader(trailing)` | Encabezado con el escudo. Solo en las pantallas de inicio. |
| `UiTopBar(title, subtitle, onBack, close, trailing, below)` | Barra de las pantallas internas. |
| `UiPageHeading(overline, title)` | Saludo o pregunta grande. |
| `UiSectionTitle(text)` | Título de sección. |
| `UiButton(label, onPressed, variant, icon, trailingIcon, compact, expand, loading)` | Botones. Variantes: `primary`, `tonal`, `outline`, `onHero`. |
| `UiRoundIconButton(icon, tooltip, onPressed)` | Botón redondo de ícono. `tooltip` obligatorio. |
| `UiCard(child, onTap, tone, radius)` | Tarjeta base. |
| `UiHeroCard(child, onTap)` | Tarjeta turquesa con el motivo del escudo. **Una por pantalla.** |
| `UiStatusChip(status, solid)` | Estado de asistencia: `present`, `manual`, `absent`, `pending`. |
| `UiPill(label, dot, icon, tone)` | Etiqueta ("En vivo · 08:42", "Nueva", "PIN 47"). |
| `UiAvatar(name, tone, square)` | Iniciales. Círculo = persona; `square` = clase. |
| `UiHistoryDots(attended)` | Historial en puntos. |
| `UiProgressRing.count(count, total)` | Conteo de la sesión. |
| `UiProgressBar(value, semanticLabel, onHero)` | Barra de progreso. |
| `UiStepBar(current, total)` | Pasos de un flujo. |
| `UiPinDisplay(pin)` | PIN de la clase (docente). |
| `UiPinEntry(value)` + `UiPinKeypad(onDigit, onBackspace)` | Escribir el PIN (estudiante). |
| `UiListGroup(children)` | Agrupa filas con separadores. |
| `UiPersonRow(name, subtitle, avatarTone, trailing, highlighted)` | Fila de persona. |
| `UiNavRow(title, subtitle, leading, trailing, onTap)` | Fila que navega. |
| `UiInfoRow(label, value)` | Dato de un resumen. |
| `UiStatTile(value, label, tone)` | Cifra con nombre. |
| `UiFilterPills(options, selected, onSelected)` | Filtros. |
| `UiTwoPhones(signal, searching)` | Dibujo de los dos celulares. |
| `UiEmptyState(title, message, icon, actionLabel, onAction)` | Pantalla o lista vacía. |
| `UiBanner(message, title, tone, actionLabel, onAction)` | Aviso con acción. |
| `showUiConfirm(...)`, `showUiSheet(...)`, `showUiSnack(...)` | Confirmación, hoja inferior, mensaje breve. |

Los campos de texto (`TextField`), `AlertDialog` y `SnackBar` ya salen con el
estilo correcto desde el tema: úsalos sin decorarlos.

Si falta un componente, **no** lo inventes dentro de la pantalla con colores
sueltos: créalo como widget privado del archivo usando solo tokens, y repórtalo
al agente jefe para subirlo a `lib/ui`.

## 5. Reglas para construir una pantalla

1. Importa `ui.dart`. **Prohibido** importar `lib/theme/…` o usar `AppColors`,
   `AppSpacing`, `AppRadii`, `AppMotion` en una pantalla migrada.
2. Prohibido `Color(0x…)`, `Colors.*` (salvo `Colors.transparent`),
   `fontSize:` y `EdgeInsets`/`SizedBox` con números fuera de la escala.
3. Todo lo que se toca mide al menos 44 × 44.
4. La pantalla debe verse bien en claro y en oscuro, en un celular de
   360 × 640 y con la letra del sistema al 130 %: usa `Expanded`/`Flexible`,
   `maxLines` + `overflow`, y `Wrap` en vez de `Row` para pastillas.
5. Listas largas con `ListView.builder`.
6. Cada estado tiene su vista: cargando, vacío (`UiEmptyState`), error
   (`UiBanner` con acción) y contenido.
7. Íconos: `Icons.*_rounded` u `_outlined`. Sin emojis.
8. Los textos siguen la tabla de la sección 2.
9. **No se toca la lógica**: servicios, base de datos, controladores, Bluetooth
   y modelos (`lib/core`, `lib/data`) quedan igual. Solo cambia cómo se ve y
   cómo se organiza la pantalla.
