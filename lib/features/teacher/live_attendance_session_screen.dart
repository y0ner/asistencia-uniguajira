import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/crypto/ble_packet_codec.dart';
import '../../core/models/attendance_record_model.dart';
import '../../core/models/course_model.dart';
import '../../core/models/student_model.dart';
import '../../data/local/app_database.dart';
import '../../data/services/attendance_session_controller.dart';
import '../../data/services/ble_attendance_service.dart';
import '../../theme/theme.dart';
import 'signed_acta_dialog.dart';

/// Pantalla de Sesión de Asistencia Docente en Vivo:
/// - Cabecera con PIN Verbal de 2 dígitos y visualizador en tiempo real del Mapa de Bits (64 bits / 8 bytes).
/// - Pestaña 1: Radar BLE en vivo con confirmación criptográfica y simulador de prueba.
/// - Pestaña 2: Lista invertida a 1 toque con priorización de pendientes y buscador rápido.
/// - Cierre y firma criptográfica de acta con HMAC-SHA256.
class LiveAttendanceSessionScreen extends StatefulWidget {
  const LiveAttendanceSessionScreen({
    super.key,
    required this.course,
    this.database,
    this.controller,
    this.bleService,
    this.customPin,
  });

  /// Curso sobre el cual se realiza la toma de asistencia.
  final CourseModel course;

  /// Base de datos local SQLite inyectable para pruebas.
  final AppDatabase? database;

  /// Controlador de sesión inyectable para pruebas.
  final AttendanceSessionController? controller;

  /// Servicio BLE inyectable para pruebas.
  final BleAttendanceService? bleService;

  /// PIN verbal personalizado de prueba (10..99).
  final int? customPin;

  @override
  State<LiveAttendanceSessionScreen> createState() =>
      _LiveAttendanceSessionScreenState();
}

class _LiveAttendanceSessionScreenState
    extends State<LiveAttendanceSessionScreen>
    with SingleTickerProviderStateMixin {
  late final AppDatabase _database;
  late final BleAttendanceService _bleService;
  late final AttendanceSessionController _controller;
  late final bool _ownsController;
  late final TabController _tabController;

  bool _isStarting = true;
  bool _isClosing = false;
  String? _initError;

  List<StudentModel> _students = <StudentModel>[];
  Map<String, AttendanceRecordModel> _recordsByStudentId =
      <String, AttendanceRecordModel>{};

  StreamSubscription<BlePacketEvent>? _bleEventsSub;
  Timer? _periodicRefreshTimer;

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _database = widget.database ?? AppDatabase.instance;
    _bleService = widget.bleService ?? BleAttendanceService();
    if (widget.controller != null) {
      _controller = widget.controller!;
      _ownsController = false;
    } else {
      _controller = AttendanceSessionController(
        database: _database,
        bleService: _bleService,
      );
      _ownsController = true;
    }

    _initializeSession();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _periodicRefreshTimer?.cancel();
    _bleEventsSub?.cancel();
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  Future<void> _initializeSession() async {
    setState(() {
      _isStarting = true;
      _initError = null;
    });

    try {
      final studentsList =
          await _database.getStudentsByCourse(widget.course.id);
      studentsList.sort(
        (StudentModel a, StudentModel b) => a.bitIndex.compareTo(b.bitIndex),
      );

      // Si el controlador ya tiene una sesión abierta para este curso, la reutilizamos;
      // en caso contrario, abrimos una nueva sesión.
      if (_controller.state == null || !_controller.state!.isOpen) {
        await _controller.startTeacherSession(
          course: widget.course,
          customPin: widget.customPin,
        );
      }

      final active = _controller.state;
      if (active != null) {
        final records =
            await _database.getAttendanceRecordsBySession(active.sessionId);
        _recordsByStudentId = <String, AttendanceRecordModel>{
          for (final AttendanceRecordModel r in records) r.studentId: r,
        };
      }

      // Escuchamos el stream de paquetes BLE para refrescar registros automáticamente
      _bleEventsSub = _bleService.packetEvents.listen((_) {
        // Le damos un breve margen al controller para que aplique la transacción en SQLite
        Future<void>.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            _reloadRecords();
          }
        });
      });

      // Polling ligero cada 1.5s para mantener sincronizado el Bitmap y la base de datos
      _periodicRefreshTimer = Timer.periodic(
        const Duration(milliseconds: 1500),
        (_) {
          if (mounted && !_isClosing) {
            _reloadRecords();
          }
        },
      );

      if (mounted) {
        setState(() {
          _students = studentsList;
          _isStarting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _initError = e.toString();
          _isStarting = false;
        });
      }
    }
  }

  Future<void> _reloadRecords() async {
    final active = _controller.state;
    if (active == null) {
      return;
    }
    try {
      final records =
          await _database.getAttendanceRecordsBySession(active.sessionId);
      if (mounted) {
        setState(() {
          _recordsByStudentId = <String, AttendanceRecordModel>{
            for (final AttendanceRecordModel r in records) r.studentId: r,
          };
        });
      }
    } catch (_) {
      // Ignoramos errores transitorios de lectura mientras se ejecutan transacciones
    }
  }

  Future<void> _handleToggleManual(
    StudentModel student,
    bool isPresent, {
    String? observation,
  }) async {
    try {
      await _controller.toggleManualAttendance(
        studentId: student.id,
        isPresent: isPresent,
        observation: observation,
      );
      await _reloadRecords();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cambiar asistencia manual: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _showObservationDialog(StudentModel student) async {
    final currentRecord = _recordsByStudentId[student.id];
    final textController =
        TextEditingController(text: currentRecord?.observation ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Text('Observación: ${student.fullName}'),
          content: TextField(
            controller: textController,
            decoration: const InputDecoration(
              hintText: 'Ej. Sin smartphone, batería agotada, iPhone sin app...',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            autofocus: true,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      final obs = textController.text.trim();
      await _handleToggleManual(
        student,
        true,
        observation: obs.isEmpty ? null : obs,
      );
    }
  }

  Future<void> _simulateBleArrival(StudentModel student) async {
    final state = _controller.state;
    if (state == null || !state.isOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay una sesión activa para simular.'),
        ),
      );
      return;
    }

    try {
      final now = DateTime.now();
      final timeTick = BlePacketCodec.computeTimeTick(now);
      final packet16 = BlePacketCodec.buildStudentBeaconBytes(
        courseId: widget.course.id,
        bitIndex: student.bitIndex,
        sessionPin: state.pin,
        secretHex: student.personalSecret,
        timeTick: timeTick,
      );

      final outcome = await _controller.processIncomingStudentPacket(
        packet16: packet16,
        rssi: -62,
        nowOverride: now,
      );

      if (!mounted) return;

      if (outcome.isAccepted) {
        await _reloadRecords();
        if (!mounted) return;
        final colors = AppColors.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '¡Llegada BLE confirmada! ${student.fullName} (Bit #${student.bitIndex.toString().padLeft(2, '0')}) '
              'Token: ${outcome.verifyCode}',
            ),
            backgroundColor: colors.statusNormal,
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        final colors = AppColors.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Rechazo criptográfico: ${outcome.failureReason ?? "Firma no válida"}',
            ),
            backgroundColor: colors.statusPerdida,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final colors = AppColors.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al simular llegada BLE: $e'),
          backgroundColor: colors.statusPerdida,
        ),
      );
    }
  }

  void _openSimulationPicker() {
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    final pendingStudents = _students
        .where((StudentModel s) => !_recordsByStudentId.containsKey(s.id))
        .toList(growable: false);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: radii.modalShape(),
      builder: (BuildContext ctx) {
        final theme = Theme.of(ctx);

        if (pendingStudents.isEmpty) {
          return Padding(
            padding: spacing.insetsLg,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.check_circle_outline,
                  color: colors.statusNormal,
                  size: 48,
                ),
                SizedBox(height: spacing.sm),
                Text(
                  'Todos los estudiantes están presentes',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: spacing.xs),
                const Text(
                  'No hay estudiantes pendientes por detectar en esta sesión.',
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: spacing.md),
                FilledButton(
                  style: FilledButton.styleFrom(shape: radii.buttonShape()),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cerrar'),
                ),
              ],
            ),
          );
        }

        return SafeArea(
          child: Padding(
            padding: spacing.symmetric(horizontal: spacing.md, vertical: spacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.science, color: colors.primary),
                    SizedBox(width: spacing.xs),
                    Text(
                      'Simulador de Anuncio BLE',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                SizedBox(height: spacing.xxs),
                Text(
                  'Selecciona un estudiante para inyectar su paquete de 16 bytes firmado con su clave HMAC real (RSSI: -62 dBm).',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceMuted,
                  ),
                ),
                SizedBox(height: spacing.sm),
                // Botón rápido para simular el primer pendiente
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _simulateBleArrival(pendingStudents.first);
                    },
                    icon: const Icon(Icons.bolt),
                    label: Text(
                      'Simular Primero: ${pendingStudents.first.fullName}',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.statusNormal,
                      foregroundColor: colors.onStatusNormal,
                      shape: radii.buttonShape(),
                    ),
                  ),
                ),
                Divider(height: spacing.lg),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: pendingStudents.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (BuildContext _, int index) {
                      final student = pendingStudents[index];
                      final bitPadded =
                          student.bitIndex.toString().padLeft(2, '0');
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: colors.primaryContainer,
                          child: Text(
                            bitPadded,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: colors.onPrimaryContainer,
                            ),
                          ),
                        ),
                        title: Text(
                          student.fullName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text('Cód: ${student.studentCode}'),
                        trailing: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _simulateBleArrival(student);
                          },
                          icon: const Icon(Icons.sensors, size: 16),
                          label: const Text('Simular'),
                          style: ElevatedButton.styleFrom(
                            shape: radii.buttonShape(),
                            padding: spacing.symmetric(
                              horizontal: spacing.xs,
                              vertical: spacing.xxs,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleCloseAndSignSession() async {
    final state = _controller.state;
    if (state == null || !state.isOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La sesión ya ha sido cerrada.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        final theme = Theme.of(ctx);
        final presentCount = _recordsByStudentId.length;
        final totalCount = _students.length;

        return AlertDialog(
          icon: Icon(
            Icons.lock_clock,
            size: 40,
            color: theme.colorScheme.primary,
          ),
          title: const Text('¿Cerrar y Firmar Sesión?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Al cerrar la sesión se detendrá el radar BLE, se consolidará el Mapa de Bits final y se generará el Acta Criptográfica firmada con HMAC-SHA256.',
              ),
              const SizedBox(height: 12),
              Container(
                padding: AppSpacing.of(context).insetsSm,
                decoration: BoxDecoration(
                  color: AppColors.of(context).surfaceContainerHigh,
                  borderRadius: AppRadii.of(context).borderSm,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    const Text('Resumen actual:'),
                    Text(
                      '$presentCount presentes / $totalCount matriculados',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                shape: AppRadii.of(context).buttonShape(),
              ),
              child: const Text('Cerrar y Firmar Acta'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _isClosing = true);

    try {
      final signedActa = await _controller.closeAndSignSession();
      if (!mounted) return;

      setState(() => _isClosing = false);

      // Muestra el modal con el Acta Criptográfica Oficial
      await SignedActaDialog.show(
        context,
        acta: signedActa,
        courseSecretHex: widget.course.courseSecret,
      );

      if (!mounted) return;

      // Volvemos al detalle del curso indicando que la sesión concluyó exitosamente
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isClosing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cerrar y firmar la sesión: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    if (_isStarting) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Sesión BLE: ${widget.course.name}'),
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const CircularProgressIndicator(),
              SizedBox(height: spacing.md),
              const Text(
                'Inicializando Radar BLE y Mapa de Bits...',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }

    if (_initError != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.course.name),
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
        ),
        body: Center(
          child: Padding(
            padding: spacing.insetsLg,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.error_outline, size: 48, color: colors.statusPerdida),
                SizedBox(height: spacing.md),
                Text(
                  'Error al iniciar sesión',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: spacing.xs),
                Text(_initError!, textAlign: TextAlign.center),
                SizedBox(height: spacing.md),
                FilledButton(
                  style: FilledButton.styleFrom(shape: radii.buttonShape()),
                  onPressed: _initializeSession,
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final activeState = _controller.state;
    final pinStr = activeState?.sessionPin ??
        (widget.customPin?.toString().padLeft(2, '0') ?? '00');
    final bitmapHex = activeState?.bitmapHex ?? AppConstants.emptyBitmapHex;

    // Métricas en tiempo real
    var presentBleCount = 0;
    var presentManualCount = 0;
    for (final record in _recordsByStudentId.values) {
      if (record.method == AppConstants.attendanceMethodBleHmac) {
        presentBleCount++;
      } else {
        presentManualCount++;
      }
    }
    final totalPresent = presentBleCount + presentManualCount;
    final totalEnrolled = _students.length;
    final absentCount = totalEnrolled - totalPresent;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        final shouldLeave = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: const Text('¿Salir de la sesión en vivo?'),
            content: const Text(
              'La sesión permanecerá abierta en segundo plano. Podrás volver a ella o cerrarla firmando el acta.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Continuar aquí'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Salir'),
              ),
            ],
          ),
        );
        if (shouldLeave == true && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.course.name),
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refrescar estado',
              onPressed: _reloadRecords,
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            // Cabecera de Sesión Activa: PIN + Mapa de Bits + Contadores
            _buildActiveSessionHeader(
              theme: theme,
              pinStr: pinStr,
              bitmapHex: bitmapHex,
              presentBleCount: presentBleCount,
              presentManualCount: presentManualCount,
              absentCount: absentCount,
              totalPresent: totalPresent,
              totalEnrolled: totalEnrolled,
            ),

            // TabBar con las dos pestañas principales
            Container(
              color: colors.surface,
              child: TabBar(
                controller: _tabController,
                indicatorColor: colors.primary,
                labelColor: colors.primary,
                unselectedLabelColor: colors.onSurfaceMuted,
                tabs: <Widget>[
                  Tab(
                    icon: const Icon(Icons.sensors),
                    text: 'Radar BLE en Vivo ($presentBleCount)',
                  ),
                  Tab(
                    icon: const Icon(Icons.checklist_rtl),
                    text: 'Lista Invertida ($absentCount)',
                  ),
                ],
              ),
            ),

            // Vista de las dos pestañas
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: <Widget>[
                  // Pestaña 1: Radar BLE en Vivo
                  _buildRadarBleTab(theme),

                  // Pestaña 2: Lista Invertida (1 Toque)
                  _buildInvertedListTab(theme),
                ],
              ),
            ),

            // Barra Inferior con Botón de Cierre y Firma
            _buildBottomActionBar(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveSessionHeader({
    required ThemeData theme,
    required String pinStr,
    required String bitmapHex,
    required int presentBleCount,
    required int presentManualCount,
    required int absentCount,
    required int totalPresent,
    required int totalEnrolled,
  }) {
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    final active = _controller.state;
    final bleWarning = _controller.bleWarning;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(
            color: colors.outlineVariant,
          ),
        ),
      ),
      child: Column(
        children: <Widget>[
          // Alerta no bloqueante si hay advertencias de hardware BLE
          if (bleWarning != null && bleWarning.isNotEmpty)
            Container(
              width: double.infinity,
              padding: spacing.symmetric(horizontal: spacing.md, vertical: spacing.xxs),
              color: colors.statusAlertaContainer,
              child: Row(
                children: <Widget>[
                  Icon(Icons.warning_amber, size: 16, color: colors.statusAlerta),
                  SizedBox(width: spacing.xs),
                  Expanded(
                    child: Text(
                      bleWarning,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onStatusAlertaContainer,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

          Padding(
            padding: spacing.fromLTRB(spacing.md, spacing.sm, spacing.md, spacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // PIN Verbal de Aula en Grande y Llamativo
                Container(
                  padding: spacing.symmetric(
                    horizontal: spacing.md,
                    vertical: spacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: radii.borderLg,
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: colors.primary.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            Icons.record_voice_over,
                            color: colors.onPrimary.withValues(alpha: 0.7),
                            size: 14,
                          ),
                          SizedBox(width: spacing.xxs),
                          Text(
                            'PIN DE AULA',
                            style: TextStyle(
                              color: colors.onPrimary.withValues(alpha: 0.7),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: spacing.xxs / 2),
                      Text(
                        pinStr,
                        style: TextStyle(
                          color: colors.onPrimary,
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'monospace',
                          letterSpacing: 2,
                        ),
                      ),
                      Text(
                        'Dilo en voz alta',
                        style: TextStyle(
                          color: colors.onPrimary.withValues(alpha: 0.6),
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: spacing.sm),

                // Visualizador del Mapa de Bits de 64 posiciones en tiempo real
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text(
                            'Mapa de Bits 64-Bit',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '0x$bitmapHex',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: totalPresent > 0
                                  ? colors.statusNormal
                                  : colors.onSurfaceMuted,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: spacing.xxs),
                      // Cuadrícula compacta de 64 celdas (4 filas x 16 columnas)
                      _buildBitmapGrid(active, theme),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Barra de Contadores en vivo
          Container(
            padding: spacing.symmetric(horizontal: spacing.md, vertical: spacing.xs),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              border: Border(
                top: BorderSide(
                  color: colors.outlineVariant,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: <Widget>[
                _buildLiveBadge(
                  label: 'BLE',
                  count: presentBleCount,
                  color: colors.statusNormal,
                  icon: Icons.bluetooth_connected,
                ),
                _buildLiveBadge(
                  label: 'Manual',
                  count: presentManualCount,
                  color: colors.manualAccent,
                  icon: Icons.touch_app,
                ),
                _buildLiveBadge(
                  label: 'Pendientes',
                  count: absentCount,
                  color: colors.statusPerdida,
                  icon: Icons.person_off,
                ),
                _buildLiveBadge(
                  label: 'Total',
                  countStr: '$totalPresent / $totalEnrolled',
                  color: colors.primary,
                  icon: Icons.groups,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBitmapGrid(ActiveCourseSessionState? active, ThemeData theme) {
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);
    final bitmap8 = active?.bitmap8;

    return Container(
      padding: spacing.insetsXxs,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: radii.borderSm,
        border: Border.all(
          color: colors.outlineVariant,
        ),
      ),
      child: Column(
        children: List<Widget>.generate(4, (int rowIndex) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List<Widget>.generate(16, (int colIndex) {
              final bitIndex = rowIndex * 16 + colIndex;
              final isEnrolled = active?.studentByBitIndex.containsKey(bitIndex) ?? false;
              final isSet = bitmap8 != null &&
                  BlePacketCodec.isStudentBitSet(bitmap8, bitIndex);

              Color cellColor;
              if (isSet) {
                cellColor = colors.statusNormal;
              } else if (isEnrolled) {
                cellColor = colors.surfaceContainerHigh;
              } else {
                cellColor = Colors.transparent;
              }

              final student = active?.studentByBitIndex[bitIndex];
              final tooltipMessage = student != null
                  ? 'Bit #$bitIndex: ${student.fullName} (${isSet ? "Presente" : "Pendiente"})'
                  : 'Bit #$bitIndex: Vacante';

              return Tooltip(
                message: tooltipMessage,
                child: Container(
                  width: 14,
                  height: 14,
                  margin: spacing.all(1),
                  decoration: BoxDecoration(
                    color: cellColor,
                    borderRadius: radii.borderXs,
                    border: Border.all(
                      color: isSet
                          ? colors.statusNormal
                          : (isEnrolled
                              ? colors.outline
                              : colors.outlineVariant),
                      width: 0.6,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    bitIndex.toString(),
                    style: TextStyle(
                      fontSize: 7,
                      fontWeight: FontWeight.bold,
                      color: isSet
                          ? colors.onStatusNormal
                          : (isEnrolled ? colors.onSurface : colors.outlineVariant),
                    ),
                  ),
                ),
              );
            }),
          );
        }),
      ),
    );
  }

  Widget _buildLiveBadge({
    required String label,
    int? count,
    String? countStr,
    required Color color,
    required IconData icon,
  }) {
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final displayValue = countStr ?? count.toString();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 14, color: color),
        SizedBox(width: spacing.xxs),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            color: colors.onSurfaceMuted,
          ),
        ),
        Text(
          displayValue,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Pestaña 1: Radar BLE en Vivo
  // ---------------------------------------------------------------------------

  Widget _buildRadarBleTab(ThemeData theme) {
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    final bleStudents = _students.where((StudentModel s) {
      final r = _recordsByStudentId[s.id];
      return r != null && r.method == AppConstants.attendanceMethodBleHmac;
    }).toList(growable: false);

    return ListView(
      padding: spacing.insetsMd,
      children: <Widget>[
        // Tarjeta de Radar Activo
        Container(
          padding: spacing.insetsMd,
          decoration: BoxDecoration(
            color: colors.statusNormalContainer.withValues(alpha: 0.35),
            borderRadius: radii.borderMd,
            border: Border.all(color: colors.statusNormal.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    padding: spacing.insetsXs,
                    decoration: BoxDecoration(
                      color: colors.statusNormal,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.sensors,
                      color: colors.onStatusNormal,
                      size: 20,
                    ),
                  ),
                  SizedBox(width: spacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Radar BLE Activo',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: colors.onSurface,
                          ),
                        ),
                        Text(
                          'Emitiendo Eco (16 bytes) y escuchando Beacons (RSSI >= -75 dBm)',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.onStatusNormalContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: spacing.sm),
              // Botón para Simular Llegada BLE
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _openSimulationPicker,
                  icon: const Icon(Icons.bolt),
                  label: const Text('Simular Llegada BLE (Demo/Test)'),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.statusNormal,
                    foregroundColor: colors.onStatusNormal,
                    shape: radii.buttonShape(),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: spacing.md),

        // Encabezado de la lista
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              'Confirmados por Bluetooth (${bleStudents.length})',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Criptografía HMAC-SHA256',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceMuted,
              ),
            ),
          ],
        ),
        SizedBox(height: spacing.xs),

        if (bleStudents.isEmpty)
          _buildEmptyBleView(theme)
        else
          ...bleStudents.map((StudentModel student) {
            final record = _recordsByStudentId[student.id];
            return _buildBleStudentTile(theme, student, record);
          }),
      ],
    );
  }

  Widget _buildEmptyBleView(ThemeData theme) {
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);

    return Container(
      padding: spacing.symmetric(vertical: spacing.xl, horizontal: spacing.lg),
      alignment: Alignment.center,
      child: Column(
        children: <Widget>[
          Icon(
            Icons.radar,
            size: 54,
            color: colors.onSurfaceMuted.withValues(alpha: 0.5),
          ),
          SizedBox(height: spacing.sm),
          Text(
            'Esperando anuncios BLE de estudiantes',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: spacing.xxs),
          Text(
            'Pide a los estudiantes ingresar el PIN del aula en su app. '
            'Aparecerán aquí con su token UG-XXXXXXXX una vez confirmados.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceMuted,
            ),
          ),
          SizedBox(height: spacing.sm),
          TextButton.icon(
            onPressed: _openSimulationPicker,
            icon: const Icon(Icons.science_outlined),
            label: const Text('Probar con simulador'),
          ),
        ],
      ),
    );
  }

  Widget _buildBleStudentTile(
    ThemeData theme,
    StudentModel student,
    AttendanceRecordModel? record,
  ) {
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    final bitPadded = student.bitIndex.toString().padLeft(2, '0');
    final rssiInt = record?.rssiAvg?.round() ?? -60;
    final token = record?.hmacTag ?? 'UG-????????';

    return Card(
      elevation: 0,
      margin: spacing.only(bottom: spacing.xs),
      shape: radii.cardShape(
        side: BorderSide(color: colors.statusNormal.withValues(alpha: 0.3)),
      ),
      color: colors.statusNormalContainer.withValues(alpha: 0.25),
      child: Padding(
        padding: spacing.insetsSm,
        child: Row(
          children: <Widget>[
            Container(
              padding: spacing.symmetric(horizontal: spacing.xs, vertical: spacing.xxs),
              decoration: BoxDecoration(
                color: colors.statusNormal,
                borderRadius: radii.borderSm,
              ),
              child: Text(
                '#$bitPadded',
                style: TextStyle(
                  color: colors.onStatusNormal,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
            SizedBox(width: spacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    student.fullName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: spacing.xxs / 2),
                  Row(
                    children: <Widget>[
                      Text(
                        'Cód: ${student.studentCode}',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colors.primary,
                        ),
                      ),
                      SizedBox(width: spacing.xs),
                      Container(
                        padding: spacing.symmetric(
                          horizontal: spacing.xxs + 2,
                          vertical: spacing.xxs / 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: radii.borderXs,
                          border: Border.all(color: colors.statusNormal.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          token,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: colors.statusNormal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.signal_cellular_alt,
                      size: 14,
                      color: rssiInt >= -65
                          ? colors.statusNormal
                          : colors.statusAlerta,
                    ),
                    SizedBox(width: spacing.xxs / 2),
                    Text(
                      '$rssiInt dBm',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: rssiInt >= -65
                            ? colors.statusNormal
                            : colors.statusAlerta,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: spacing.xxs / 2),
                Container(
                  padding: spacing.symmetric(
                    horizontal: spacing.xxs + 2,
                    vertical: spacing.xxs / 2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.statusNormalContainer,
                    borderRadius: radii.borderXs,
                  ),
                  child: Text(
                    'BLE OK',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: colors.onStatusNormalContainer,
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

  // ---------------------------------------------------------------------------
  // Pestaña 2: Lista Invertida (1 Toque)
  // ---------------------------------------------------------------------------

  Widget _buildInvertedListTab(ThemeData theme) {
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);
    final query = _searchQuery.trim().toLowerCase();

    // Filtramos estudiantes según búsqueda rápida
    final filtered = _students.where((StudentModel s) {
      if (query.isEmpty) return true;
      return s.fullName.toLowerCase().contains(query) ||
          s.studentCode.contains(query);
    }).toList(growable: false);

    // Separamos en pendientes (arriba como pide el requerimiento) y confirmados (abajo)
    final pending = filtered
        .where((StudentModel s) => !_recordsByStudentId.containsKey(s.id))
        .toList(growable: false);

    final confirmed = filtered
        .where((StudentModel s) => _recordsByStudentId.containsKey(s.id))
        .toList(growable: false);

    return ListView(
      padding: spacing.insetsMd,
      children: <Widget>[
        // Mensaje descriptivo de la lista invertida
        Container(
          padding: spacing.symmetric(horizontal: spacing.sm, vertical: spacing.xs),
          decoration: BoxDecoration(
            color: colors.manualAccentContainer.withValues(alpha: 0.35),
            borderRadius: radii.borderSm,
            border: Border.all(color: colors.manualAccent.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.touch_app, size: 20, color: colors.manualAccent),
              SizedBox(width: spacing.xs),
              Expanded(
                child: Text(
                  'Marca a los alumnos sin celular o con batería descargada con un solo toque.',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onManualAccentContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: spacing.sm),

        // Buscador Rápido por Nombre o Código
        TextField(
          controller: _searchController,
          onChanged: (String value) => setState(() => _searchQuery = value),
          decoration: InputDecoration(
            hintText: 'Buscar por nombre o código...',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            isDense: true,
            filled: true,
            fillColor: colors.surfaceContainerHigh.withValues(alpha: 0.3),
            border: OutlineInputBorder(
              borderRadius: radii.borderSm,
              borderSide: BorderSide(
                color: colors.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
        SizedBox(height: spacing.md),

        // SECCIÓN 1: PENDIENTES / SIN BLE (Muestra en la parte superior)
        Row(
          children: <Widget>[
            Container(
              padding: spacing.symmetric(horizontal: spacing.xs, vertical: spacing.xxs / 2),
              decoration: BoxDecoration(
                color: colors.statusPerdidaContainer,
                borderRadius: radii.borderXs,
              ),
              child: Text(
                'PENDIENTES (${pending.length})',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: colors.onStatusPerdidaContainer,
                ),
              ),
            ),
            SizedBox(width: spacing.xs),
            Text(
              'No detectados por BLE',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceMuted,
              ),
            ),
          ],
        ),
        SizedBox(height: spacing.xs),

        if (pending.isEmpty)
          Container(
            padding: spacing.insetsMd,
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: radii.borderSm,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.check_circle_outline, color: colors.statusNormal, size: 18),
                SizedBox(width: spacing.xs),
                Text(
                  'No hay estudiantes pendientes en este grupo.',
                  style: TextStyle(fontSize: 12, color: colors.onSurfaceMuted),
                ),
              ],
            ),
          )
        else
          ...pending.map((StudentModel student) {
            return _buildPendingStudentTile(theme, student);
          }),

        SizedBox(height: spacing.lg),

        // SECCIÓN 2: YA CONFIRMADOS (BLE O MANUAL)
        Row(
          children: <Widget>[
            Container(
              padding: spacing.symmetric(horizontal: spacing.xs, vertical: spacing.xxs / 2),
              decoration: BoxDecoration(
                color: colors.statusNormalContainer,
                borderRadius: radii.borderXs,
              ),
              child: Text(
                'REGISTRADOS (${confirmed.length})',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: colors.onStatusNormalContainer,
                ),
              ),
            ),
            SizedBox(width: spacing.xs),
            Text(
              'Presentes en el Bitmap',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceMuted,
              ),
            ),
          ],
        ),
        SizedBox(height: spacing.xs),

        if (confirmed.isEmpty)
          Padding(
            padding: spacing.insetsSm,
            child: Text(
              'Aún no hay alumnos confirmados.',
              style: TextStyle(fontSize: 12, color: colors.onSurfaceMuted),
            ),
          )
        else
          ...confirmed.map((StudentModel student) {
            final record = _recordsByStudentId[student.id];
            return _buildConfirmedStudentTile(theme, student, record);
          }),
      ],
    );
  }

  Widget _buildPendingStudentTile(ThemeData theme, StudentModel student) {
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);
    final bitPadded = student.bitIndex.toString().padLeft(2, '0');

    return Card(
      elevation: 0,
      margin: spacing.only(bottom: spacing.xxs + 2),
      shape: radii.cardShape(
        side: BorderSide(
          color: colors.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: ListTile(
        contentPadding: spacing.symmetric(horizontal: spacing.sm, vertical: spacing.xxs / 2),
        leading: Container(
          width: 44,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            borderRadius: radii.borderXs,
          ),
          child: Text(
            '#$bitPadded',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ),
        title: Text(
          student.fullName,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        subtitle: Text(
          'Cód: ${student.studentCode}',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            color: colors.onSurfaceMuted,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.note_alt_outlined, size: 20),
              tooltip: 'Agregar nota de excepción',
              onPressed: () => _showObservationDialog(student),
            ),
            FilledButton.tonal(
              onPressed: () => _handleToggleManual(student, true),
              style: FilledButton.styleFrom(
                backgroundColor: colors.manualAccentContainer,
                foregroundColor: colors.onManualAccentContainer,
                padding: spacing.symmetric(horizontal: spacing.sm, vertical: spacing.xs),
                shape: radii.buttonShape(),
              ),
              child: const Text(
                'Presente',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmedStudentTile(
    ThemeData theme,
    StudentModel student,
    AttendanceRecordModel? record,
  ) {
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);
    final isBle = record?.method == AppConstants.attendanceMethodBleHmac;
    final bitPadded = student.bitIndex.toString().padLeft(2, '0');

    return Card(
      elevation: 0,
      margin: spacing.only(bottom: spacing.xxs + 2),
      shape: radii.cardShape(
        side: BorderSide(
          color: isBle
              ? colors.statusNormal.withValues(alpha: 0.3)
              : colors.manualAccent.withValues(alpha: 0.3),
        ),
      ),
      color: isBle
          ? colors.statusNormalContainer.withValues(alpha: 0.2)
          : colors.manualAccentContainer.withValues(alpha: 0.2),
      child: ListTile(
        contentPadding: spacing.symmetric(horizontal: spacing.sm, vertical: spacing.xxs / 2),
        leading: Container(
          width: 44,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isBle ? colors.statusNormal : colors.manualAccent,
            borderRadius: radii.borderXs,
          ),
          child: Text(
            '#$bitPadded',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              fontSize: 12,
              color: colors.onPrimary,
            ),
          ),
        ),
        title: Text(
          student.fullName,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        subtitle: Row(
          children: <Widget>[
            Text(
              'Cód: ${student.studentCode}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
            SizedBox(width: spacing.xs),
            Container(
              padding: spacing.symmetric(horizontal: spacing.xxs + 2, vertical: spacing.xxs / 4),
              decoration: BoxDecoration(
                color: isBle ? colors.statusNormalContainer : colors.manualAccentContainer,
                borderRadius: radii.borderXs,
              ),
              child: Text(
                isBle ? 'BLE' : 'MANUAL',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: isBle ? colors.onStatusNormalContainer : colors.onManualAccentContainer,
                ),
              ),
            ),
            if (record?.observation != null) ...<Widget>[
              SizedBox(width: spacing.xxs + 2),
              Expanded(
                child: Text(
                  '(${record!.observation!})',
                  style: TextStyle(
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    color: colors.onSurfaceMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        trailing: isBle
            ? Icon(Icons.check_circle, color: colors.statusNormal, size: 22)
            : OutlinedButton(
                onPressed: () => _handleToggleManual(student, false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.statusPerdida,
                  side: BorderSide(color: colors.statusPerdida.withValues(alpha: 0.4)),
                  padding: spacing.symmetric(horizontal: spacing.xs, vertical: spacing.xxs),
                  shape: radii.buttonShape(),
                ),
                child: const Text('Desmarcar', style: TextStyle(fontSize: 11)),
              ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Barra Inferior con Botón de Cierre y Firma
  // ---------------------------------------------------------------------------

  Widget _buildBottomActionBar(ThemeData theme) {
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    return Container(
      padding: spacing.fromLTRB(spacing.md, spacing.sm, spacing.md, spacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colors.onSurface.withValues(alpha: 0.05),
            offset: const Offset(0, -2),
            blurRadius: 8,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isClosing ? null : _handleCloseAndSignSession,
            icon: _isClosing
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.onPrimary,
                    ),
                  )
                : const Icon(Icons.verified_outlined),
            label: Text(
              _isClosing
                  ? 'Firmando Acta Criptográfica...'
                  : 'Cerrar Sesión y Firmar Acta',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: colors.onPrimary,
              padding: spacing.insetsVMd,
              shape: radii.buttonShape(),
            ),
          ),
        ),
      ),
    );
  }
}
