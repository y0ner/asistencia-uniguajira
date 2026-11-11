# Prueba 01 · Dos celulares Android reales

- **Objetivo:** comprobar que la Oleada 1 funciona fuera del computador. Que el Bluetooth aguante una clase, que los fallos se vean en pantalla, que las dos apps convivan y que el Excel se pueda compartir.
- **No es objetivo:** validar la distancia de 20–30 cm. Hoy el umbral (`minRssiDbm = -75`) detecta a 1–3 m; aquí solo se **mide** para calibrar en la Oleada 2.
- **Personas:** 2 (una con el celular docente y otra con el celular estudiante).
- **Duración:** unos 40 minutos.

## 0. Preparación

1. Compilar desde `dev`:

   ```bash
   ./run.sh apk-docente      # build/app/outputs/flutter-apk/app-docente-debug.apk
   ./run.sh apk-estudiante   # build/app/outputs/flutter-apk/app-estudiante-debug.apk
   ```

2. En cada celular, activar **Opciones de desarrollador → Depuración USB**, conectarlo y aceptar la huella del PC.
3. Instalar (`adb devices` muestra el número de serie de cada uno):

   ```bash
   adb -s <SERIE_DOCENTE>    install -r build/app/outputs/flutter-apk/app-docente-debug.apk
   adb -s <SERIE_ESTUDIANTE> install -r build/app/outputs/flutter-apk/app-estudiante-debug.apk
   ```

4. Anotar el modelo y la versión de Android de cada celular en la tabla de resultados.

## 1. Dos apps en un mismo celular (O1-B)

En el celular docente, instalar **también** la APK del estudiante.

- [ ] Aparecen dos íconos: "Asistencia Docente" y "Asistencia Estudiante".
- [ ] Cada una abre directo en su rol, sin selector.
- [ ] El ícono de Bluetooth de la barra superior abre el diagnóstico. En Android 12 o superior **no** aparece "Ubicación".

Después, desinstalar la app del estudiante de ese celular para no confundirse.

## 2. Permisos y Bluetooth apagado (O1-A)

En el celular estudiante:

1. Apagar el Bluetooth y entrar a marcar asistencia.
   - [ ] La app muestra que falta el Bluetooth y el botón **"Encender Bluetooth"**. Al tocarlo, Android pide encenderlo.
2. En Ajustes de Android → Apps → Asistencia Estudiante → Permisos, **negar** "Dispositivos cercanos" y volver a la app.
   - [ ] La app lo detecta y ofrece **"Abrir Ajustes"**. Al conceder el permiso y tocar **"Reintentar Verificación"**, continúa.

Repetir en el celular docente al iniciar una sesión.

## 3. Curso e inscripción

1. Docente: **Nuevo Curso**. Luego importar la lista con al menos el estudiante de prueba.
2. Estudiante: **Escanear QR** con el QR de inscripción que muestra el docente para ese estudiante.
   - [ ] El curso aparece en "Mis Cursos Enrolados".

## 4. Sesión de 10 minutos con pantalla bloqueada (O1-A)

Separación inicial: **1 metro**, sobre una mesa.

1. Docente: inicia la sesión del curso y dicta el **PIN de 2 dígitos**.
2. Estudiante: **Marcar Asistencia BLE** y escribe el PIN.
   - [ ] El estudiante queda **confirmado** en la pantalla del docente. Anotar cuántos segundos tardó.
3. Dejar las dos pantallas encendidas.
   - [ ] La pantalla **no** se apaga sola (wakelock).
4. Al minuto 5, **bloquear a mano** el celular del estudiante durante 30 s y desbloquearlo.
   - [ ] El estudiante sigue o vuelve a quedar confirmado.
   - [ ] No aparece ningún banner rojo. Si aparece, **fotografiarlo** y copiar el texto exacto.
5. Al minuto 10: **Cerrar y Firmar Acta**.
   - [ ] El acta queda firmada y la pantalla vuelve a apagarse normal.

## 5. Distancia (solo medir, para la Oleada 2)

Con una sesión nueva, alejar el celular del estudiante en pasos: **0,3 m · 1 m · 2 m · 3 m · 5 m**, unos 30 s en cada punto.

- Anotar en cada distancia si queda confirmado o no.
- Si el diagnóstico muestra el RSSI (dBm), anotarlo también.
- Repetir una vez con un cuerpo o una pared entre los celulares.

## 6. Compartir el Excel (O1-C)

1. Docente: curso → **Reportes** → exportar el Excel.
2. En el diálogo, **Compartir** → WhatsApp o Drive.
   - [ ] El archivo llega y abre en Excel o Google Sheets con **4 hojas**.
3. Salir y volver a Reportes.
   - [ ] Aparece **"Compartir último Excel"**.

## Resultados (llenar y devolver al agente jefe)

| Dato | Docente | Estudiante |
|---|---|---|
| Marca y modelo | | |
| Versión de Android | | |

| Paso | ¿Pasó? | Observaciones / texto exacto de errores |
|---|---|---|
| 1. Dos apps | | |
| 2. Permisos y Bluetooth | | |
| 3. Inscripción | | |
| 4. Sesión de 10 min (segundos hasta confirmar) | | |
| 4. Bloqueo al minuto 5 | | |
| 6. Compartir Excel | | |

| Distancia | 0,3 m | 1 m | 2 m | 3 m | 5 m | Con obstáculo |
|---|---|---|---|---|---|---|
| ¿Confirmado? | | | | | | |
| RSSI (si se ve) | | | | | | |

Si algo falla, el registro técnico sirve mucho:

```bash
adb -s <SERIE> logcat -d | grep -iE "flutter|ble|advertis|bluetooth" > logcat_<rol>.txt
```
