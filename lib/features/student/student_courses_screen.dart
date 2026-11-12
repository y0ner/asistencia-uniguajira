import 'package:flutter/material.dart';

import '../../core/models/student_enrollment_model.dart';
import '../../data/local/app_database.dart';
import '../../data/services/student_enrollment_service.dart';
import '../../ui/ui.dart';
import '../shared/hardware_diagnostic_dialog.dart';
import 'student_live_beacon_screen.dart';
import 'student_qr_enrollment_screen.dart';

/// Pantalla principal de inicio para el estudiante.
///
/// Permite:
/// - Visualizar las clases en las que está inscrito el estudiante.
/// - Marcar asistencia en vivo en una clase mediante Bluetooth.
/// - Salir de una clase desvinculando la credencial local.
/// - Unirse a una nueva clase escaneando el código QR del profesor o pegando el código.
class StudentCoursesScreen extends StatefulWidget {
  const StudentCoursesScreen({
    super.key,
    this.enrollmentService,
    this.database,
  });

  final StudentEnrollmentService? enrollmentService;
  final AppDatabase? database;

  @override
  State<StudentCoursesScreen> createState() => _StudentCoursesScreenState();
}

class _StudentCoursesScreenState extends State<StudentCoursesScreen> {
  late final StudentEnrollmentService _enrollmentService;
  late final AppDatabase _database;

  bool _isLoading = true;
  String? _errorMessage;
  List<StudentEnrollmentModel> _enrollments = <StudentEnrollmentModel>[];

  @override
  void initState() {
    super.initState();
    _database = widget.database ?? AppDatabase.instance;
    _enrollmentService =
        widget.enrollmentService ?? StudentEnrollmentService(_database);
    _loadEnrollments();
  }

  Future<void> _loadEnrollments() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final enrollments = await _enrollmentService.getEnrolledCourses();

      if (!mounted) return;
      setState(() {
        _enrollments = enrollments;
        _isLoading = false;
      });
    } catch (e, st) {
      debugPrint('Error al cargar clases: $e\n$st');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'No se pudieron cargar tus clases.';
        _isLoading = false;
      });
    }
  }

  Future<void> _openQrScanner() async {
    final result = await Navigator.of(context).push<StudentEnrollmentModel>(
      MaterialPageRoute<StudentEnrollmentModel>(
        builder: (_) => StudentQrEnrollmentScreen(
          enrollmentService: _enrollmentService,
          database: _database,
        ),
      ),
    );

    if (!mounted) return;

    if (result != null) {
      await _loadEnrollments();
      if (!mounted) return;
      showUiSnack(context, 'Ya estás en ${result.courseName}.');
    }
  }

  Future<void> _openLiveBeaconScreen(StudentEnrollmentModel enrollment) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => StudentLiveBeaconScreen(
          enrollment: enrollment,
        ),
      ),
    );
  }

  Future<void> _showCourseOptionsSheet(
    StudentEnrollmentModel enrollment,
  ) async {
    final subtitle = _buildSubtitle(enrollment);

    await showUiSheet<void>(
      context,
      builder: (sheetContext) {
        final c = UiColors.of(sheetContext);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: UiSpace.sm),
            Text(
              enrollment.courseName,
              style: UiText.h2.copyWith(color: c.ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: UiSpace.xs),
            Text(
              subtitle,
              style: UiText.label.copyWith(color: c.muted),
            ),
            const SizedBox(height: UiSpace.lg),
            InkWell(
              onTap: () {
                Navigator.of(sheetContext).pop();
                _confirmRemoveEnrollment(enrollment);
              },
              borderRadius: BorderRadius.circular(UiRadius.md),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: UiSize.touch),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: UiSpace.sm),
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, color: c.absentText),
                      const SizedBox(width: UiSpace.md),
                      Text(
                        'Salir de esta clase',
                        style: UiText.bodyStrong.copyWith(color: c.absentText),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmRemoveEnrollment(
    StudentEnrollmentModel enrollment,
  ) async {
    final confirmed = await showUiConfirm(
      context,
      title: '¿Salir de esta clase?',
      message: 'Para volver tendrás que pedirle el código a tu profesor.',
      confirmLabel: 'Salir',
      destructive: true,
    );

    if (confirmed == true) {
      try {
        await _enrollmentService.removeEnrollment(enrollment.id);
        await _loadEnrollments();
        if (mounted) {
          showUiSnack(context, 'Saliste de la clase.');
        }
      } catch (e, st) {
        debugPrint('Error al salir de la clase: $e\n$st');
        if (mounted) {
          showUiSnack(context, 'No se pudo salir de la clase.');
        }
      }
    }
  }

  // El celular del estudiante no guarda las clases del docente: solo se
  // conoce el código que trae la inscripción.
  String _buildSubtitle(StudentEnrollmentModel enrollment) => enrollment.courseCode;

  String _computeOverline(DateTime now) {
    if (_enrollments.isNotEmpty) {
      final raw = _enrollments.first.fullName.trim();
      if (raw.isNotEmpty) {
        final firstWord = raw.split(RegExp(r'\s+')).first;
        if (firstWord.isNotEmpty) {
          final capitalized =
              firstWord[0].toUpperCase() + firstWord.substring(1).toLowerCase();
          return 'Hola, $capitalized';
        }
      }
    }
    return UiFormat.longDate(now);
  }

  Widget _buildEnrollmentCard(StudentEnrollmentModel enrollment, int index) {
    final c = UiColors.of(context);
    final subtitle = _buildSubtitle(enrollment);

    return UiCard(
      radius: 22,
      padding: const EdgeInsets.all(UiSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              UiAvatar(name: enrollment.courseName, square: true),
              const SizedBox(width: UiSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      enrollment.courseName,
                      style: UiText.title.copyWith(color: c.ink),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: UiText.label.copyWith(color: c.muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: UiSpace.sm),
              UiRoundIconButton(
                icon: Icons.more_horiz_rounded,
                tooltip: 'Opciones de la clase',
                onPressed: () => _showCourseOptionsSheet(enrollment),
              ),
            ],
          ),
          const SizedBox(height: UiSpace.md),
          UiButton(
            label: 'Marcar asistencia',
            compact: true,
            variant:
                index == 0 ? UiButtonVariant.primary : UiButtonVariant.tonal,
            onPressed: () => _openLiveBeaconScreen(enrollment),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    final Widget body;
    if (_isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_errorMessage != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: UiSpace.page),
          child: UiBanner(
            tone: UiBannerTone.error,
            message: _errorMessage!,
            actionLabel: 'Volver a intentar',
            onAction: _loadEnrollments,
          ),
        ),
      );
    } else if (_enrollments.isEmpty) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UiPageHeading(
            overline: UiFormat.longDate(now),
            title: '¿A qué clase llegaste?',
          ),
          Expanded(
            child: UiEmptyState(
              icon: Icons.qr_code_scanner_rounded,
              title: 'Aún no estás en ninguna clase',
              message:
                  'Pídele a tu profesor el código QR de la clase y únete.',
              actionLabel: 'Unirme a una clase',
              onAction: _openQrScanner,
            ),
          ),
        ],
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _loadEnrollments,
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: UiSpace.xxl),
          itemCount: _enrollments.length + 1,
          itemBuilder: (BuildContext context, int index) {
            if (index == 0) {
              return UiPageHeading(
                overline: _computeOverline(now),
                title: '¿A qué clase llegaste?',
              );
            }
            final enrollment = _enrollments[index - 1];
            return Padding(
              padding: const EdgeInsets.fromLTRB(
                UiSpace.page,
                0,
                UiSpace.page,
                UiSpace.md,
              ),
              child: _buildEnrollmentCard(enrollment, index - 1),
            );
          },
        ),
      );
    }

    return UiPage(
      header: UiBrandHeader(
        trailing: UiRoundIconButton(
          icon: Icons.tune_rounded,
          tooltip: 'Ajustes y diagnóstico',
          onPressed: () => showHardwareDiagnosticDialog(context),
        ),
      ),
      bottom: _isLoading || _errorMessage != null || _enrollments.isEmpty
          ? null
          : UiButton(
              label: 'Unirme a una clase',
              icon: Icons.qr_code_scanner_rounded,
              variant: UiButtonVariant.outline,
              onPressed: _openQrScanner,
            ),
      body: body,
    );
  }
}
