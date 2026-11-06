import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/crypto/ble_packet_codec.dart';
import '../../core/models/student_enrollment_model.dart';
import '../../data/local/app_database.dart';
import '../../data/services/student_enrollment_service.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '¡Enrolado exitosamente en ${result.courseName}! '
            'Bit #${result.bitIndex.toString().padLeft(2, '0')}',
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    }
  }

  Future<void> _confirmRemoveEnrollment(
    StudentEnrollmentModel enrollment,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          icon: Icon(
            Icons.warning_amber_rounded,
            color: theme.colorScheme.error,
            size: 40,
          ),
          title: const Text('¿Desvincular credencial?'),
          content: Text(
            'Esta acción eliminará tu credencial local y semilla criptográfica '
            'del curso "${enrollment.courseName}".\n\n'
            'Perderás tu posición asignada (Bit #${enrollment.bitIndex.toString().padLeft(2, '0')}) '
            'y deberás escanear nuevamente el código QR con el docente.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Desvincular'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    if (confirmed == true) {
      try {
        await _enrollmentService.removeEnrollment(enrollment.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Credencial de "${enrollment.courseName}" eliminada correctamente.',
            ),
          ),
        );
        await _loadEnrollments();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al desvincular credencial: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _showBleAttendanceDialog(StudentEnrollmentModel enrollment) {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        return StudentBleAttendancePreviewDialog(enrollment: enrollment);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Cursos Enrolados'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _loadEnrollments,
          ),
        ],
      ),
      body: _buildBody(theme),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openQrScanner,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Enrolar Curso (Escanear QR)'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.error_outline,
                size: 56,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
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
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(
                      alpha: 0.3,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.school_outlined,
                    size: 72,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Aún no estás enrolado en ningún curso',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Escanea el código QR en el teléfono de tu docente el primer '
                  'día de clase para recibir tu posición en el Mapa de Bits y tu '
                  'semilla criptográfica.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: _openQrScanner,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Enrolar Primer Curso'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
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
        padding: const EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 88,
        ),
        itemCount: _enrollments.length,
        itemBuilder: (BuildContext context, int index) {
          final enrollment = _enrollments[index];
          return _EnrollmentCard(
            enrollment: enrollment,
            onMarkAttendance: () => _showBleAttendanceDialog(enrollment),
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
    final enrolledDate = DateTime.fromMillisecondsSinceEpoch(
      enrollment.enrolledAtEpochMs,
    );
    final formattedDate = DateFormat('dd/MM/yyyy · HH:mm').format(enrolledDate);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Cabecera: Nombre de la asignatura y código
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.menu_book_rounded,
                    color: theme.colorScheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        enrollment.courseName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Código: ${enrollment.courseCode}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    color: theme.colorScheme.error,
                  ),
                  tooltip: 'Desvincular credencial',
                  onPressed: onRemove,
                ),
              ],
            ),
            const Divider(height: 20),

            // Datos del estudiante
            Row(
              children: <Widget>[
                Icon(
                  Icons.person_outline,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    enrollment.fullName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Icon(
                  Icons.badge_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Código: ${enrollment.studentCode}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Badge destacado con el Bit asignado en el Bitmap (0..63)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.6,
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.tag_rounded,
                    size: 22,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bit Asignado: #${enrollment.bitIndex.toString().padLeft(2, '0')} (0..63)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.verified_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Fecha de enrolamiento
            Text(
              'Enrolado el $formattedDate',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),

            // Botón de acción principal
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onMarkAttendance,
                icon: const Icon(Icons.bluetooth_searching),
                label: const Text('Marcar Asistencia BLE'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
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
      title: Row(
        children: <Widget>[
          Icon(Icons.bluetooth_searching, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
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
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.enrollment.courseName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.enrollment.fullName} · Código: ${widget.enrollment.studentCode}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Bit Asignado: #${widget.enrollment.bitIndex.toString().padLeft(2, '0')}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Campo de PIN verbal de 2 dígitos
              Text(
                'PIN Verbal del Aula (2 dígitos)',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
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
                ),
                decoration: InputDecoration(
                  hintText: '00',
                  counterText: '',
                  prefixIcon: const Icon(Icons.pin_outlined),
                  suffixIcon: isPinValid
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : const Icon(Icons.info_outline, color: Colors.grey),
                  border: const OutlineInputBorder(),
                  helperText: 'Dictado en voz alta por el docente en el aula.',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 16),

              // Tarjeta de previsualización del Token HMAC rotativo
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
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
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Ventana 30s',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onPrimary,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          verifyCode,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
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
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor: theme.colorScheme.primary.withValues(
                        alpha: 0.15,
                      ),
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          'Rotación en ${secondsRemaining}s',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Tick #$currentTick',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Nota informativa
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: theme.colorScheme.secondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Modo previsualización: La emisión BLE publicitaria y '
                        'sincronización con el radar del aula se conectará en la Etapa 3. '
                        'Tu credencial criptográfica local está activa y verificada.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: theme.colorScheme.onSecondaryContainer,
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
