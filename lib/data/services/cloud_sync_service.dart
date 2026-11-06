import 'dart:convert';
import 'dart:typed_data';

import '../../core/constants/app_constants.dart';
import '../local/app_database.dart';
import 'excel_report_service.dart';

/// Estados de dominio devueltos por [CloudSyncService].
abstract final class CloudSyncStatus {
  /// El transporte confirmó la sincronización institucional.
  static const String synced = 'SYNCED';

  /// El paquete quedó listo para exportación o reintento offline.
  static const String offlineReady = 'OFFLINE_READY';

  /// El transporte se ejecutó pero no confirmó la sincronización.
  static const String failed = 'SYNC_FAILED';

  /// Alias de [offlineReady] para consumidores que hablan de cola local.
  static const String queued = offlineReady;
}

/// Paquete tabular serializable con las cuatro hojas oficiales del curso.
class CloudSyncPayload {
  CloudSyncPayload({
    required this.courseId,
    required this.courseCode,
    required this.courseName,
    required this.reportHmacSha256,
    required this.generatedAtIso,
    required Map<String, List<List<Object?>>> sheets,
    Uint8List? workbookBytes,
  }) : sheets = _freezeSheets(sheets),
       workbookBytes = workbookBytes == null
           ? null
           : Uint8List.fromList(workbookBytes);

  /// Identificador del curso.
  final String courseId;

  /// Código institucional del curso.
  final String courseCode;

  /// Nombre del curso.
  final String courseName;

  /// Huella HMAC-SHA256 de la integridad del reporte.
  final String reportHmacSha256;

  /// Instante de generación del reporte en ISO8601 UTC.
  final String generatedAtIso;

  /// Filas de las hojas `Resumen`, `Detalle`, `Sesiones` y `Metadatos`.
  final Map<String, List<List<Object?>>> sheets;

  /// Libro `.xlsx` listo para compartir o subir a Google Drive.
  final Uint8List? workbookBytes;

  /// Alias de [reportHmacSha256] usado por el contrato de sincronización.
  String get reportSignatureHmac => reportHmacSha256;

  /// Nombres de las cuatro hojas en su orden reglamentario.
  List<String> get sheetNames =>
      List<String>.unmodifiable(sheets.keys.toList(growable: false));

  /// Cantidad total de filas, incluyendo los encabezados de cada hoja.
  int get sheetsRowCount => sheets.values.fold<int>(
    0,
    (int total, List<List<Object?>> rows) => total + rows.length,
  );

  /// Cantidad de filas de datos, excluyendo los encabezados.
  int get dataRowCount => sheets.values.fold<int>(
    0,
    (int total, List<List<Object?>> rows) =>
        total + (rows.isEmpty ? 0 : rows.length - 1),
  );

  /// Encabezado de una hoja, o una lista vacía si no existe.
  List<Object?> headersFor(String sheetName) {
    final rows = sheets[sheetName];
    if (rows == null || rows.isEmpty) {
      return const <Object?>[];
    }
    return List<Object?>.unmodifiable(rows.first);
  }

  /// Filas de datos de una hoja, sin su encabezado.
  List<List<Object?>> rowsFor(String sheetName) {
    final rows = sheets[sheetName];
    if (rows == null || rows.length <= 1) {
      return const <List<Object?>>[];
    }
    return List<List<Object?>>.unmodifiable(rows.skip(1));
  }

  /// Serializa el paquete a una estructura JSON.
  ///
  /// El libro binario se omite por defecto; se puede incluir como Base64 para
  /// transportes que necesiten enviar también el archivo a Google Drive.
  Map<String, Object?> toJson({bool includeWorkbookBytes = false}) {
    final json = <String, Object?>{
      'courseId': courseId,
      'courseCode': courseCode,
      'courseName': courseName,
      'reportHmacSha256': reportHmacSha256,
      'generatedAtIso': generatedAtIso,
      'sheets': <String, Object?>{
        for (final MapEntry<String, List<List<Object?>>> entry
            in sheets.entries)
          entry.key: entry.value
              .map((List<Object?> row) => List<Object?>.of(row))
              .toList(growable: false),
      },
    };
    final bytes = workbookBytes;
    if (includeWorkbookBytes && bytes != null) {
      json['workbookBase64'] = base64Encode(bytes);
    }
    return json;
  }

  /// Serializa el paquete como una cadena JSON.
  String toJsonString({bool includeWorkbookBytes = false}) {
    return jsonEncode(toJson(includeWorkbookBytes: includeWorkbookBytes));
  }
}

/// Resultado de una operación de sincronización institucional.
class CloudSyncResult {
  const CloudSyncResult({
    required this.status,
    required this.syncedAtIso,
    required this.sheetsRowCount,
    required this.reportSignatureHmac,
    required this.xlsxBytes,
    this.payload,
    this.institutionalEmail,
    this.transportUsed = false,
    this.transportSucceeded = false,
    this.errorMessage,
  });

  /// Uno de los valores de [CloudSyncStatus].
  final String status;

  /// Instante de finalización de la operación en ISO8601 UTC.
  final String syncedAtIso;

  /// Cantidad total de filas tabulares, incluyendo encabezados.
  final int sheetsRowCount;

  /// Huella HMAC-SHA256 del reporte enviado.
  final String reportSignatureHmac;

  /// Libro `.xlsx` generado para el curso.
  final Uint8List xlsxBytes;

  /// Paquete tabular que se envió o quedó listo para exportación.
  final CloudSyncPayload? payload;

  /// Cuenta institucional utilizada para la operación.
  final String? institutionalEmail;

  /// Indica si se ejecutó un transporte de red.
  final bool transportUsed;

  /// Indica si el transporte confirmó la operación.
  final bool transportSucceeded;

  /// Detalle del fallo de transporte, si existe.
  final String? errorMessage;

  /// Alias de [xlsxBytes].
  Uint8List get workbookBytes => xlsxBytes;

  /// Alias de [xlsxBytes].
  Uint8List get excelBytes => xlsxBytes;

  /// Alias de [xlsxBytes].
  Uint8List get fileBytes => xlsxBytes;

  /// Alias de [reportSignatureHmac].
  String get reportHmacSha256 => reportSignatureHmac;

  /// Cantidad de filas de datos, sin contar los encabezados.
  int get dataRowCount {
    final package = payload;
    return package?.dataRowCount ?? 0;
  }

  /// Indica si la sincronización fue confirmada por el transporte.
  bool get isSynced => status == CloudSyncStatus.synced;

  /// Indica si el paquete quedó listo para exportación o reintento offline.
  bool get isOfflineReady => status == CloudSyncStatus.offlineReady;

  /// Indica si la operación terminó correctamente o quedó lista offline.
  bool get isSuccess =>
      status == CloudSyncStatus.synced ||
      status == CloudSyncStatus.offlineReady;

  /// Indica si el transporte falló.
  bool get hasFailed => status == CloudSyncStatus.failed;

  /// Serializa el resultado a JSON, incluyendo el libro en Base64.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status,
      'syncedAtIso': syncedAtIso,
      'sheetsRowCount': sheetsRowCount,
      'reportSignatureHmac': reportSignatureHmac,
      'institutionalEmail': institutionalEmail,
      'transportUsed': transportUsed,
      'transportSucceeded': transportSucceeded,
      'errorMessage': errorMessage,
      'xlsxBase64': base64Encode(xlsxBytes),
    };
  }
}

/// Servicio de sincronización institucional con cuentas `@uniguajira.edu.co`.
///
/// La generación del paquete es local y funciona sin red. El envío real se
/// inyecta mediante [syncCourseToInstitutionalCloud.transportOverride], lo que
/// permite conectar Google Sign-In/Sheets sin acoplar este servicio a un cliente
/// HTTP específico.
class CloudSyncService {
  CloudSyncService({
    AppDatabase? database,
    ExcelReportService? excelReportService,
  }) : _excelReportService =
           excelReportService ??
           ExcelReportService(database: database ?? AppDatabase.instance);

  final ExcelReportService _excelReportService;

  /// Generador de reportes utilizado por la sincronización.
  ExcelReportService get excelReportService => _excelReportService;

  /// Valida que [email] sea una cuenta institucional de La Guajira.
  ///
  /// Acepta mayúsculas y minúsculas, pero exige exactamente el dominio de
  /// [AppConstants.institutionalDomain] y una parte local no vacía.
  bool isValidInstitutionalEmail(String email) {
    final normalized = email.trim();
    if (normalized.isEmpty || normalized.contains(RegExp(r'\s'))) {
      return false;
    }

    final atIndex = normalized.lastIndexOf('@');
    if (atIndex <= 0 || atIndex != normalized.indexOf('@')) {
      return false;
    }

    final localPart = normalized.substring(0, atIndex);
    final domain = normalized.substring(atIndex).toLowerCase();
    if (domain != AppConstants.institutionalDomain.toLowerCase()) {
      return false;
    }
    if (!RegExp(r'^[A-Za-z0-9._%+-]+$').hasMatch(localPart)) {
      return false;
    }
    if (localPart.startsWith('.') ||
        localPart.endsWith('.') ||
        localPart.contains('..')) {
      return false;
    }
    return true;
  }

  /// Construye las cuatro hojas y el libro binario listo para sincronizar.
  Future<CloudSyncPayload> buildGoogleSheetsPayload(String courseId) async {
    final summary = await _excelReportService.buildCourseSummary(courseId);
    final workbookBytes = _excelReportService.generateWorkbookFromSummary(
      summary,
    );
    return CloudSyncPayload(
      courseId: summary.course.id,
      courseCode: summary.course.code,
      courseName: summary.course.name,
      reportHmacSha256: summary.reportHmacSha256,
      generatedAtIso: summary.generatedAtIso,
      sheets: summary.sheets,
      workbookBytes: workbookBytes,
    );
  }

  /// Sincroniza el curso con el transporte institucional inyectado.
  ///
  /// Valida primero la cuenta institucional, construye el reporte real desde
  /// SQLite y ejecuta [transportOverride] cuando está disponible. Sin transporte
  /// devuelve el paquete y el `.xlsx` en estado [CloudSyncStatus.offlineReady].
  Future<CloudSyncResult> syncCourseToInstitutionalCloud({
    required String courseId,
    required String institutionalEmail,
    Future<bool> Function(CloudSyncPayload payload)? transportOverride,
  }) async {
    final normalizedEmail = institutionalEmail.trim();
    if (!isValidInstitutionalEmail(normalizedEmail)) {
      throw ArgumentError.value(
        institutionalEmail,
        'institutionalEmail',
        'La cuenta debe pertenecer al dominio '
            '${AppConstants.institutionalDomain}.',
      );
    }

    final payload = await buildGoogleSheetsPayload(courseId);
    final workbookBytes = payload.workbookBytes;
    if (workbookBytes == null) {
      throw StateError(
        'El paquete de sincronización no contiene el libro .xlsx.',
      );
    }

    if (transportOverride == null) {
      return CloudSyncResult(
        status: CloudSyncStatus.offlineReady,
        syncedAtIso: DateTime.now().toUtc().toIso8601String(),
        sheetsRowCount: payload.sheetsRowCount,
        reportSignatureHmac: payload.reportHmacSha256,
        xlsxBytes: workbookBytes,
        payload: payload,
        institutionalEmail: normalizedEmail,
        transportUsed: false,
        transportSucceeded: false,
      );
    }

    try {
      final succeeded = await transportOverride(payload);
      return CloudSyncResult(
        status: succeeded ? CloudSyncStatus.synced : CloudSyncStatus.failed,
        syncedAtIso: DateTime.now().toUtc().toIso8601String(),
        sheetsRowCount: payload.sheetsRowCount,
        reportSignatureHmac: payload.reportHmacSha256,
        xlsxBytes: workbookBytes,
        payload: payload,
        institutionalEmail: normalizedEmail,
        transportUsed: true,
        transportSucceeded: succeeded,
        errorMessage: succeeded
            ? null
            : 'El transporte no confirmó la sincronización.',
      );
    } catch (error) {
      return CloudSyncResult(
        status: CloudSyncStatus.failed,
        syncedAtIso: DateTime.now().toUtc().toIso8601String(),
        sheetsRowCount: payload.sheetsRowCount,
        reportSignatureHmac: payload.reportHmacSha256,
        xlsxBytes: workbookBytes,
        payload: payload,
        institutionalEmail: normalizedEmail,
        transportUsed: true,
        transportSucceeded: false,
        errorMessage: error.toString(),
      );
    }
  }
}

Map<String, List<List<Object?>>> _freezeSheets(
  Map<String, List<List<Object?>>> sheets,
) {
  final frozen = <String, List<List<Object?>>>{};
  for (final MapEntry<String, List<List<Object?>>> entry in sheets.entries) {
    frozen[entry.key] = List<List<Object?>>.unmodifiable(
      entry.value
          .map((List<Object?> row) => List<Object?>.unmodifiable(row))
          .toList(growable: false),
    );
  }
  return Map<String, List<List<Object?>>>.unmodifiable(frozen);
}
