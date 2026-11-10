# Brief O1-C · Compartir el Excel desde el celular del docente

- **Rama:** `feat/compartir-excel` · **Worktree:** `../worktrees/feat-compartir-excel`
- **Lee primero:** `AGENTS.md` (reglas obligatorias).
- **Objetivo:** que después de exportar el Excel, el docente pueda **compartirlo o abrirlo** (WhatsApp, correo, Drive, gestor de archivos) con un toque. Hoy se guarda en una carpeta que el docente no encuentra.

## Contexto

`lib/features/teacher/course_reports_screen.dart`, `_exportOfficialExcelWorkbook()` (≈ línea 159), llama a `ExcelReportService.exportWorkbookToFile` y muestra `_showExportSuccessDialog` con la ruta. `_resolveExportDirectory()` (≈ línea 120) elige la carpeta. `share_plus` ya está en `pubspec.yaml`.

## Archivos permitidos

- `lib/features/teacher/course_reports_screen.dart`
- `lib/data/services/report_share_service.dart` (**nuevo**)
- `test/report_share_service_test.dart` (**nuevo**)

## Qué hacer

1. Crea `ReportShareService` con `Future<ReportShareOutcome> shareReport({required String filePath, required String courseName})`. Usa `SharePlus.instance.share(ShareParams(files: [XFile(filePath, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')], subject: …, text: …))`; revisa la API exacta en `~/.pub-cache/hosted/pub.dev/share_plus-13.*/`. Inyecta la función de compartir en el constructor para poder probarlo sin plataforma.
2. Antes de compartir, verifica que el archivo exista y no esté vacío. Si no, devuelve un resultado de error con un mensaje en español.
3. En el diálogo de éxito de la exportación, agrega dos acciones: **"Compartir"** (principal) y **"Cerrar"**. Mantén la información que ya muestra (tamaño y huella HMAC).
4. Agrega también un botón **"Compartir último Excel"** junto al de exportar. Solo aparece si ya existe un archivo exportado de ese curso en la carpeta de exportación.
5. Los errores se muestran en un `SnackBar` con los colores de estado de `AppColors`; nada de `catch (_) {}`.

## Criterios de aceptación

- [ ] Pruebas de `ReportShareService`: archivo válido (la función falsa recibe la ruta y el *mime type* correctos), archivo inexistente y archivo vacío.
- [ ] El diálogo de éxito tiene el botón "Compartir", que llama al servicio.
- [ ] `flutter analyze --no-pub` sin problemas.

## Qué se probará en el celular (lo hace el humano)

Exportar el Excel de un curso, tocar "Compartir", enviarlo por WhatsApp o guardarlo en Drive y abrirlo en Excel o Google Sheets: deben aparecer las 4 hojas.
