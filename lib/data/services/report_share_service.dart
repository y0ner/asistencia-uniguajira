import 'dart:io';

import 'package:share_plus/share_plus.dart';

/// Firma de la función que invoca la plataforma nativa de compartir.
///
/// Permite desacoplar el plugin de la plataforma y facilitar pruebas unitarias.
typedef ShareHandler = Future<ShareResult> Function(ShareParams params);

/// Estados resultantes de la operación de compartir un reporte.
enum ReportShareStatus {
  /// El usuario completó o seleccionó una aplicación de destino.
  success,

  /// El usuario cerró o descartó la hoja de compartir sin seleccionar acción.
  dismissed,

  /// La plataforma no soporta compartir o el resultado no está disponible.
  unavailable,

  /// Ocurrió un error de validación del archivo o una falla durante el compartir.
  error,
}

/// Resultado estructurado de compartir un reporte institucional.
class ReportShareOutcome {
  const ReportShareOutcome({
    required this.status,
    this.errorMessage,
    this.rawResult,
  });

  /// Crea un resultado exitoso.
  factory ReportShareOutcome.success({ShareResult? rawResult}) {
    return ReportShareOutcome(
      status: ReportShareStatus.success,
      rawResult: rawResult,
    );
  }

  /// Crea un resultado cuando el usuario descarta la hoja de compartir.
  factory ReportShareOutcome.dismissed({ShareResult? rawResult}) {
    return ReportShareOutcome(
      status: ReportShareStatus.dismissed,
      rawResult: rawResult,
    );
  }

  /// Crea un resultado cuando el mecanismo de compartir no está disponible.
  factory ReportShareOutcome.unavailable({ShareResult? rawResult}) {
    return ReportShareOutcome(
      status: ReportShareStatus.unavailable,
      rawResult: rawResult,
    );
  }

  /// Crea un resultado de error con mensaje descriptivo en español.
  factory ReportShareOutcome.error(String message) {
    return ReportShareOutcome(
      status: ReportShareStatus.error,
      errorMessage: message,
    );
  }

  /// Estado de la operación de compartir.
  final ReportShareStatus status;

  /// Mensaje de error legible para el usuario en español (solo presente si [isError]).
  final String? errorMessage;

  /// Resultado crudo provisto por `share_plus`, si se llegó a invocar la plataforma.
  final ShareResult? rawResult;

  /// Indica si la acción de compartir fue exitosa.
  bool get isSuccess => status == ReportShareStatus.success;

  /// Indica si el usuario descartó el diálogo de compartir.
  bool get isDismissed => status == ReportShareStatus.dismissed;

  /// Indica si el resultado no está disponible en la plataforma.
  bool get isUnavailable => status == ReportShareStatus.unavailable;

  /// Indica si ocurrió un error durante la validación o el proceso de compartir.
  bool get isError => status == ReportShareStatus.error;
}

/// Servicio encargado de compartir reportes oficiales (.xlsx) del docente
/// mediante las aplicaciones del sistema (WhatsApp, correo institucional, Drive, etc.).
class ReportShareService {
  ReportShareService({
    ShareHandler? shareHandler,
  }) : _shareHandler = shareHandler ?? SharePlus.instance.share;

  final ShareHandler _shareHandler;

  /// Tipo MIME oficial para hojas de cálculo Excel modernas OpenXML (.xlsx).
  static const String excelMimeType =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  /// Comparte el archivo de reporte indicado en [filePath] asociado al curso [courseName].
  ///
  /// Verifica previamente que el archivo exista y contenga datos (> 0 bytes).
  /// Si el archivo no existe o está vacío, retorna inmediatamente [ReportShareOutcome.error]
  /// sin invocar la plataforma de compartir.
  Future<ReportShareOutcome> shareReport({
    required String filePath,
    required String courseName,
  }) async {
    final trimmedPath = filePath.trim();
    if (trimmedPath.isEmpty) {
      return ReportShareOutcome.error(
        'La ruta del archivo de reporte no puede estar vacía.',
      );
    }

    final file = File(trimmedPath);
    final bool exists;
    try {
      exists = await file.exists();
    } catch (e) {
      return ReportShareOutcome.error(
        'Error al verificar la existencia del archivo de reporte: $e',
      );
    }

    if (!exists) {
      return ReportShareOutcome.error(
        'El archivo de reporte no existe: $trimmedPath',
      );
    }

    final int length;
    try {
      length = await file.length();
    } catch (e) {
      return ReportShareOutcome.error(
        'Error al leer el tamaño del archivo de reporte: $e',
      );
    }

    if (length == 0) {
      return ReportShareOutcome.error(
        'El archivo de reporte está vacío (0 bytes).',
      );
    }

    final trimmedCourseName = courseName.trim().isEmpty ? 'Asignatura' : courseName.trim();
    final subject = 'Reporte oficial de asistencia - $trimmedCourseName';
    final text =
        'Reporte oficial de asistencia del curso $trimmedCourseName generado por Asistencia Uniguajira.';

    final params = ShareParams(
      files: <XFile>[
        XFile(
          file.path,
          mimeType: excelMimeType,
        ),
      ],
      subject: subject,
      text: text,
    );

    try {
      final result = await _shareHandler(params);
      switch (result.status) {
        case ShareResultStatus.success:
          return ReportShareOutcome.success(rawResult: result);
        case ShareResultStatus.dismissed:
          return ReportShareOutcome.dismissed(rawResult: result);
        case ShareResultStatus.unavailable:
          return ReportShareOutcome.unavailable(rawResult: result);
      }
    } catch (e) {
      return ReportShareOutcome.error(
        'Error al abrir el menú para compartir el reporte: $e',
      );
    }
  }
}
