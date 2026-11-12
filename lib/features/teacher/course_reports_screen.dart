import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/models/course_model.dart';
import '../../core/models/session_model.dart';
import '../../data/local/app_database.dart';
import '../../data/services/cloud_sync_service.dart';
import '../../data/services/course_overview_service.dart';
import '../../data/services/excel_report_service.dart';
import '../../data/services/report_share_service.dart';
import '../../ui/ui.dart';

enum _ReportFilter { all, alert, risk }

/// Pantalla de reportes de asistencia para docentes:
/// - Métricas consolidadas: sesiones cerradas, porcentaje promedio y estudiantes en riesgo.
/// - Filtros rápidos: Todos, En alerta y En riesgo.
/// - Lista de estudiantes con resumen de asistencias, faltas y porcentaje.
/// - Exportación y opción para compartir el libro Excel oficial.
class CourseReportsScreen extends StatefulWidget {
  const CourseReportsScreen({
    super.key,
    required this.course,
    this.database,
    this.excelService,
    this.cloudSyncService,
    this.reportShareService,
    this.exportOnOpen = false,
  });

  /// Curso institucional objeto del reporte.
  final CourseModel course;

  /// Base de datos SQLite local opcional para inyección en pruebas.
  final AppDatabase? database;

  /// Servicio generador de reportes Excel opcional.
  final ExcelReportService? excelService;

  /// Servicio de sincronización institucional opcional.
  final CloudSyncService? cloudSyncService;

  /// Servicio para compartir reportes institucionales opcional.
  final ReportShareService? reportShareService;

  /// Si es verdadero, al terminar de cargar los datos exporta el libro oficial una vez.
  final bool exportOnOpen;

  /// Despliega el diálogo de exportación exitosa con las acciones requeridas:
  /// "Compartir" (principal) y "Cerrar".
  static Future<void> showExportSuccessDialog({
    required BuildContext context,
    required String filePath,
    required int fileSizeBytes,
    required String hmacSha256,
    required Future<void> Function() onShare,
  }) async {
    final fileName = p.basename(filePath);
    final sizeKb = (fileSizeBytes / 1024).toStringAsFixed(1);

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogCtx) {
        final colors = UiColors.of(dialogCtx);
        return AlertDialog(
          title: const Text('Excel listo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(fileName, style: UiText.bodyStrong.copyWith(color: colors.ink)),
              const SizedBox(height: UiSpace.xs),
              Text('$sizeKb KB', style: UiText.label.copyWith(color: colors.muted)),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cerrar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                onShare();
              },
              child: const Text('Compartir'),
            ),
          ],
        );
      },
    );
  }

  @override
  State<CourseReportsScreen> createState() => _CourseReportsScreenState();
}

class _CourseReportsScreenState extends State<CourseReportsScreen> {
  late final AppDatabase _database;
  late final ExcelReportService _excelService;
  late final ReportShareService _reportShareService;

  bool _isLoading = true;
  bool _isExporting = false;
  bool _isSharing = false;
  bool _hasExportedOnOpen = false;
  String? _loadError;
  String? _latestExportedFilePath;

  CourseAttendanceSummary? _summary;
  List<SessionModel> _sessions = <SessionModel>[];

  _ReportFilter _currentFilter = _ReportFilter.all;

  @override
  void initState() {
    super.initState();
    _database = widget.database ?? AppDatabase.instance;
    _excelService =
        widget.excelService ?? ExcelReportService(database: _database);
    _reportShareService =
        widget.reportShareService ?? ReportShareService();
    _loadReportData();
  }

  Future<void> _loadReportData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final summary = await _excelService.buildCourseSummary(widget.course.id);
      final sessions = await _database.getSessionsByCourse(widget.course.id);

      if (mounted) {
        setState(() {
          _summary = summary;
          _sessions = sessions;
          _isLoading = false;
        });
        await _checkLatestExportedFile();
        if (widget.exportOnOpen && !_hasExportedOnOpen) {
          _hasExportedOnOpen = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _exportOfficialExcelWorkbook();
            }
          });
        }
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
    final downloadsDir = Directory('/storage/emulated/0/Download');
    if (await downloadsDir.exists()) {
      return downloadsDir.path;
    }

    try {
      final tempDir = Directory(p.join(Directory.systemTemp.path, 'reports'));
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }
      return tempDir.path;
    } catch (e) {
      debugPrint('No se pudo acceder al directorio de reportes: $e');
      return Directory.systemTemp.path;
    }
  }

  Future<void> _checkLatestExportedFile() async {
    try {
      final directoryPath = await _resolveExportDirectory();
      final file = File(
        p.join(directoryPath, ExcelReportService.exportFileNameFor(widget.course)),
      );
      final exists = await file.exists() && await file.length() > 0;
      if (mounted) {
        setState(() => _latestExportedFilePath = exists ? file.path : null);
      }
    } catch (e) {
      debugPrint('Error al verificar último archivo Excel exportado: $e');
      if (mounted) {
        setState(() => _latestExportedFilePath = null);
      }
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
      final summary =
          _summary ?? await _excelService.buildCourseSummary(widget.course.id);
      final hmacSha256 = summary.reportHmacSha256;

      if (!mounted) return;
      setState(() {
        _isExporting = false;
        _latestExportedFilePath = filePath;
      });

      await CourseReportsScreen.showExportSuccessDialog(
        context: context,
        filePath: filePath,
        fileSizeBytes: fileSizeBytes,
        hmacSha256: hmacSha256,
        onShare: () => _shareExportedFile(filePath),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isExporting = false);
      showUiSnack(context, 'No se pudo crear el Excel. Inténtalo de nuevo.');
    }
  }

  Future<void> _shareExportedFile(String filePath) async {
    if (_isSharing) return;

    setState(() => _isSharing = true);

    try {
      final outcome = await _reportShareService.shareReport(
        filePath: filePath,
        courseName: widget.course.name,
      );

      if (!mounted) return;

      if (outcome.isError) {
        showUiSnack(
          context,
          outcome.errorMessage ??
              'No se pudo compartir el reporte. Inténtalo de nuevo.',
        );
      } else if (outcome.isSuccess) {
        showUiSnack(context, 'Reporte compartido exitosamente.');
      }
    } catch (e) {
      if (!mounted) return;
      showUiSnack(
        context,
        'No se pudo compartir el reporte. Inténtalo de nuevo.',
      );
    } finally {
      if (mounted) {
        setState(() => _isSharing = false);
        await _checkLatestExportedFile();
      }
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

  // Mismo criterio que el Excel y que la pantalla de la clase.
  int _countStudentsInLoss(List<StudentAttendanceMetric> students) =>
      students.where(CourseOverviewService.isAtRisk).length;

  int _countStudentsInAlert(List<StudentAttendanceMetric> students) =>
      students.where(CourseOverviewService.isInAlert).length;

  List<StudentAttendanceMetric> _getFilteredStudents(
    List<StudentAttendanceMetric> allStudents,
  ) {
    return allStudents.where((StudentAttendanceMetric s) {
      final isLoss = CourseOverviewService.isAtRisk(s);
      final isAlert = CourseOverviewService.isInAlert(s);

      switch (_currentFilter) {
        case _ReportFilter.alert:
          return isAlert;
        case _ReportFilter.risk:
          return isLoss;
        case _ReportFilter.all:
          return true;
      }
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = UiColors.of(context);

    if (_isLoading) {
      return UiPage(
        header: UiTopBar(
          title: 'Reportes',
          subtitle: widget.course.name,
          onBack: () => Navigator.of(context).pop(),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: UiSpace.lg),
              Text(
                'Cargando reporte…',
                style: UiText.bodyStrong.copyWith(color: colors.ink),
              ),
            ],
          ),
        ),
      );
    }

    if (_loadError != null) {
      return UiPage(
        header: UiTopBar(
          title: 'Reportes',
          subtitle: widget.course.name,
          onBack: () => Navigator.of(context).pop(),
        ),
        body: UiEmptyState(
          icon: Icons.error_outline_rounded,
          title: 'No se pudo cargar el reporte',
          message: _loadError!,
          actionLabel: 'Volver a intentar',
          onAction: _loadReportData,
        ),
      );
    }

    if (_sessions.isEmpty) {
      return UiPage(
        header: UiTopBar(
          title: 'Reportes',
          subtitle: widget.course.name,
          onBack: () => Navigator.of(context).pop(),
        ),
        body: const UiEmptyState(
          icon: Icons.bar_chart_rounded,
          title: 'Aún no hay datos',
          message:
              'Cuando cierres tu primera sesión verás aquí el resumen de la clase.',
        ),
      );
    }

    final summary = _summary;
    final students = summary?.studentMetrics ?? <StudentAttendanceMetric>[];
    final allCount = students.length;
    final alertCount = _countStudentsInAlert(students);
    final lossCount = _countStudentsInLoss(students);
    final avgAttendance = _calculateAverageAttendance(students);
    final filteredStudents = _getFilteredStudents(students);

    final hasLatest = _latestExportedFilePath != null;
    final bottomWidget = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasLatest) ...[
          UiButton(
            label: 'Compartir el último Excel',
            variant: UiButtonVariant.tonal,
            compact: true,
            onPressed: _isExporting || _isSharing
                ? null
                : () => _shareExportedFile(_latestExportedFilePath!),
          ),
          const SizedBox(height: UiSpace.sm),
        ],
        UiButton(
          label: 'Enviar Excel',
          icon: Icons.ios_share_rounded,
          loading: _isExporting,
          onPressed:
              _isExporting || _isSharing ? null : _exportOfficialExcelWorkbook,
        ),
      ],
    );

    return UiPage(
      header: UiTopBar(
        title: 'Reportes',
        subtitle: widget.course.name,
        onBack: () => Navigator.of(context).pop(),
      ),
      bottom: bottomWidget,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: UiSpace.page),
            child: Row(
              children: [
                Expanded(
                  child: UiStatTile(
                    value: '${summary?.totalClosedSessions ?? _sessions.length}',
                    label: 'sesiones',
                  ),
                ),
                const SizedBox(width: UiSpace.sm),
                Expanded(
                  child: UiStatTile(
                    value: '${avgAttendance.toStringAsFixed(0)} %',
                    label: 'asistencia',
                  ),
                ),
                const SizedBox(width: UiSpace.sm),
                Expanded(
                  child: UiStatTile(
                    value: '$lossCount',
                    label: 'en riesgo',
                    tone: lossCount > 0 ? UiTone.absent : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: UiSpace.md),
          UiFilterPills<_ReportFilter>(
            options: [
              UiFilterOption(
                value: _ReportFilter.all,
                label: 'Todos $allCount',
              ),
              UiFilterOption(
                value: _ReportFilter.alert,
                label: 'En alerta $alertCount',
              ),
              UiFilterOption(
                value: _ReportFilter.risk,
                label: 'En riesgo $lossCount',
              ),
            ],
            selected: _currentFilter,
            onSelected: (val) => setState(() => _currentFilter = val),
          ),
          const SizedBox(height: UiSpace.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: UiSpace.page),
              child: Material(
                color: colors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(UiRadius.lg),
                  side: BorderSide(color: colors.line),
                ),
                clipBehavior: Clip.antiAlias,
                child: filteredStudents.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(UiSpace.lg),
                          child: Text(
                            'No hay estudiantes en este grupo',
                            style: UiText.body.copyWith(color: colors.muted),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: filteredStudents.length,
                        separatorBuilder: (context, index) => Divider(
                          height: 1,
                          thickness: 1,
                          color: colors.line,
                        ),
                        itemBuilder: (context, index) {
                          final s = filteredStudents[index];
                          final isLoss = CourseOverviewService.isAtRisk(s);
                          final isAlert = CourseOverviewService.isInAlert(s);

                          final UiTone tone = isLoss
                              ? UiTone.absent
                              : (isAlert ? UiTone.manual : UiTone.tint);

                          final absencesText = s.totalAbsences == 1
                              ? '1 falta'
                              : '${s.totalAbsences} faltas';
                          final subtitleText =
                              'Fue a ${s.totalAttendances} de ${s.totalSessions} · $absencesText';

                          return UiPersonRow(
                            name: s.fullName,
                            subtitle: subtitleText,
                            avatarTone: tone,
                            trailing: UiPill(
                              label:
                                  '${s.attendancePercentage.toStringAsFixed(0)} %',
                              tone: tone,
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
