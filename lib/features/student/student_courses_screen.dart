import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/crypto/ble_packet_codec.dart';
import '../../core/models/student_enrollment_model.dart';
import '../../data/local/app_database.dart';
import '../../data/services/student_enrollment_service.dart';
import '../../theme/theme.dart';
import 'student_live_beacon_screen.dart';
import 'student_qr_enrollment_screen.dart';

/// Pantalla principal de la billetera de cursos enrolados del estudiante.
///
/// Permite:
/// - Visualizar los cursos en los que el estudiante está enrolado localmente.
/// - Consultar su código estudiantil y su posición asignada en el Bitmap (0..63).
/// - Previsualizar la rotación de su token HMAC y configurar el PIN verbal BLE.
/// - Desvincular credenciales locales si es necesario.
/// - Acceder al escáner QR de enrolamiento del primer día de clase.
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

  bool _isLoading = true;
  String? _errorMessage;
  List<StudentEnrollmentModel> _enrollments = <StudentEnrollmentModel>[];

  @override
  void initState() {
    super.initState();
    final db = widget.database ?? AppDatabase.instance;
    _enrollmentService =
        widget.enrollmentService ?? StudentEnrollmentService(db);
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error al cargar cursos enrolados: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _openQrScanner() async {
    final result = await Navigator.of(context).push<StudentEnrollmentModel>(
      MaterialPageRoute<StudentEnrollmentModel>(
        builder: (_) => StudentQrEnrollmentScreen(
          enrollmentService: _enrollmentService,
        ),
      ),
    );

    if (!mounted) return;

    if (result != null) {
      await _loadEnrollments();
      if (!mounted) return;
      final colors = AppColors.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '¡Enrolado exitosamente en ${result.courseName}! '
            'Bit #${result.bitIndex.toString().padLeft(2, '0')}',
          ),
          backgroundColor: colors.statusNormal,
        ),
      );
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

  Future<void> _confirmRemoveEnrollment(
    StudentEnrollmentModel enrollment,
  ) async {
    final colors = AppColors.of(context);
    final radii = AppRadii.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          shape: radii.dialogShape(),
          title: const Text('¿Desvincular curso?'),
          content: Text(
            'Se eliminará tu credencial criptográfica del curso '
            '"${enrollment.courseName}". Para volver a marcar asistencia, '
            'deberás escanear el QR del docente nuevamente.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colors.statusPerdida,
                foregroundColor: colors.onStatusPerdida,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Desvincular'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        await _enrollmentService.removeEnrollment(enrollment.id);
        await _loadEnrollments();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Credencial de "${enrollment.courseName}" desvinculada.',
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al desvincular curso: $e'),
              backgroundColor: colors.statusPerdida,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Cursos Enrolados'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Escanear QR de enrolamiento',
            onPressed: _openQrScanner,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar lista',
            onPressed: _loadEnrollments,
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openQrScanner,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Escanear QR'),
      ),
    );
  }

  Widget _buildBody() {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: spacing.insetsLg,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.error_outline,
                size: 56,
                color: colors.statusPerdida,
              ),
              SizedBox(height: spacing.md),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colors.onSurface,
                ),
              ),
              SizedBox(height: spacing.md),
              FilledButton.icon(
                onPressed: _loadEnrollments,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_enrollments.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: spacing.insetsXl,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  padding: spacing.insetsLg,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.school_outlined,
                    size: 72,
                    color: colors.primary,
                  ),
                ),
                SizedBox(height: spacing.lg),
                Text(
                  'Aún no estás enrolado en ningún curso',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: spacing.sm),
                Text(
                  'Escanea el código QR en el teléfono de tu docente el primer '
                  'día de clase para recibir tu posición en el Mapa de Bits y tu '
                  'semilla criptográfica.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceMuted,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: spacing.xl),
                FilledButton.icon(
                  onPressed: _openQrScanner,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Enrolar Primer Curso'),
                  style: FilledButton.styleFrom(
                    padding: spacing.symmetric(
                      horizontal: spacing.lg,
                      vertical: spacing.sm,
                    ),
                    shape: radii.buttonShape(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadEnrollments,
      child: ListView.builder(
        padding: spacing.only(
          left: spacing.md,
          right: spacing.md,
          top: spacing.md,
          bottom: spacing.xxl + spacing.xl,
        ),
        itemCount: _enrollments.length,
        itemBuilder: (BuildContext context, int index) {
          final enrollment = _enrollments[index];
          return _EnrollmentCard(
            enrollment: enrollment,
            onMarkAttendance: () => _openLiveBeaconScreen(enrollment),
            onRemove: () => _confirmRemoveEnrollment(enrollment),
          );
        },
      ),
    );
  }
}

/// Tarjeta individual de curso enrolado.
class _EnrollmentCard extends StatelessWidget {
  const _EnrollmentCard({
    required this.enrollment,
    required this.onMarkAttendance,
    required this.onRemove,
  });

  final StudentEnrollmentModel enrollment;
  final VoidCallback onMarkAttendance;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    final enrolledDate = DateTime.fromMillisecondsSinceEpoch(
      enrollment.enrolledAtEpochMs,
    );
    final formattedDate = DateFormat('dd/MM/yyyy · HH:mm').format(enrolledDate);

    return Card(
      elevation: 0,
      margin: spacing.only(bottom: spacing.md),
      shape: radii.cardShape(side: BorderSide(color: colors.outlineVariant)),
      child: Padding(
        padding: spacing.insetsCard,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Cabecera: Nombre de la asignatura y código
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  padding: spacing.all(spacing.xs + 2),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: radii.borderMd,
                  ),
                  child: Icon(
                    Icons.menu_book_rounded,
                    color: colors.primary,
                    size: 24,
                  ),
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        enrollment.courseName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.onSurface,
                        ),
                      ),
                      SizedBox(height: spacing.xxs / 2),
                      Container(
                        padding: spacing.symmetric(
                          horizontal: spacing.xs,
                          vertical: spacing.xxs / 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHigh,
                          borderRadius: radii.borderXs,
                        ),
                        child: Text(
                          'Código: ${enrollment.courseCode}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.onSurfaceMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    color: colors.statusPerdida,
                  ),
                  tooltip: 'Desvincular credencial',
                  onPressed: onRemove,
                ),
              ],
            ),
            Divider(height: spacing.lg),

            // Datos del estudiante
            Row(
              children: <Widget>[
                Icon(
                  Icons.person_outline,
                  size: 20,
                  color: colors.primary,
                ),
                SizedBox(width: spacing.xs),
                Expanded(
                  child: Text(
                    enrollment.fullName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.xxs + 2),
            Row(
              children: <Widget>[
                Icon(
                  Icons.badge_outlined,
                  size: 20,
                  color: colors.primary,
                ),
                SizedBox(width: spacing.xs),
                Text(
                  'Código: ${enrollment.studentCode}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w500,
                    color: colors.onSurface,
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.sm),

            // Badge destacado con el Bit asignado en el Bitmap (0..63)
            Container(
              width: double.infinity,
              padding: spacing.symmetric(horizontal: spacing.sm + 2, vertical: spacing.xs + 2),
              decoration: BoxDecoration(
                color: colors.primaryContainer.withValues(alpha: 0.6),
                borderRadius: radii.borderSm,
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.tag_rounded,
                    size: 22,
                    color: colors.primary,
                  ),
                  SizedBox(width: spacing.xs),
                  Expanded(
                    child: Text(
                      'Bit Asignado: #${enrollment.bitIndex.toString().padLeft(2, '0')} (0..63)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.verified_outlined,
                    size: 20,
                    color: colors.primary,
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.xs),

            // Fecha de enrolamiento
            Text(
              'Enrolado el $formattedDate',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceMuted,
              ),
            ),
            SizedBox(height: spacing.md),

            // Botón de acción principal
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onMarkAttendance,
                icon: const Icon(Icons.bluetooth_searching),
                label: const Text('Marcar Asistencia BLE'),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                  padding: spacing.symmetric(vertical: spacing.sm),
                  shape: radii.buttonShape(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Diálogo modal interactivo para previsualizar la asistencia BLE y el token HMAC rotativo.
class StudentBleAttendancePreviewDialog extends StatefulWidget {
  const StudentBleAttendancePreviewDialog({
    super.key,
    required this.enrollment,
  });

  final StudentEnrollmentModel enrollment;

  @override
  State<StudentBleAttendancePreviewDialog> createState() =>
      _StudentBleAttendancePreviewDialogState();
}

class _StudentBleAttendancePreviewDialogState
    extends State<StudentBleAttendancePreviewDialog> {
  late final TextEditingController _pinController;
  Timer? _tickerTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _pinController = TextEditingController();
    _pinController.addListener(() => setState(() {}));
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    final currentTick = BlePacketCodec.computeTimeTick(_now);
    final epochSeconds = _now.millisecondsSinceEpoch ~/ 1000;
    final elapsedInWindow = epochSeconds % AppConstants.hmacWindowSeconds;
    final secondsRemaining = AppConstants.hmacWindowSeconds - elapsedInWindow;
    final progress = secondsRemaining / AppConstants.hmacWindowSeconds;

    final verifyCode = BlePacketCodec.generateAttendanceVerifyCode(
      courseId: widget.enrollment.courseId,
      studentCode: widget.enrollment.studentCode,
      bitIndex: widget.enrollment.bitIndex,
      timeTick: currentTick,
      secretHex: widget.enrollment.deviceSecret,
    );

    final pinText = _pinController.text.trim();
    final isPinValid =
        pinText.length == AppConstants.roomPinLength &&
        int.tryParse(pinText) != null;

    return AlertDialog(
      shape: radii.dialogShape(),
      title: Row(
        children: <Widget>[
          Icon(Icons.bluetooth_searching, color: colors.primary),
          SizedBox(width: spacing.xs),
          const Expanded(
            child: Text(
              'Asistencia BLE · Vista Previa',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Asignatura y estudiante
              Container(
                padding: spacing.insetsSm,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHigh,
                  borderRadius: radii.borderSm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.enrollment.courseName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.onSurface,
                      ),
                    ),
                    SizedBox(height: spacing.xxs / 2),
                    Text(
                      '${widget.enrollment.fullName} · Código: ${widget.enrollment.studentCode}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceMuted,
                      ),
                    ),
                    SizedBox(height: spacing.xxs),
                    Text(
                      'Bit Asignado: #${widget.enrollment.bitIndex.toString().padLeft(2, '0')}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: spacing.md),

              // Campo de PIN verbal de 2 dígitos
              Text(
                'PIN Verbal del Aula (2 dígitos)',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colors.onSurface,
                ),
              ),
              SizedBox(height: spacing.xxs + 2),
              TextField(
                controller: _pinController,
                keyboardType: TextInputType.number,
                maxLength: AppConstants.roomPinLength,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 10,
                  color: colors.onSurface,
                ),
                decoration: InputDecoration(
                  hintText: '00',
                  counterText: '',
                  prefixIcon: const Icon(Icons.pin_outlined),
                  suffixIcon: isPinValid
                      ? Icon(Icons.check_circle, color: colors.statusNormal)
                      : Icon(Icons.info_outline, color: colors.onSurfaceMuted),
                  helperText: 'Dictado en voz alta por el docente en el aula.',
                  helperMaxLines: 2,
                ),
              ),
              SizedBox(height: spacing.md),

              // Tarjeta de previsualización del Token HMAC rotativo
              Container(
                padding: spacing.insetsCard,
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: radii.borderMd,
                  border: Border.all(
                    color: colors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          'SELLO CRIPTOGRÁFICO',
                          style: theme.textTheme.labelSmall?.copyWith(
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.bold,
                            color: colors.primary,
                          ),
                        ),
                        Container(
                          padding: spacing.symmetric(
                            horizontal: spacing.xxs + 2,
                            vertical: spacing.xxs / 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.primary,
                            borderRadius: radii.borderXs,
                          ),
                          child: Text(
                            'Ventana 30s',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onPrimary,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: spacing.xs),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          verifyCode,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                            color: colors.primary,
                          ),
                        ),
                        SizedBox(width: spacing.xs),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 20),
                          tooltip: 'Copiar token',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: verifyCode));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Token copiado al portapapeles'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    SizedBox(height: spacing.xs),
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor: colors.primary.withValues(alpha: 0.15),
                      color: colors.primary,
                      borderRadius: radii.borderXs,
                    ),
                    SizedBox(height: spacing.xxs + 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          'Rotación en ${secondsRemaining}s',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colors.onSurface,
                          ),
                        ),
                        Text(
                          'Tick #$currentTick',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: spacing.sm + 2),

              // Nota informativa
              Container(
                padding: spacing.insetsSm,
                decoration: BoxDecoration(
                  color: colors.secondaryContainer.withValues(alpha: 0.4),
                  borderRadius: radii.borderSm,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: colors.secondary,
                    ),
                    SizedBox(width: spacing.xs),
                    Expanded(
                      child: Text(
                        'Modo previsualización: La emisión BLE publicitaria y '
                        'sincronización con el radar del aula se conecta en tiempo real. '
                        'Tu credencial criptográfica local está activa y verificada.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: colors.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Entendido / Cerrar'),
        ),
      ],
    );
  }
}
