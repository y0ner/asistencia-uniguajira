# Oleada 2 · Inscripción con un solo QR de clase

- **Estado:** propuesta para aprobación de Yoner (12 de noviembre de 2026).
- **Reemplaza:** el QR individual por estudiante (el docente mostraba un QR por persona).
- **No cambia:** la toma de asistencia (PIN → acercar → "¡Presente!"), ya probada con dos celulares reales.

## 1. Objetivo

Que toda una clase se inscriba en un par de minutos sin que el docente toque nada por estudiante, que el docente pueda incluir a quien no está en su lista, y que cada celular quede amarrado a **un** estudiante.

## 2. Cómo se vive

### Docente

1. En la clase toca **"Inscribir estudiantes"**. La pantalla muestra **un QR de la clase** (se puede proyectar) y el contador "Inscritos 18 de 32".
2. Deja la pantalla abierta. Los estudiantes de su lista entran **solos**.
3. Si llega alguien que **no está en la lista**, aparece en **"Por aprobar"**. El docente lo toca, le pregunta nombre y correo, los escribe y toca **"Agregar y aceptar"** (o **"Rechazar"**).
4. Si un código **ya tiene un celular vinculado**, aparece un aviso: "Ana Pérez ya tiene un celular vinculado. ¿Reemplazarlo por este?" → **Reemplazar** / **Rechazar**.
5. Al cerrar la pantalla termina la inscripción; las solicitudes sin resolver se descartan.

### Estudiante

1. **"Unirme a una clase"** → escanea el QR de la clase.
2. Escribe **su código estudiantil** y lo confirma ("¿Tu código es 0182120016?").
3. Ve "Buscando a tu profesor…" con el dibujo de los dos celulares. Debe estar **en el salón**: la respuesta llega por Bluetooth.
4. Resultado:
   - **"¡Listo! Ya estás en Bases de Datos II."**
   - "Tu profesor está revisando tu solicitud." (espera en esa pantalla)
   - "Tu profesor no aprobó la solicitud. Habla con él."
   - "La clase ya está completa (64 estudiantes)."
   - Tras 60 s sin respuesta: "No encontramos a tu profesor. Acércate y pídele que abra «Inscribir estudiantes»."

## 3. Reglas de decisión del celular del docente

| Llega una solicitud con… | Qué pasa |
|---|---|
| Código de la lista, sin celular vinculado | **Se acepta sola.** |
| Código de la lista, con otro celular vinculado | Va a **Conflictos**: el docente decide reemplazar o rechazar. |
| Código que no está en la lista | Va a **Por aprobar**: nunca se acepta sola. |
| Clase con 64 estudiantes activos | Se responde "clase completa". |
| Solicitud con firma inválida (no escaneó el QR de esta clase) | Se ignora en silencio. |
| El mismo celular repite su solicitud | Se responde lo mismo que antes (no duplica). |

## 4. Seguridad

**Amenaza que se cubre:** un compañero que quiere inscribirse o marcar por otro.

1. **Solo desde el salón.** Aunque el QR circule por WhatsApp, la solicitud y la respuesta viajan por Bluetooth de corto alcance.
2. **Cada celular genera su propia clave** (par X25519). El QR lleva la **clave pública del docente**; como el QR se ve directamente en su pantalla, es un canal auténtico. El estudiante envía su clave pública por Bluetooth y ambos calculan el mismo secreto (Diffie-Hellman) sin que viaje por el aire. Quien escuche el Bluetooth **no puede** calcular el secreto de otro estudiante.
3. **Un código, un celular.** El segundo intento con el mismo código no entra solo: el docente lo ve y decide.
4. **Lo que no está en la lista lo aprueba una persona**, que tiene al estudiante al frente.
5. **Rastro.** Cada estudiante guarda cómo entró (lista o "agregado en clase") y cuándo se vinculó su celular; sale en el Excel.

**Límite conocido:** quien llegue primero con el código de un compañero ausente queda vinculado hasta que el docente lo note (lo verá cuando el dueño real intente inscribirse: conflicto). Se mitiga con la aprobación visible y el aviso de conflicto. No se promete "imposible de suplantar".

## 5. Protocolo Bluetooth

Paquetes de 16 bytes en el Service UUID, igual que hoy. Byte 2 = tipo:

| Byte 2 | Paquete | Estado |
|---|---|---|
| `0x80 \| bitIndex` | Anuncio de asistencia del estudiante | existe |
| `0x00` | Eco del docente (mapa de 64 bits) | existe |
| `0xC0 \| fragmento` (0–3) | **Solicitud de inscripción** (estudiante) | nuevo |
| `0x40 \| estado` | **Respuesta de inscripción** (docente) | nuevo |

Los verificadores actuales deben **ignorar** los paquetes con el bit `0x40` encendido.

### 5.1 QR de la clase (versión 2)

```json
{"v":2,"courseId":"…","courseCode":"SIST-401","courseName":"Bases de Datos II",
 "sharedSecret":"<64 hex>","teacherKey":"<clave pública X25519, 64 hex>"}
```

El par de claves del docente se crea una vez por clase y se guarda en la base de datos.

### 5.2 Solicitud (estudiante → docente), 4 fragmentos

Mensaje de 44 bytes:

```
código (6)  = [cantidad de dígitos:1][número big-endian:5]     (códigos numéricos de hasta 12 dígitos)
clave pública del estudiante (32)
firma (6)   = HMAC-SHA256(sharedSecret, "ENR1" | reqId | código | clave)[0..6]
```

Cada fragmento: `[courseHash16:2][0xC0|i:1][reqId:2][11 bytes del mensaje]`.
El estudiante rota los 4 fragmentos (uno cada ~400 ms) hasta recibir respuesta o agotar 60 s. `reqId` es aleatorio por intento.

El docente arma el mensaje cuando tiene los 4 fragmentos del mismo `reqId` y verifica la firma.

### 5.3 Secreto del dispositivo

```
compartido   = X25519(privada propia, pública del otro)
deviceSecret = HKDF-SHA256(compartido, salt = sharedSecret, info = "asistencia/device/v1" | código)  → 32 bytes
```

Es el `personal_secret` que ya usa la asistencia: la toma de asistencia no cambia.

### 5.4 Respuesta (docente → estudiante), 1 paquete

```
[courseHash16:2][0x40|estado:1][reqId:2][bitIndex:1][HMAC-SHA256(deviceSecret, "ENR2"|bytes 0..5)[0..10]]
```

| Estado | Significado |
|---|---|
| 1 | Aceptado (`bitIndex` válido) |
| 2 | En revisión (por aprobar o conflicto) |
| 3 | Rechazado |
| 4 | Clase completa |

La firma con `deviceSecret` confirma que ambos calcularon el mismo secreto. El docente rota las respuestas pendientes (una cada ~600 ms) y deja de enviar la de un estudiante cuando lleva 3 s sin oír su solicitud (el estudiante deja de emitir al recibir un estado final: esa es la confirmación).

## 6. Datos (base de datos versión 4)

- `courses`: `enroll_private_key`, `enroll_public_key`.
- `students`:
  - `status`: `active` | `retired`.
  - `origin`: `roster` (lista) | `added_in_class` (agregado en clase).
  - `device_key_id` (huella de la clave del celular) y `device_bound_at`; nulos = sin celular vinculado.
  - `retired_at`.
  - `bit_index` pasa a ser nulo en los retirados (libera la casilla).
- Celular del estudiante: `student_enrollments` guarda su par de claves y el `deviceSecret`. `student_id` se calcula localmente (`courseId:código`).
- Los datos de prueba actuales se descartan (no hay piloto en curso).

Con esto el docente **sí sabe** cuántos tienen celular vinculado ("32 estudiantes · 28 con celular vinculado", como en la guía de diseño).

## 7. Eliminar o retirar a un estudiante

En **Estudiantes**, cada fila tiene un menú "…":

| Situación | Acción | Efecto |
|---|---|---|
| Sin asistencias registradas | **Eliminar** | Se borra por completo. |
| Con asistencias | **Retirar de la clase** | Sale de la lista y de las sesiones nuevas; sus asistencias pasadas quedan en el historial y en el Excel, marcadas "Retirado el …". No cuenta en porcentajes ni en "en riesgo". |
| Cualquiera con celular vinculado | **Desvincular celular** | Podrá inscribir otro celular. |

**Doble confirmación** para eliminar y retirar: (1) aviso con las consecuencias; (2) escribir el **primer nombre** del estudiante.

Los totales de las sesiones ya cerradas ("29 de 32") se toman de la sesión firmada, para que no cambien al retirar a alguien.

*Mejora posterior:* que el celular del retirado muestre "Ya no estás en esta clase" al intentar marcar.

## 8. Pantallas

| Pantalla | App | Cambio |
|---|---|---|
| Inscribir estudiantes | Docente | **Nueva.** QR de la clase, contador, "Por aprobar", "Conflictos", últimos inscritos. |
| Estudiantes | Docente | Estado del celular por fila ("Celular vinculado" / "Sin celular"), menú "…" (eliminar, retirar, desvincular). Se quita el QR por estudiante. |
| Clase | Docente | Subtítulo "32 estudiantes · 28 con celular vinculado". "Inscribir estudiantes" en el menú y en el aviso de clase vacía. |
| Unirme a una clase | Estudiante | Escanear → código → buscando → resultado. |
| Agregar estudiantes | Docente | Sin cambios (sigue siendo la forma de cargar la lista). |

## 9. Excel y reportes

- Hoja de estudiantes: columnas "Origen" (Lista / Agregado en clase), "Celular vinculado desde" y "Estado" (Activo / Retirado el …).
- Los retirados aparecen al final y no entran en promedios ni en "en riesgo".

## 10. Riesgos

| Riesgo | Mitigación |
|---|---|
| 30 celulares pidiendo inscripción a la vez | El docente responde en rotación; se probará con los celulares disponibles y se medirá el tiempo por estudiante. |
| Rotar anuncios cada 400–600 ms en algunos Android | Ya se serializa detener → iniciar; se medirá en la prueba 02 y se ajusta el intervalo. |
| Códigos con letras | Fuera de alcance: se valida que el código sea numérico (4 a 12 dígitos). |

## 11. Plan de trabajo

1. **Agente jefe (núcleo delicado):** criptografía (X25519, HKDF), códec de los paquetes nuevos, armado de fragmentos, migración a la versión 4, servicios de inscripción del docente y del estudiante, con pruebas unitarias y una simulación completa en memoria (dos servicios "hablándose" sin Bluetooth real).
2. **Agentes de Gemini (pantallas, en paralelo):** Inscribir estudiantes; Unirme a una clase; Estudiantes (estado, eliminar, retirar); Excel y reportes.
3. **Sección "Cómo funciona"** (diseño aprobado aparte).
4. **Prueba 02 con dos celulares:** inscribir desde la lista, inscribir a alguien fuera de la lista, conflicto por cambio de celular, eliminar, retirar, y asistencia completa después de inscribirse.
