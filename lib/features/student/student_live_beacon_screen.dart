import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/crypto/ble_packet_codec.dart';
import '../../core/models/student_enrollment_model.dart';
import '../../data/local/app_database.dart';
import '../../data/services/attendance_session_controller.dart';
import '../../data/services/ble_attendance_service.dart';

/// Verde institucional de la Universidad de La Guajira.
const Color _uniguajiraGreen = Color(0xFF00843D);

/// Fases del flujo de emisión BLE y recepción de eco en el estudiante.
enum StudentBeaconPhase {
  /// Paso 1: Ingreso del PIN verbal de 2 dígitos dictado en el aula.
  inputPin,

  /// Paso 2: Emitiendo anuncio BLE HMAC-SHA256 y escuchando el eco docente.
  broadcasting,

  /// Paso 3: Asistencia confirmada en el Bitmap con Sello Criptográfico Verde.
  confirmed,
}

/// Pantalla completa de asistencia en vivo para el estudiante.
///
/// Gestiona las 3 etapas del protocolo en el aula:
/// 1. Ingreso del PIN verbal de 2 dígitos (10..99).
/// 2. Emisión del beacon BLE de 16 bytes con Service UUID de 128 bits,
///    rotación de HMAC cada 30 segundos y escucha en tiempo real del eco del docente.
/// 3. Despliegue del Sello Criptográfico Verde Oficial Uniguajira con token
///    auditable `UG-XXXXXXXX` tras confirmar el bit en 1 en el Mapa de Bits.
class StudentLiveBeaconScreen extends StatefulWidget {
  const StudentLiveBeaconScreen({
    super.key,
    required this.enrollment,
    this.bleService,
    this.sessionController,
    this.database,
  });

  /// Credencial local del estudiante para este curso.
  final StudentEnrollmentModel enrollment;

  /// Servicio BLE inyectable para pruebas o mocks.
  final BleAttendanceService? bleService;

  /// Controlador de sesión inyectable para verificar el eco docente.
  final AttendanceSessionController? sessionController;

  /// Base de datos local inyectable.
  final AppDatabase? database;

  @override
  State<StudentLiveBeaconScreen> createState() =>
      _StudentLiveBeaconScreenState();
}

class _StudentLiveBeaconScreenState extends State<StudentLiveBeaconScreen>
    with SingleTickerProviderStateMixin {
  late final BleAttendanceService _bleService;
  late final bool _ownsBleService;
  late final AttendanceSessionController _sessionController;
  late final bool _ownsSessionController;

  late final TextEditingController _pinController;
  final FocusNode _pinFocusNode = FocusNode();

  StudentBeaconPhase _phase = StudentBeaconPhase.inputPin;

  int? _sessionPin;
  StreamSubscription<BlePacketEvent>? _bleSubscription;
  Timer? _tickerTimer;
  DateTime _now = DateTime.now();
  int _currentTick = 0;
  int? _lastEmittedTick;
  String? _currentEmittedUuid;

  StudentConfirmationOutcome? _confirmationOutcome;
  DateTime? _confirmedAt;

  String? _bleWarning;
  bool _isProcessingPacket = false;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _bleService = widget.bleService ?? BleAttendanceService();
    _ownsBleService = widget.bleService == null;

    final db = widget.database ?? AppDatabase.instance;
    _sessionController =
        widget.sessionController ??
        AttendanceSessionController(database: db, bleService: _bleService);
    _ownsSessionController = widget.sessionController == null;

    _pinController = TextEditingController();
    _pinController.addListener(() {
      setState(() {});
    });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _tickerTimer?.cancel();
    _bleSubscription?.cancel();

    if (_phase == StudentBeaconPhase.broadcasting) {
      unawaited(_bleService.stopAdvertising());
      unawaited(_bleService.stopScan());
    }

    if (_ownsSessionController) {
      unawaited(_sessionController.dispose());
    } else if (_ownsBleService) {
      unawaited(_bleService.dispose());
    }

    _pinController.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Lógica de Protocolo BLE y Verificación de Eco
  // ---------------------------------------------------------------------------

  Future<void> _startBroadcasting(int pin) async {
    _sessionPin = pin;
    _now = DateTime.now();
    _currentTick = BlePacketCodec.computeTimeTick(_now);
    _lastEmittedTick = _currentTick;

    final packet = BlePacketCodec.buildStudentBeaconBytes(
      courseId: widget.enrollment.courseId,
      bitIndex: widget.enrollment.bitIndex,
      sessionPin: pin,
      secretHex: widget.enrollment.deviceSecret,
      timeTick: _currentTick,
    );
    _currentEmittedUuid = BlePacketCodec.bytes16ToUuid(packet);

    setState(() {
      _phase = StudentBeaconPhase.broadcasting;
      _bleWarning = null;
    });

    _bleSubscription = _bleService.packetEvents.listen(
      (BlePacketEvent event) {
        _handleIncomingPacket(event.packet16, event.rssi);
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _bleWarning = 'Aviso de canal BLE: $error';
        });
      },
    );

    try {
      await _bleService.startAdvertisingPacket(packet);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bleWarning =
            'Emisión por hardware no disponible en este entorno ($e). '
            'Usa el botón de simulación para verificar el flujo.';
      });
    }

    try {
      await _bleService.startScan();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bleWarning ??=
            'Escaneo BLE no disponible en este dispositivo ($e). '
            'Usa el botón de simulación para verificar el flujo.';
      });
    }

    _startTicker();
  }

  void _startTicker() {
    _tickerTimer?.cancel();
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (Timer _) {
      if (!mounted || _phase != StudentBeaconPhase.broadcasting) {
        return;
      }
      final now = DateTime.now();
      final newTick = BlePacketCodec.computeTimeTick(now);
      final tickChanged = newTick != _lastEmittedTick;

      if (tickChanged && _sessionPin != null) {
        _lastEmittedTick = newTick;
        _currentTick = newTick;
        final packet = BlePacketCodec.buildStudentBeaconBytes(
          courseId: widget.enrollment.courseId,
          bitIndex: widget.enrollment.bitIndex,
          sessionPin: _sessionPin!,
          secretHex: widget.enrollment.deviceSecret,
          timeTick: newTick,
        );
        _currentEmittedUuid = BlePacketCodec.bytes16ToUuid(packet);
        unawaited(_updateAdvertisingPacket(packet));
      }

      setState(() {
        _now = now;
        _currentTick = newTick;
      });
    });
  }

  Future<void> _updateAdvertisingPacket(Uint8List packet) async {
    try {
      await _bleService.startAdvertisingPacket(packet);
    } catch (_) {
      // Ignorar fallo de actualización en dispositivos sin emisor nativo.
    }
  }

  Future<void> _handleIncomingPacket(Uint8List packet16, int rssi) async {
    if (_phase != StudentBeaconPhase.broadcasting ||
        _isProcessingPacket ||
        _sessionPin == null) {
      return;
    }
    _isProcessingPacket = true;
    try {
      final outcome = await _sessionController.checkTeacherEchoForStudent(
        enrollment: widget.enrollment,
        sessionPin: _sessionPin!,
        teacherPacket16: packet16,
        rssi: rssi,
      );

      if (outcome.isConfirmed) {
        await _onConfirmed(outcome);
      }
    } catch (_) {
      // Paquetes ajenos al protocolo o corruptos se descartan sin interrumpir.
    } finally {
      _isProcessingPacket = false;
    }
  }

  Future<void> _onConfirmed(StudentConfirmationOutcome outcome) async {
    _tickerTimer?.cancel();
    _tickerTimer = null;
    await _bleSubscription?.cancel();
    _bleSubscription = null;

    try {
      await _bleService.stopAdvertising();
    } catch (_) {}
    try {
      await _bleService.stopScan();
    } catch (_) {}

    await HapticFeedback.heavyImpact();

    if (!mounted) return;
    setState(() {
      _phase = StudentBeaconPhase.confirmed;
      _confirmationOutcome = outcome;
      _confirmedAt = outcome.confirmedAt ?? DateTime.now();
    });
  }

  Future<void> _cancelBroadcasting() async {
    _tickerTimer?.cancel();
    _tickerTimer = null;
    await _bleSubscription?.cancel();
    _bleSubscription = null;

    try {
      await _bleService.stopAdvertising();
    } catch (_) {}
    try {
      await _bleService.stopScan();
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _phase = StudentBeaconPhase.inputPin;
      _sessionPin = null;
      _bleWarning = null;
    });
  }

  Future<void> _simulateTeacherEcho() async {
    if (_sessionPin == null) return;

    // Construye un mapa de bits de 8 bytes con el bit del estudiante en 1.
    final bitmap8 = BlePacketCodec.setStudentBit(
      BlePacketCodec.createEmptyBitmap8(),
      widget.enrollment.bitIndex,
    );

    // Construye el paquete de eco firmado con el sharedSecret del curso.
    final simulatedEcho = BlePacketCodec.buildTeacherEchoBytes(
      courseId: widget.enrollment.courseId,
      sessionId: 'simulated_session_${widget.enrollment.courseId}',
      bitmap8: bitmap8,
      sharedSecretHex: widget.enrollment.sharedSecret,
    );

    // Inyecta en el servicio y procesa con el verificador real.
    _bleService.injectSimulatedPacket(packet16: simulatedEcho, rssi: -60);
    await _handleIncomingPacket(simulatedEcho, -60);
  }

  // ---------------------------------------------------------------------------
  // Construcción de la Interfaz
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: _buildAppBar(theme),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: switch (_phase) {
            StudentBeaconPhase.inputPin => _buildInputPinStep(theme),
            StudentBeaconPhase.broadcasting => _buildBroadcastingStep(theme),
            StudentBeaconPhase.confirmed => _buildConfirmedStep(theme),
          },
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeData theme) {
    if (_phase == StudentBeaconPhase.confirmed) {
      return AppBar(
        title: const Text('Sello Criptográfico Oficial'),
        backgroundColor: _uniguajiraGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      );
    }

    return AppBar(
      title: Text(
        _phase == StudentBeaconPhase.inputPin
            ? 'Marcar Asistencia BLE'
            : 'Emisión en Aula',
      ),
      backgroundColor: theme.colorScheme.primary,
      foregroundColor: theme.colorScheme.onPrimary,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: 'Regresar',
        onPressed: () {
          if (_phase == StudentBeaconPhase.broadcasting) {
            _cancelBroadcasting();
          } else {
            Navigator.of(context).pop();
          }
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Paso 1: Ingreso del PIN Verbal del Salón (10..99)
  // ---------------------------------------------------------------------------

  Widget _buildInputPinStep(ThemeData theme) {
    final pinText = _pinController.text.trim();
    final parsed = int.tryParse(pinText);
    final isValidPin =
        parsed != null &&
        parsed >= AppConstants.minimumSessionPin &&
        parsed <= AppConstants.maximumSessionPin &&
        pinText.length == AppConstants.roomPinLength;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Tarjeta informativa del curso y estudiante
              _buildCourseSummaryCard(theme),
              const SizedBox(height: 24),

              // Título y explicación del PIN verbal
              Text(
                'PIN Verbal del Aula',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Digita el número de 2 dígitos (10 a 99) que el profesor dicta '
                'en el aula para iniciar la emisión de tu beacon seguro.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Campo de entrada grande para el PIN
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isValidPin
                        ? _uniguajiraGreen
                        : theme.colorScheme.outlineVariant,
                    width: isValidPin ? 2 : 1,
                  ),
                ),
                child: Column(
                  children: <Widget>[
                    TextField(
                      controller: _pinController,
                      focusNode: _pinFocusNode,
                      keyboardType: TextInputType.number,
                      maxLength: AppConstants.roomPinLength,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      textAlign: TextAlign.center,
                      autofocus: true,
                      style: theme.textTheme.displayMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 18,
                        color: isValidPin
                            ? _uniguajiraGreen
                            : theme.colorScheme.primary,
                      ),
                      decoration: const InputDecoration(
                        hintText: '00',
                        counterText: '',
                        border: InputBorder.none,
                      ),
                      onSubmitted: (String value) {
                        if (isValidPin) {
                          _startBroadcasting(parsed);
                        }
                      },
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          isValidPin
                              ? Icons.check_circle_rounded
                              : Icons.info_outline_rounded,
                          size: 18,
                          color: isValidPin
                              ? _uniguajiraGreen
                              : theme.colorScheme.outline,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isValidPin
                              ? 'PIN Válido ($parsed)'
                              : 'Ingresa 2 dígitos (10..99)',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: isValidPin
                                ? _uniguajiraGreen
                                : theme.colorScheme.outline,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Botón "Iniciar Emisión BLE"
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  onPressed: isValidPin
                      ? () => _startBroadcasting(parsed)
                      : null,
                  icon: const Icon(Icons.bluetooth_searching, size: 24),
                  label: const Text(
                    'Iniciar Emisión BLE',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Nota de seguridad y protocolo
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.35,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.shield_outlined,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Protocolo Seguro: Tu anuncio se firma con HMAC-SHA256 '
                        'rotativo de 30s. Solo el docente con la clave del curso '
                        'puede descifrar tu presencia.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontSize: 11.5,
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
    );
  }

  // ---------------------------------------------------------------------------
  // Paso 2: Emitiendo Beacon HMAC y Escuchando Eco Docente
  // ---------------------------------------------------------------------------

  Widget _buildBroadcastingStep(ThemeData theme) {
    final epochSeconds = _now.millisecondsSinceEpoch ~/ 1000;
    final elapsedInWindow = epochSeconds % AppConstants.hmacWindowSeconds;
    final secondsRemaining = AppConstants.hmacWindowSeconds - elapsedInWindow;
    final progress = secondsRemaining / AppConstants.hmacWindowSeconds;

    final bitIndexFormatted = widget.enrollment.bitIndex
        .toString()
        .padLeft(2, '0');

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Animación de radar y estado principal
              Center(
                child: ScaleTransition(
                  scale: _pulseAnimation,
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      border: Border.all(
                        color: theme.colorScheme.primary.withValues(alpha: 0.45),
                        width: 3,
                      ),
                    ),
                    child: Icon(
                      Icons.sensors_rounded,
                      size: 48,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Text(
                'Emitiendo Beacon Criptográfico',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Escuchando el Eco del Docente en el aula...',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // Roster: Bit Asignado (#XX) y Código Estudiantil
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.6,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.6,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: <Widget>[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          // Bit asignado destacado
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                const Icon(
                                  Icons.tag_rounded,
                                  size: 18,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Bit #$bitIndexFormatted',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // PIN en uso
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'PIN: $_sessionPin',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 22),
                      Row(
                        children: <Widget>[
                          const Icon(Icons.person_outline, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.enrollment.fullName,
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
                          const Icon(Icons.badge_outlined, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Código: ${widget.enrollment.studentCode}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Tarjeta de Cuenta Regresiva de la Ventana HMAC (30 segundos)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.35,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(
                              Icons.timer_outlined,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'VENTANA HMAC ROTATIVA',
                              style: theme.textTheme.labelSmall?.copyWith(
                                letterSpacing: 1.1,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Tick #$_currentTick',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: theme.colorScheme.primary.withValues(
                        alpha: 0.15,
                      ),
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 8),
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
                          'Ventana: ${AppConstants.hmacWindowSeconds}s',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // UUID de 128 bits emitido en el anuncio BLE
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.5,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          'UUID 128-BIT EMITIDO (BLE)',
                          style: theme.textTheme.labelSmall?.copyWith(
                            letterSpacing: 1,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        if (_currentEmittedUuid != null)
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            tooltip: 'Copiar UUID',
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: _currentEmittedUuid!),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('UUID copiado al portapapeles'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      _currentEmittedUuid ?? 'Calculando Service UUID...',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Payload de 16 bytes: [CourseHash:2][Flag+Bit:1][Pin:1][Tick:4][HMAC:8]',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Aviso si el hardware BLE no está disponible localmente
              if (_bleWarning != null) ...<Widget>[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 20,
                        color: Colors.amber.shade900,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _bleWarning!,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Botón discreto de simulación para pruebas de escritorio / QA
              OutlinedButton.icon(
                onPressed: _simulateTeacherEcho,
                icon: const Icon(Icons.science_outlined, size: 20),
                label: const Text('Simular Eco Docente (Demo/Test)'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.5),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Botón para cancelar emisión y volver al paso 1
              TextButton.icon(
                onPressed: _cancelBroadcasting,
                icon: const Icon(Icons.close_rounded),
                label: const Text('Cancelar Emisión / Cambiar PIN'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Paso 3: SELLO CRIPTOGRÁFICO VERDE OFICIAL UNIGUAJIRA
  // ---------------------------------------------------------------------------

  Widget _buildConfirmedStep(ThemeData theme) {
    final outcome = _confirmationOutcome;
    final verifyCode = outcome?.verifyCode ?? 'UG-00000000';
    final confirmedAt = _confirmedAt ?? DateTime.now();
    final formattedDate = DateFormat(
      'dd/MM/yyyy · HH:mm:ss',
    ).format(confirmedAt);
    final bitIndexFormatted = widget.enrollment.bitIndex
        .toString()
        .padLeft(2, '0');

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Encabezado institucional del Sello Verde
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 28,
                ),
                decoration: BoxDecoration(
                  color: _uniguajiraGreen,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: _uniguajiraGreen.withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: <Widget>[
                    // Ícono de verificación grande
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.verified_rounded,
                        size: 72,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),

                    const Text(
                      'UNIVERSIDAD DE LA GUAJIRA',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '¡ASISTENCIA REGISTRADA!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'SELLO CRIPTOGRÁFICO OFICIAL',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Código de verificación auditable en grande (UG-XXXXXXXX)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            verifyCode,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2.5,
                              color: _uniguajiraGreen,
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton(
                            icon: const Icon(
                              Icons.copy_rounded,
                              size: 22,
                              color: _uniguajiraGreen,
                            ),
                            tooltip: 'Copiar código de verificación',
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: verifyCode),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Código de verificación copiado',
                                  ),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Comprobante inmutable emitido por el Eco del Docente',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Detalle auditable de la asistencia
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.5,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Datos del Registro',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Divider(height: 20),
                      _buildDetailRow(
                        icon: Icons.person_outline,
                        label: 'Estudiante',
                        value: widget.enrollment.fullName,
                        theme: theme,
                      ),
                      const SizedBox(height: 12),
                      _buildDetailRow(
                        icon: Icons.badge_outlined,
                        label: 'Código Estudiantil',
                        value: widget.enrollment.studentCode,
                        isMonospace: true,
                        theme: theme,
                      ),
                      const SizedBox(height: 12),
                      _buildDetailRow(
                        icon: Icons.menu_book_rounded,
                        label: 'Asignatura',
                        value:
                            '${widget.enrollment.courseName} (${widget.enrollment.courseCode})',
                        theme: theme,
                      ),
                      const SizedBox(height: 12),
                      _buildDetailRow(
                        icon: Icons.tag_rounded,
                        label: 'Posición en Mapa de Bits',
                        value: 'Bit #$bitIndexFormatted (Confirmado en 1)',
                        isHighlight: true,
                        theme: theme,
                      ),
                      const SizedBox(height: 12),
                      _buildDetailRow(
                        icon: Icons.access_time_rounded,
                        label: 'Hora Exacta',
                        value: formattedDate,
                        theme: theme,
                      ),
                      if (outcome?.sessionPin != null) ...<Widget>[
                        const SizedBox(height: 12),
                        _buildDetailRow(
                          icon: Icons.pin_outlined,
                          label: 'PIN del Aula',
                          value: '${outcome!.sessionPin}',
                          theme: theme,
                        ),
                      ],
                      if (outcome?.rssi != null) ...<Widget>[
                        const SizedBox(height: 12),
                        _buildDetailRow(
                          icon: Icons.signal_cellular_alt_rounded,
                          label: 'Potencia RSSI',
                          value: '${outcome!.rssi} dBm (Proximidad aceptada)',
                          theme: theme,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Botones de acción final
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        final summary =
                            'COMPROBANTE ASISTENCIA UNIGUAJIRA\n'
                            'Token: $verifyCode\n'
                            'Asignatura: ${widget.enrollment.courseName}\n'
                            'Estudiante: ${widget.enrollment.fullName} (${widget.enrollment.studentCode})\n'
                            'Bit: #$bitIndexFormatted\n'
                            'Fecha: $formattedDate';
                        Clipboard.setData(ClipboardData(text: summary));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Resumen de asistencia copiado al portapapeles',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('Copiar'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Volver a Mis Cursos'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _uniguajiraGreen,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Componentes Auxiliares
  // ---------------------------------------------------------------------------

  Widget _buildCourseSummaryCard(ThemeData theme) {
    final bitIndexFormatted = widget.enrollment.bitIndex
        .toString()
        .padLeft(2, '0');

    return Card(
      elevation: 0,
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.school_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        widget.enrollment.courseName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Código: ${widget.enrollment.courseCode}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.enrollment.fullName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Código: ${widget.enrollment.studentCode}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontFamily: 'monospace',
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Bit #$bitIndexFormatted',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
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

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    required ThemeData theme,
    bool isMonospace = false,
    bool isHighlight = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          icon,
          size: 18,
          color: isHighlight ? _uniguajiraGreen : theme.colorScheme.primary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: isMonospace ? 'monospace' : null,
                  fontWeight: isHighlight ? FontWeight.bold : FontWeight.w500,
                  color: isHighlight ? _uniguajiraGreen : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
