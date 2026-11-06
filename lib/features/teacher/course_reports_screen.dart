import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/course_model.dart';
import '../../core/models/session_model.dart';
import '../../data/local/app_database.dart';
import '../../data/services/cloud_sync_service.dart';
import '../../data/services/excel_report_service.dart';
import 'live_attendance_session_screen.dart';
import 'signed_acta_dialog.dart';

/// Centro institucional de reportes de asistencia para docentes:
/// - Métricas consolidadas en tiempo real: sesiones cerradas, % promedio de
///   asistencia global, alertas académicas y actas firmadas.
/// - Pestaña 1: Resumen de estudiantes ordenado por Bit Index con estados
///   de alerta semaforizados (NORMAL / ALERTA / PÉRDIDA).
/// - Pestaña 2: Historial de sesiones con PIN verbal, Bitmap de 8 bytes y
///   actas criptográficas HMAC-SHA256.
/// - Pestaña 3: Sincronización con Google Sheets y cuentas institucionales
///   `@uniguajira.edu.co`.
/// - Exportación oficial del libro Excel (.xlsx de 4 hojas) al almacenamiento local.
class CourseReportsScreen extends StatefulWidget {
  const CourseReportsScreen({
    super.key,
    required this.course,
    this.database,
    this.excelService,
    this.cloudSyncService,
  });

  /// Curso institucional objeto del reporte.
  final CourseModel course;

  /// Base de datos SQLite local opcional para inyección en pruebas.
  final AppDatabase? database;

  /// Servicio generador de reportes Excel opcional.
  final ExcelReportService? excelService;

  /// Servicio de sincronización institucional opcional.
  final CloudSyncService? cloudSyncService;

  @override
  State<CourseReportsScreen> createState() => _CourseReportsScreenState();
}

class _CourseReportsScreenState extends State<CourseReportsScreen> {
  static const Color _uniguajiraBlue = Color(0xFF0033A0);
  static const Color _uniguajiraGold = Color(0xFFEAAA00);

  late final AppDatabase _database;
  late final ExcelReportService _excelService;
  late final CloudSyncService _cloudSyncService;
  final TextEditingController _institutionalEmailController =
      TextEditingController();
  final GlobalKey<FormState> _syncFormKey = GlobalKey<FormState>();

  bool _isLoading = true;
  bool _isExporting = false;
  bool _isSyncing = false;
  String? _loadError;

  CourseAttendanceSummary? _summary;
  List<SessionModel> _sessions = <SessionModel>[];
  Map<String, String?> _actaSignatures = <String, String?>{};
  Map<String, String?> _actaJsons = <String, String?>{};

  String _studentFilter = 'ALL';
  String _searchQuery = '';
  CloudSyncResult? _lastSyncResult;

  @override
  void initState() {
    super.initState();
    _database = widget.database ?? AppDatabase.instance;
    _excelService =
        widget.excelService ?? ExcelReportService(database: _database);
    _cloudSyncService =
        widget.cloudSyncService ??
        CloudSyncService(
          database: _database,
          excelReportService: _excelService,
        );
    _loadReportData();
  }

  @override
  void dispose() {
    _institutionalEmailController.dispose();
    super.dispose();
  }

  Future<void> _loadReportData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final summary = await _excelService.buildCourseSummary(widget.course.id);
      final sessions = await _database.getSessionsByCourse(widget.course.id);

      final signatures = <String, String?>{};
      final jsons = <String, String?>{};

      for (final session in sessions) {
        signatures[session.id] = await _database.getSessionActaSignature(
          session.id,
        );
        jsons[session.id] = await _database.getSessionActaJson(session.id);
      }

      if (mounted) {
        setState(() {
          _summary = summary;
          _sessions = sessions;
          _actaSignatures = signatures;
          _actaJsons = jsons;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<String> _resolveExportDirectory() async {
    // Si existe la carpeta pública de descargas de Android, priorizarla para fácil acceso.
    final downloadsDir = Directory('/storage/emulated/0/Download');
    if (await downloadsDir.exists()) {
      return downloadsDir.path;
    }

    try {
      final databasesDir = await getDatabasesPath();
      final reportsDir = Directory(p.join(databasesDir, 'reports'));
      if (!await reportsDir.exists()) {
        await reportsDir.create(recursive: true);
      }
      return reportsDir.path;
    } catch (_) {
      final tempDir = Directory(p.join(Directory.systemTemp.path, 'reports'));
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }
      return tempDir.path;
    }
  }

  Future<void> _exportOfficialExcelWorkbook() async {
    if (_isExporting) return;

    setState(() => _isExporting = true);

    try {
      final targetDirectory = await _resolveExportDirectory();
      final filePath = await _excelService.exportWorkbookToFile(
        courseId: widget.course.id,
        directoryPath: targetDirectory,
      );

      final file = File(filePath);
      final fileSizeBytes = await file.exists() ? await file.length() : 0;
      final summary = _summary ?? await _excelService.buildCourseSummary(widget.course.id);
      final hmacSha256 = summary.reportHmacSha256;

      if (!mounted) return;
      setState(() => _isExporting = false);

      await _showExportSuccessDialog(
        filePath: filePath,
        fileSizeBytes: fileSizeBytes,
        hmacSha256: hmacSha256,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isExporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al exportar libro Excel: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _showExportSuccessDialog({
    required String filePath,
    required int fileSizeBytes,
    required String hmacSha256,
  }) async {
    final fileName = p.basename(filePath);
    final sizeKb = (fileSizeBytes / 1024).toStringAsFixed(1);

    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.table_view_rounded,
                  color: Colors.green.shade800,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Excel Oficial Generado',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'El libro oficial de 4 hojas reglamentarias (Resumen, Detalle, '
                  'Sesiones y Metadatos) fue generado y firmado exitosamente.',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
                const SizedBox(height: 16),
                _buildInfoRow('Archivo:', fileName, isBold: true),
                const SizedBox(height: 6),
                _buildInfoRow('Tamaño:', '$fileSizeBytes bytes ($sizeKb KB)'),
                const SizedBox(height: 6),
                _buildInfoRow('Hojas:', '4 (Resumen, Detalle, Sesiones, Metadatos)'),
                const SizedBox(height: 12),
                const Text(
                  'Ruta en almacenamiento:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: SelectableText(
                    filePath,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Huella HMAC-SHA256 del reporte:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: SelectableText(
                    hmacSha256,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Colors.blue.shade900,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: filePath));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Ruta del archivo copiada al portapapeles.'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copiar Ruta'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: _uniguajiraBlue,
              ),
              child: const Text('Aceptar'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isBold = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleInstitutionalSync() async {
    if (!_syncFormKey.currentState!.validate()) {
      return;
    }

    final email = _institutionalEmailController.text.trim();
    setState(() => _isSyncing = true);

    try {
      final result = await _cloudSyncService.syncCourseToInstitutionalCloud(
        courseId: widget.course.id,
        institutionalEmail: email,
      );

      if (!mounted) return;
      setState(() {
        _lastSyncResult = result;
        _isSyncing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.isSynced
                ? 'Sincronización confirmada con Google Sheets.'
                : 'Paquete de 4 hojas listo para exportación institucional offline.',
          ),
          backgroundColor:
              result.isSuccess ? Colors.green.shade800 : Colors.orange.shade800,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSyncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fallo en sincronización institucional: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _viewSessionActa(SessionModel session) async {
    final actaJson = _actaJsons[session.id];
    if (actaJson != null && actaJson.isNotEmpty) {
      await SignedActaDialog.showFromJson(
        context,
        actaJson: actaJson,
        courseSecretHex: widget.course.courseSecret,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No existe acta firmada almacenada para esta sesión.'),
        ),
      );
    }
  }

  Future<void> _onStartBleSession() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => LiveAttendanceSessionScreen(
          course: widget.course,
          database: _database,
        ),
      ),
    );
    if (!mounted) return;
    if (result == true) {
      await _loadReportData();
    }
  }

  double _calculateAverageAttendance(List<StudentAttendanceMetric> students) {
    if (students.isEmpty) return 100.0;
    final sum = students.fold<double>(
      0.0,
      (double acc, StudentAttendanceMetric s) => acc + s.attendancePercentage,
    );
    return (sum / students.length * 10.0).roundToDouble() / 10.0;
  }

  int _countStudentsInLoss(List<StudentAttendanceMetric> students) {
    return students
        .where(
          (StudentAttendanceMetric s) =>
              s.alertStatus == AttendanceAlertStatus.failureByAbsences ||
              s.absencePercentage >= 25.0,
        )
        .length;
  }

  int _countStudentsInAlert(List<StudentAttendanceMetric> students) {
    return students
        .where(
          (StudentAttendanceMetric s) =>
              (s.alertStatus == AttendanceAlertStatus.attendanceAlert ||
                  s.absencePercentage >= 15.0) &&
              s.alertStatus != AttendanceAlertStatus.failureByAbsences &&
              s.absencePercentage < 25.0,
        )
        .length;
  }

  List<StudentAttendanceMetric> _getFilteredStudents(
    List<StudentAttendanceMetric> allStudents,
  ) {
    return allStudents.where((StudentAttendanceMetric s) {
      final matchesSearch = _searchQuery.isEmpty ||
          s.fullName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          s.studentCode.contains(_searchQuery);
      if (!matchesSearch) return false;

      final isLoss = s.alertStatus == AttendanceAlertStatus.failureByAbsences ||
          s.absencePercentage >= 25.0;
      final isAlert = (s.alertStatus == AttendanceAlertStatus.attendanceAlert ||
              s.absencePercentage >= 15.0) &&
          !isLoss;

      switch (_studentFilter) {
        case 'NORMAL':
          return !isLoss && !isAlert;
        case 'ALERT':
          return isAlert;
        case 'LOSS':
          return isLoss;
        case 'ALL':
        default:
          return true;
      }
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Centro de Reportes y Asistencia',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                '${widget.course.name} • Gr. ${widget.course.groupCode} • Sem. ${widget.course.semester}',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
          backgroundColor: _uniguajiraBlue,
          foregroundColor: Colors.white,
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar reporte',
              onPressed: _loadReportData,
            ),
          ],
          bottom: const TabBar(
            indicatorColor: _uniguajiraGold,
            indicatorWeight: 3.5,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: <Widget>[
              Tab(
                icon: Icon(Icons.people_alt_outlined),
                text: 'Resumen Estudiantes',
              ),
              Tab(
                icon: Icon(Icons.history_edu_outlined),
                text: 'Sesiones y Actas',
              ),
              Tab(
                icon: Icon(Icons.cloud_sync_outlined),
                text: 'Sincronización Nube',
              ),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
                ? _buildErrorView(theme, _loadError!)
                : _buildLoadedContent(theme),
        bottomNavigationBar: _buildBottomActions(theme),
      ),
    );
  }

  Widget _buildErrorView(ThemeData theme, String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              'Error al compilar reporte del curso',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _loadReportData,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
              style: FilledButton.styleFrom(backgroundColor: _uniguajiraBlue),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadedContent(ThemeData theme) {
    final summary = _summary;
    if (summary == null) {
      return const SizedBox.shrink();
    }

    final students = summary.students;
    final avgAttendance = _calculateAverageAttendance(students);
    final inLossCount = _countStudentsInLoss(students);
    final inAlertCount = _countStudentsInAlert(students);

    return Column(
      children: <Widget>[
        // Tarjetas superiores de métricas consolidadas
        _buildGlobalMetricsBar(
          theme: theme,
          totalClosedSessions: summary.totalClosedSessions,
          totalSessions: summary.totalSessions,
          avgAttendance: avgAttendance,
          inLossCount: inLossCount,
          inAlertCount: inAlertCount,
          signedActas: summary.totalSignedActas,
          reportHmac: summary.reportHmacSha256,
        ),

        // Contenido de las pestañas
        Expanded(
          child: TabBarView(
            children: <Widget>[
              // Pestaña 1: Resumen Estudiantes
              _buildStudentsSummaryTab(theme, students),

              // Pestaña 2: Sesiones y Actas Criptográficas
              _buildSessionsAndActasTab(theme, summary),

              // Pestaña 3: Sincronización Institucional Nube
              _buildInstitutionalSyncTab(theme, summary),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGlobalMetricsBar({
    required ThemeData theme,
    required int totalClosedSessions,
    required int totalSessions,
    required double avgAttendance,
    required int inLossCount,
    required int inAlertCount,
    required int signedActas,
    required String reportHmac,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.event_available_rounded,
                  iconColor: Colors.blue.shade700,
                  value: '$totalClosedSessions',
                  label: 'Sesiones Cerradas',
                  sublabel: 'de $totalSessions creadas',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.insights_rounded,
                  iconColor: avgAttendance >= 80 ? Colors.green.shade700 : Colors.orange.shade700,
                  value: '$avgAttendance%',
                  label: 'Asistencia Global',
                  sublabel: 'promedio del curso',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.warning_amber_rounded,
                  iconColor: inLossCount > 0 ? Colors.red.shade700 : (inAlertCount > 0 ? Colors.amber.shade800 : Colors.green.shade700),
                  value: '$inLossCount / $inAlertCount',
                  label: 'En Riesgo / Pérdida',
                  sublabel: inLossCount > 0 ? '>25% inasistencias' : '>15% inasistencias',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.verified_user_rounded,
                  iconColor: _uniguajiraBlue,
                  value: '$signedActas',
                  label: 'Actas HMAC-SHA256',
                  sublabel: 'firmas verificadas',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Huella de integridad global
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: <Widget>[
                const Icon(Icons.fingerprint, size: 16, color: _uniguajiraBlue),
                const SizedBox(width: 6),
                const Text(
                  'HMAC Reporte: ',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: _uniguajiraBlue,
                  ),
                ),
                Expanded(
                  child: Text(
                    reportHmac,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10.5,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 14),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  tooltip: 'Copiar HMAC global',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: reportHmac));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('HMAC-SHA256 del reporte copiado.'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
    required String sublabel,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            offset: const Offset(0, 1),
            blurRadius: 3,
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  sublabel,
                  style: TextStyle(
                    fontSize: 9.5,
                    color: Colors.grey.shade600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // PESTAÑA 1: Resumen de Estudiantes
  // ===========================================================================

  Widget _buildStudentsSummaryTab(
    ThemeData theme,
    List<StudentAttendanceMetric> students,
  ) {
    if (students.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.group_off_outlined, size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text(
                'No hay estudiantes inscritos en el curso.',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Importa el roster desde la pantalla anterior para visualizar métricas.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    final filtered = _getFilteredStudents(students);

    return Column(
      children: <Widget>[
        // Barra de búsqueda y filtros rápidos
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: <Widget>[
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'Buscar por nombre o código...',
                      hintStyle: const TextStyle(fontSize: 13),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Filtro por Chips de Semáforo
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: <Widget>[
              _buildFilterChoiceChip('ALL', 'Todos (${students.length})'),
              const SizedBox(width: 6),
              _buildFilterChoiceChip(
                'NORMAL',
                'Normal (${students.where((s) => s.absencePercentage < 15.0).length})',
                chipColor: Colors.green.shade700,
              ),
              const SizedBox(width: 6),
              _buildFilterChoiceChip(
                'ALERT',
                'Alerta >15% (${_countStudentsInAlert(students)})',
                chipColor: Colors.amber.shade900,
              ),
              const SizedBox(width: 6),
              _buildFilterChoiceChip(
                'LOSS',
                'Pérdida >25% (${_countStudentsInLoss(students)})',
                chipColor: Colors.red.shade800,
              ),
            ],
          ),
        ),

        const Divider(height: 12),

        // Lista de Estudiantes
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    'No hay estudiantes que coincidan con el filtro.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (BuildContext context, int index) {
                    final metric = filtered[index];
                    return _buildStudentMetricCard(theme, metric);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilterChoiceChip(
    String key,
    String label, {
    Color? chipColor,
  }) {
    final isSelected = _studentFilter == key;
    return ChoiceChip(
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 11.5,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected
            ? Colors.white
            : (chipColor ?? _uniguajiraBlue),
      ),
      selected: isSelected,
      selectedColor: chipColor ?? _uniguajiraBlue,
      backgroundColor: Colors.grey.shade100,
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      onSelected: (bool selected) {
        if (selected) {
          setState(() => _studentFilter = key);
        }
      },
    );
  }

  Widget _buildStudentMetricCard(
    ThemeData theme,
    StudentAttendanceMetric metric,
  ) {
    final isLoss = metric.alertStatus == AttendanceAlertStatus.failureByAbsences ||
        metric.absencePercentage >= 25.0;
    final isAlert = (metric.alertStatus == AttendanceAlertStatus.attendanceAlert ||
            metric.absencePercentage >= 15.0) &&
        !isLoss;

    final badgeColor = isLoss
        ? Colors.red.shade700
        : (isAlert ? Colors.amber.shade900 : Colors.green.shade700);
    final badgeBg = isLoss
        ? Colors.red.shade50
        : (isAlert ? Colors.amber.shade50 : Colors.green.shade50);
    final badgeText = isLoss ? 'PÉRDIDA' : (isAlert ? 'ALERTA' : 'NORMAL');

    final bitPadded = metric.bitIndex.toString().padLeft(2, '0');

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isLoss
              ? Colors.red.shade200
              : (isAlert ? Colors.amber.shade300 : Colors.grey.shade300),
          width: isLoss || isAlert ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Bit Index Badge
                Container(
                  width: 44,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _uniguajiraBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '#$bitPadded',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: _uniguajiraBlue,
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Datos del Estudiante
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        metric.fullName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: <Widget>[
                          Text(
                            'Cód: ${metric.studentCode}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: _uniguajiraBlue,
                            ),
                          ),
                          if (metric.email != null && metric.email!.isNotEmpty) ...<Widget>[
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                metric.email!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // Chip de Semáforo
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        isLoss
                            ? Icons.cancel
                            : (isAlert ? Icons.warning_rounded : Icons.check_circle),
                        size: 13,
                        color: badgeColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        badgeText,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: badgeColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Barra de progreso de asistencia
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: metric.attendancePercentage / 100.0,
                minHeight: 6,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(badgeColor),
              ),
            ),

            const SizedBox(height: 8),

            // Métricas detalladas: BLE, Manual, Inasistencias, Porcentaje
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                _buildStatPill(
                  icon: Icons.bluetooth,
                  label: 'BLE',
                  value: '${metric.bleAttendances}',
                  color: Colors.blue.shade700,
                ),
                _buildStatPill(
                  icon: Icons.how_to_reg,
                  label: 'Manual',
                  value: '${metric.manualAttendances}',
                  color: Colors.teal.shade700,
                ),
                _buildStatPill(
                  icon: Icons.event_busy,
                  label: 'Fallas',
                  value: '${metric.totalAbsences}',
                  color: metric.totalAbsences > 0 ? Colors.red.shade700 : Colors.grey.shade600,
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${metric.attendancePercentage}% Asist.',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: badgeColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatPill({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Text(
          '$label: ',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // PESTAÑA 2: Sesiones y Actas Criptográficas
  // ===========================================================================

  Widget _buildSessionsAndActasTab(
    ThemeData theme,
    CourseAttendanceSummary summary,
  ) {
    if (_sessions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.history_toggle_off, size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text(
                'No hay sesiones de clase registradas.',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Inicia una sesión de asistencia BLE con el botón inferior.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _sessions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int index) {
        final session = _sessions[index];
        final signature = _actaSignatures[session.id];
        final hasActa = _actaJsons[session.id] != null;
        return _buildSessionActaCard(theme, session, signature, hasActa);
      },
    );
  }

  Widget _buildSessionActaCard(
    ThemeData theme,
    SessionModel session,
    String? signature,
    bool hasActa,
  ) {
    final isClosed = session.closedAt != null || hasActa;
    final startDate = DateTime.tryParse(session.startedAt);
    final formattedStart = startDate != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(startDate)
        : session.startedAt.replaceAll('T', ' ').split('.').first;

    final closedDate = session.closedAt != null ? DateTime.tryParse(session.closedAt!) : null;
    final formattedClosed = closedDate != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(closedDate)
        : (session.closedAt?.replaceAll('T', ' ').split('.').first ?? 'En curso');

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isClosed ? Colors.green.shade300 : Colors.blue.shade300,
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Estado y PIN verbal
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isClosed ? Colors.green.shade50 : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isClosed ? Colors.green.shade400 : Colors.blue.shade400,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        isClosed ? Icons.verified_user : Icons.timelapse,
                        size: 14,
                        color: isClosed ? Colors.green.shade800 : Colors.blue.shade800,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isClosed ? 'CERRADA Y FIRMADA' : 'SESIÓN ABIERTA',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isClosed ? Colors.green.shade800 : Colors.blue.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: _uniguajiraGold.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _uniguajiraGold.withValues(alpha: 0.7)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.dialpad, size: 14, color: Colors.black87),
                      const SizedBox(width: 4),
                      Text(
                        'PIN Verbal: ${session.roomPin}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Fechas de Apertura y Cierre
            Row(
              children: <Widget>[
                Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  'Apertura: $formattedStart',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                Icon(Icons.lock_clock, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  'Cierre: $formattedClosed',
                  style: TextStyle(
                    fontSize: 12,
                    color: isClosed ? Colors.grey.shade800 : Colors.blue.shade700,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Bitmap de 8 Bytes en Hexadecimal
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: <Widget>[
                  Text(
                    'Bitmap (${AppConstants.bitmapByteLength}B): ',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '0x${session.bitmapHex}',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isClosed ? Colors.green.shade800 : Colors.blue.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Firma HMAC Criptográfica
            if (signature != null && signature.isNotEmpty) ...<Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.purple.shade200),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.key, size: 14, color: Colors.purple.shade800),
                    const SizedBox(width: 4),
                    const Text(
                      'Firma HMAC: ',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        signature,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          color: Colors.purple.shade900,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 13),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                      tooltip: 'Copiar firma HMAC',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: signature));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Firma HMAC de la sesión copiada.'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],

            // Botón de Acción: Ver Acta o Reanudar
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                if (hasActa)
                  FilledButton.tonalIcon(
                    onPressed: () => _viewSessionActa(session),
                    icon: const Icon(Icons.description_outlined, size: 16),
                    label: const Text('Ver Acta Firmada'),
                    style: FilledButton.styleFrom(
                      foregroundColor: _uniguajiraBlue,
                    ),
                  )
                else
                  FilledButton.icon(
                    onPressed: _onStartBleSession,
                    icon: const Icon(Icons.sensors, size: 16),
                    label: const Text('Reanudar Sesión BLE'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _uniguajiraBlue,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // PESTAÑA 3: Sincronización Nube Institucional (@uniguajira.edu.co)
  // ===========================================================================

  Widget _buildInstitutionalSyncTab(
    ThemeData theme,
    CourseAttendanceSummary summary,
  ) {
    final lastResult = _lastSyncResult;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Tarjeta Informativa Institucional
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.blue.shade200),
            ),
            color: Colors.blue.shade50.withValues(alpha: 0.5),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.school, color: _uniguajiraBlue, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Sincronización Institucional Uniguajira',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _uniguajiraBlue,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Exporta de manera segura el libro oficial de asistencia '
                          'hacia la cuenta institucional ${AppConstants.institutionalDomain}. '
                          'El paquete incluye las 4 hojas reglamentarias y la firma '
                          'HMAC-SHA256 para auditoría sin requerir dependencias propietarias.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade800,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Formulario de Validación de Correo
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _syncFormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Cuenta Institucional del Docente',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Solo se admiten correos con dominio ${AppConstants.institutionalDomain}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _institutionalEmailController,
                      keyboardType: TextInputType.emailAddress,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      decoration: InputDecoration(
                        labelText: 'Correo Institucional',
                        hintText: 'docente${AppConstants.institutionalDomain}',
                        prefixIcon: const Icon(Icons.alternate_email),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        if (email.isEmpty) {
                          return 'Por favor ingresa tu correo institucional';
                        }
                        if (!_cloudSyncService.isValidInstitutionalEmail(email)) {
                          return 'Solo se admiten cuentas con dominio ${AppConstants.institutionalDomain}';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isSyncing ? null : _handleInstitutionalSync,
                        icon: _isSyncing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.cloud_upload_outlined),
                        label: Text(
                          _isSyncing
                              ? 'Generando y Sincronizando...'
                              : 'Sincronizar con Google Sheets ${AppConstants.institutionalDomain}',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: _uniguajiraBlue,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Tarjeta de Resultado de la Sincronización
          if (lastResult != null) ...<Widget>[
            _buildSyncResultCard(theme, lastResult),
            const SizedBox(height: 16),
          ],

          // Estructura de las 4 Hojas Reglamentarias
          _buildSheetsSummaryCard(summary),
        ],
      ),
    );
  }

  Widget _buildSyncResultCard(ThemeData theme, CloudSyncResult result) {
    final isSuccess = result.isSuccess;
    final isSynced = result.isSynced;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isSynced
              ? Colors.green.shade400
              : (isSuccess ? Colors.blue.shade400 : Colors.red.shade400),
          width: 1.5,
        ),
      ),
      color: isSynced
          ? Colors.green.shade50
          : (isSuccess ? Colors.blue.shade50 : Colors.red.shade50),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  isSynced
                      ? Icons.check_circle
                      : (isSuccess ? Icons.cloud_done : Icons.error),
                  color: isSynced
                      ? Colors.green.shade800
                      : (isSuccess ? Colors.blue.shade800 : Colors.red.shade800),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isSynced
                        ? 'Sincronización Confirmada'
                        : (isSuccess
                            ? 'Paquete Institucional Listo (Modo Offline)'
                            : 'Fallo de Transporte'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isSynced
                          ? Colors.green.shade900
                          : (isSuccess ? Colors.blue.shade900 : Colors.red.shade900),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    result.status,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Cuenta: ${result.institutionalEmail ?? "No informada"}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Total de filas procesadas: ${result.sheetsRowCount} en 4 hojas',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              'Fecha ISO: ${result.syncedAtIso}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.fingerprint, size: 14, color: _uniguajiraBlue),
                  const SizedBox(width: 6),
                  const Text(
                    'HMAC: ',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: _uniguajiraBlue,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      result.reportSignatureHmac,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 13),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                    tooltip: 'Copiar HMAC',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: result.reportSignatureHmac));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Huella HMAC del paquete copiada.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSheetsSummaryCard(CourseAttendanceSummary summary) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Estructura del Libro Oficial (4 Hojas)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Especificación técnica reglamentaria de la Universidad de La Guajira.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            _buildSheetRow(
              '1. Resumen',
              'Consolidado por estudiante con Bit Index, % de asistencia y estado de alerta.',
              summary.sheets['Resumen']?.length ?? 0,
              Icons.people_outline,
            ),
            const Divider(height: 16),
            _buildSheetRow(
              '2. Detalle',
              'Matriz individual sesión por estudiante con RSSI, Time-Tick y método BLE/Manual.',
              summary.sheets['Detalle']?.length ?? 0,
              Icons.format_list_bulleted,
            ),
            const Divider(height: 16),
            _buildSheetRow(
              '3. Sesiones',
              'Historial de sesiones, PIN verbal, Bitmap de 8 bytes y hashes de actas.',
              summary.sheets['Sesiones']?.length ?? 0,
              Icons.history,
            ),
            const Divider(height: 16),
            _buildSheetRow(
              '4. Metadatos',
              'Identificadores del curso, docente, fecha ISO8601 y huella HMAC-SHA256 global.',
              summary.sheets['Metadatos']?.length ?? 0,
              Icons.info_outline,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSheetRow(
    String title,
    String description,
    int rowCount,
    IconData icon,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _uniguajiraBlue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: _uniguajiraBlue),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$rowCount filas',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // BOTÓN INFERIOR: Exportación Oficial Excel (.xlsx)
  // ===========================================================================

  Widget _buildBottomActions(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, -2),
            blurRadius: 6,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isExporting ? null : _exportOfficialExcelWorkbook,
            icon: _isExporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.table_view_rounded),
            label: Text(
              _isExporting
                  ? 'Generando Libro Oficial (.xlsx)...'
                  : 'Exportar Excel Oficial (.xlsx — 4 Hojas)',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF107C41), // Verde Excel oficial
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
