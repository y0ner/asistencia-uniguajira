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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '¡Llegada BLE confirmada! ${student.fullName} (Bit #${student.bitIndex.toString().padLeft(2, '0')}) '
              'Token: ${outcome.verifyCode}',
            ),
            backgroundColor: Colors.green.shade800,
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Rechazo criptográfico: ${outcome.failureReason ?? "Firma no válida"}',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al simular llegada BLE: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _openSimulationPicker() {
    final pendingStudents = _students
        .where((StudentModel s) => !_recordsByStudentId.containsKey(s.id))
        .toList(growable: false);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext ctx) {
        final theme = Theme.of(ctx);

        if (pendingStudents.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.check_circle_outline,
                  color: Colors.green,
                  size: 48,
                ),
                const SizedBox(height: 12),
                Text(
                  'Todos los estudiantes están presentes',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'No hay estudiantes pendientes por detectar en esta sesión.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cerrar'),
                ),
              ],
            ),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.science, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
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
                const SizedBox(height: 4),
                Text(
                  'Selecciona un estudiante para inyectar su paquete de 16 bytes firmado con su clave HMAC real (RSSI: -62 dBm).',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
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
                      backgroundColor: Colors.green.shade700,
                    ),
                  ),
                ),
                const Divider(height: 24),
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
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: Text(
                            bitPadded,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onPrimaryContainer,
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
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
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
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
                backgroundColor: const Color(0xFF0033A0),
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

    if (_isStarting) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Sesión BLE: ${widget.course.name}'),
          backgroundColor: const Color(0xFF0033A0),
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
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
          backgroundColor: const Color(0xFF0033A0),
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
                const SizedBox(height: 16),
                Text(
                  'Error al iniciar sesión',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(_initError!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
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
          backgroundColor: const Color(0xFF0033A0),
          foregroundColor: Colors.white,
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
              color: theme.colorScheme.surface,
              child: TabBar(
                controller: _tabController,
                indicatorColor: const Color(0xFF0033A0),
                labelColor: const Color(0xFF0033A0),
                unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
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
    final active = _controller.state;
    final bleWarning = _controller.bleWarning;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        children: <Widget>[
          // Alerta no bloqueante si hay advertencias de hardware BLE
          if (bleWarning != null && bleWarning.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              color: Colors.amber.shade100,
              child: Row(
                children: <Widget>[
                  Icon(Icons.warning_amber, size: 16, color: Colors.amber.shade900),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      bleWarning,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.amber.shade900,
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // PIN Verbal de Aula en Grande y Llamativo
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0033A0),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: const Color(0xFF0033A0).withValues(alpha: 0.3),
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
                        children: const <Widget>[
                          Icon(
                            Icons.record_voice_over,
                            color: Colors.white70,
                            size: 14,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'PIN DE AULA',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        pinStr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'monospace',
                          letterSpacing: 2,
                        ),
                      ),
                      const Text(
                        'Dilo en voz alta',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),

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
                                  ? Colors.green.shade700
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              border: Border(
                top: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: <Widget>[
                _buildLiveBadge(
                  label: 'BLE',
                  count: presentBleCount,
                  color: Colors.green.shade700,
                  icon: Icons.bluetooth_connected,
                ),
                _buildLiveBadge(
                  label: 'Manual',
                  count: presentManualCount,
                  color: Colors.orange.shade800,
                  icon: Icons.touch_app,
                ),
                _buildLiveBadge(
                  label: 'Pendientes',
                  count: absentCount,
                  color: Colors.red.shade700,
                  icon: Icons.person_off,
                ),
                _buildLiveBadge(
                  label: 'Total',
                  countStr: '$totalPresent / $totalEnrolled',
                  color: const Color(0xFF0033A0),
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
    final bitmap8 = active?.bitmap8;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
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
                cellColor = Colors.green.shade600;
              } else if (isEnrolled) {
                cellColor = theme.colorScheme.surfaceContainerHighest;
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
                  margin: const EdgeInsets.all(1),
                  decoration: BoxDecoration(
                    color: cellColor,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: isSet
                          ? Colors.green.shade800
                          : (isEnrolled
                              ? Colors.grey.shade400
                              : Colors.grey.shade300),
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
                          ? Colors.white
                          : (isEnrolled ? Colors.black87 : Colors.grey.shade400),
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
    final displayValue = countStr ?? count.toString();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade700,
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
    final bleStudents = _students.where((StudentModel s) {
      final r = _recordsByStudentId[s.id];
      return r != null && r.method == AppConstants.attendanceMethodBleHmac;
    }).toList(growable: false);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        // Tarjeta de Radar Activo
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.green.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade600,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.sensors,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Radar BLE Activo',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          'Emitiendo Eco (16 bytes) y escuchando Beacons (RSSI >= -75 dBm)',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.green.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Botón para Simular Llegada BLE
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _openSimulationPicker,
                  icon: const Icon(Icons.bolt),
                  label: const Text('Simular Llegada BLE (Demo/Test)'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade800,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

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
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      alignment: Alignment.center,
      child: Column(
        children: <Widget>[
          Icon(
            Icons.radar,
            size: 54,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            'Esperando anuncios BLE de estudiantes',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Pide a los estudiantes ingresar el PIN del aula en su app. '
            'Aparecerán aquí con su token UG-XXXXXXXX una vez confirmados.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
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
    final bitPadded = student.bitIndex.toString().padLeft(2, '0');
    final rssiInt = record?.rssiAvg?.round() ?? -60;
    final token = record?.hmacTag ?? 'UG-????????';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.green.shade200),
      ),
      color: Colors.green.shade50.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.shade700,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '#$bitPadded',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 12),
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
                  const SizedBox(height: 2),
                  Row(
                    children: <Widget>[
                      Text(
                        'Cód: ${student.studentCode}',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.green.shade300),
                        ),
                        child: Text(
                          token,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade900,
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
                          ? Colors.green.shade800
                          : Colors.orange.shade800,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '$rssiInt dBm',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: rssiInt >= -65
                            ? Colors.green.shade800
                            : Colors.orange.shade800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'BLE OK',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade900,
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
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        // Mensaje descriptivo de la lista invertida
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.touch_app, size: 20, color: Colors.orange.shade800),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Marca a los alumnos sin celular o con batería descargada con un solo toque.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade900,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

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
            fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // SECCIÓN 1: PENDIENTES / SIN BLE (Muestra en la parte superior)
        Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'PENDIENTES (${pending.length})',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade900,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'No detectados por BLE',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (pending.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const <Widget>[
                Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                SizedBox(width: 8),
                Text(
                  'No hay estudiantes pendientes en este grupo.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          )
        else
          ...pending.map((StudentModel student) {
            return _buildPendingStudentTile(theme, student);
          }),

        const SizedBox(height: 24),

        // SECCIÓN 2: YA CONFIRMADOS (BLE O MANUAL)
        Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'REGISTRADOS (${confirmed.length})',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade900,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Presentes en el Bitmap',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (confirmed.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Aún no hay alumnos confirmados.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
    final bitPadded = student.bitIndex.toString().padLeft(2, '0');

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: Container(
          width: 44,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
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
            color: theme.colorScheme.onSurfaceVariant,
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
                backgroundColor: Colors.orange.shade100,
                foregroundColor: Colors.orange.shade900,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
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
    final isBle = record?.method == AppConstants.attendanceMethodBleHmac;
    final bitPadded = student.bitIndex.toString().padLeft(2, '0');

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isBle ? Colors.green.shade200 : Colors.orange.shade200,
        ),
      ),
      color: isBle
          ? Colors.green.shade50.withValues(alpha: 0.3)
          : Colors.orange.shade50.withValues(alpha: 0.3),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: Container(
          width: 44,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isBle ? Colors.green.shade700 : Colors.orange.shade700,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '#$bitPadded',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              fontSize: 12,
              color: Colors.white,
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
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isBle ? Colors.green.shade100 : Colors.orange.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isBle ? 'BLE' : 'MANUAL',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: isBle ? Colors.green.shade900 : Colors.orange.shade900,
                ),
              ),
            ),
            if (record?.observation != null) ...<Widget>[
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '(${record!.observation!})',
                  style: TextStyle(
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey.shade700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        trailing: isBle
            ? const Icon(Icons.check_circle, color: Colors.green, size: 22)
            : OutlinedButton(
                onPressed: () => _handleToggleManual(student, false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade300),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.verified_outlined),
            label: Text(
              _isClosing
                  ? 'Firmando Acta Criptográfica...'
                  : 'Cerrar Sesión y Firmar Acta',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0033A0),
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
