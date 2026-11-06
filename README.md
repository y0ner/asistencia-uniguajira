# Asistencia Multimodal Uniguajira (`asistencia_uniguajira`)

**Universidad de La Guajira** · Facultad de Ingeniería · Programa de Ingeniería de Sistemas  
**Proyecto de Grado:** Yoner De Jesus Isaza Vides (`0182120016`) y Álvaro Luis Garrido Medina (`0182110072`)  
**Asignatura:** Proyectos II · Docente: Miguel Humberto Romero Acuña · Directora: Lisseth Paola Castañeda Vega

---

## 📱 Descripción del Proyecto
Aplicación móvil multiplataforma desarrollada en **Flutter** con arquitectura *Offline-First* (SQLite) para el registro y control de asistencia académica en la Universidad de La Guajira. El sistema opera **sin tocar el SMA** y con **costo de servidor $0**, combinando proximidad criptográfica por Bluetooth Low Energy (BLE) con confirmación instantánea por mapas de bits y una capa de respaldo institucional basada en Google Sheets (`@uniguajira.edu.co`).

---

## ⚙️ Núcleo Tecnológico (Arquitectura Aprobada)

1. **Ingesta de Cursos sin tocar el SMA:**
   - Importación directa de archivos `.xlsx` y `.csv`, pegado masivo de listas desde el portapapeles y registro manual de estudiantes.
2. **Proximidad Criptográfica BLE + Eco de Mapa de Bits (8 Bytes):**
   - El estudiante emite un paquete BLE con etiqueta rotativa `HMAC-SHA256` cada 30 segundos.
   - El docente emite un único paquete de anuncio de **24 bytes** que incluye un **Mapa de Bits de 8 bytes (64 posiciones)**.
   - El teléfono del estudiante detecta su bit en tiempo real y muestra su **Sello Criptográfico Verde** sin requerir conexiones GATT ni servidor central.
3. **Lista Invertida de Excepción (Cero Exclusión):**
   - Los estudiantes sin dispositivo móvil o con batería descargada son registrados de forma rápida por el docente en la misma pantalla mediante una lista invertida a un toque.
4. **Cierre, Reportes y Nube Institucional (`$0`):**
   - Firma criptográfica del Acta de Sesión, generación local del libro **Excel oficial (`.xlsx`)** con las 4 hojas reglamentarias (`Resumen`, `Detalle`, `Sesiones`, `Metadatos`) y sincronización asíncrona con **Google Sheets y Google Drive (`@uniguajira.edu.co`)**.

---

## 🛠️ Comandos de Ejecución y Verificación

```bash
flutter pub get
flutter analyze
flutter test
flutter run```