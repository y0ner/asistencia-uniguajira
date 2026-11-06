# Asistencia Multimodal Uniguajira (`asistencia_uniguajira`)

**Universidad de La Guajira** · Facultad de Ingeniería · Programa de Ingeniería de Sistemas  
**Proyecto de Grado:** Yoner De Jesus Isaza Vides (`0182120016`) y Álvaro Luis Garrido Medina (`0182110072`)  
**Asignatura:** Proyectos II · Docente: Miguel Humberto Romero Acuña · Directora: Lisseth Paola Castañeda Vega

---

## Arquitectura Multimodal (4 Motores en una sola aplicación Flutter)

1. **Opción 1 — Proximidad Criptográfica BLE + Eco de Confirmación por Mapa de Bits (8 Bytes):**
   - El estudiante emite un anuncio de **16 bytes** con etiqueta rotativa `HMAC-SHA256` cada 30 s.
   - El docente responde en un único paquete de **24 bytes** (`[Curso 4B][Tick 4B][Bitmap 8B][HMAC 8B]`) que cabe holgadamente en los 31 bytes del estándar BLE 4.2/5.0 sin conexiones GATT.
   - El teléfono del estudiante ve su bit encenderse en `1` y gira automáticamente a su **Sello Criptográfico Verde**.

2. **Opción 2 — Visión Artificial *On-Device* en 5 Segundos (*MediaPipe + MobileFaceNet 128D*):**
   - Diseñada para días de **parciales o exámenes** donde el estudiante tiene prohibido sacar el celular.
   - Compara vectores numéricos normalizados L2 de 128 dimensiones localmente ($\text{sim}(\vec{u}, \vec{v}) \ge 0.75$) sin subir fotografías a la nube.

3. **Opción 3 — Confinamiento Acústico por Ultrasonido (`18.8 kHz – 19.4 kHz`) Anti-Pasillo y Anti-WhatsApp:**
   - Modulación FSK inaudible decodificada mediante el **algoritmo de Goertzel**.
   - Rebota en las paredes del salón (0 % de falsos positivos de pasillo) y se autodestruye si alguien intenta reenviar el audio por nota de voz de WhatsApp (cuyo códec Opus corta frecuencias superiores a `16 kHz`).

4. **Opción 4 — Ingesta OCR Local Antiduplicados (Cero Contacto con el SMA) + Excel `.xlsx` y Google Workspace (`$0`):**
   - El docente carga 1 o varias capturas de pantalla de su lista y el motor local aplica **deduplicación en 2 niveles** (código exacto preservando ceros iniciales + similitud difusa *Jaro-Winkler* $\ge 0.92$).
   - Firma criptográfica del **Acta JSON** en el Keystore, generación del libro **Excel (`.xlsx`)** con las 4 hojas reglamentarias (`Resumen`, `Detalle`, `Sesiones`, `Metadatos`) y sincronización con **Google Sheets (`@uniguajira.edu.co`)**.

---

## Comandos de Ejecución y Verificación

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```
