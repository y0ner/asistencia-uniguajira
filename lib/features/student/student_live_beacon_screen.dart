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
import '../../theme/theme.dart';

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
    return Scaffold(
      appBar: _buildAppBar(context),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: switch (_phase) {
            StudentBeaconPhase.inputPin => _buildInputPinStep(context),
            StudentBeaconPhase.broadcasting => _buildBroadcastingStep(context),
            StudentBeaconPhase.confirmed => _buildConfirmedStep(context),
          },
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final colors = AppColors.of(context);

    if (_phase == StudentBeaconPhase.confirmed) {
      return AppBar(
        title: const Text('Sello Criptográfico Oficial'),
        backgroundColor: colors.statusNormal,
        foregroundColor: colors.onStatusNormal,
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

  Widget _buildInputPinStep(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    final pinText = _pinController.text.trim();
    final parsed = int.tryParse(pinText);
    final isValidPin =
        parsed != null &&
        parsed >= AppConstants.minimumSessionPin &&
        parsed <= AppConstants.maximumSessionPin &&
        pinText.length == AppConstants.roomPinLength;

    return Center(
      child: SingleChildScrollView(
        padding: spacing.symmetric(horizontal: spacing.lg, vertical: spacing.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Tarjeta informativa del curso y estudiante
              _buildCourseSummaryCard(context),
              SizedBox(height: spacing.lg),

              // Título y explicación del PIN verbal
              Text(
                'PIN Verbal del Aula',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: spacing.xs),
              Text(
                'Digita el número de 2 dígitos (10 a 99) que el profesor dicta '
                'en el aula para iniciar la emisión de tu beacon seguro.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceMuted,
                  height: 1.35,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: spacing.lg),

              // Campo de entrada grande para el PIN
              Container(
                padding: spacing.insetsCard,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHigh.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: radii.borderXl,
                  border: Border.all(
                    color: isValidPin
                        ? colors.statusNormal
                        : colors.outlineVariant,
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
                            ? colors.statusNormal
                            : colors.primary,
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
                    SizedBox(height: spacing.xxs),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          isValidPin
                              ? Icons.check_circle_rounded
                              : Icons.info_outline_rounded,
                          size: 18,
                          color: isValidPin
                              ? colors.statusNormal
                              : colors.outline,
                        ),
                        SizedBox(width: spacing.xxs),
                        Text(
                          isValidPin
                              ? 'PIN Válido ($parsed)'
                              : 'Ingresa 2 dígitos (10..99)',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: isValidPin
                                ? colors.statusNormal
                                : colors.outline,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: spacing.xl),

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
                    shape: radii.buttonShape(),
                  ),
                ),
              ),
              SizedBox(height: spacing.md),

              // Nota de seguridad y protocolo
              Container(
                padding: spacing.insetsSm,
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(
                    alpha: 0.35,
                  ),
                  borderRadius: radii.borderMd,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.shield_outlined,
                      size: 20,
                      color: colors.primary,
                    ),
                    SizedBox(width: spacing.xs),
                    Expanded(
                      child: Text(
                        'Protocolo Seguro: Tu anuncio se firma con HMAC-SHA256 '
                        'rotativo de 30s. Solo el docente con la clave del curso '
                        'puede descifrar tu presencia.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onPrimaryContainer,
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

  Widget _buildBroadcastingStep(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    final epochSeconds = _now.millisecondsSinceEpoch ~/ 1000;
    final elapsedInWindow = epochSeconds % AppConstants.hmacWindowSeconds;
    final secondsRemaining = AppConstants.hmacWindowSeconds - elapsedInWindow;
    final progress = secondsRemaining / AppConstants.hmacWindowSeconds;

    final bitIndexFormatted = widget.enrollment.bitIndex
        .toString()
        .padLeft(2, '0');

    return SingleChildScrollView(
      padding: spacing.symmetric(horizontal: spacing.md, vertical: spacing.sm),
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
                      color: colors.primary.withValues(alpha: 0.12),
                      border: Border.all(
                        color: colors.primary.withValues(alpha: 0.45),
                        width: 3,
                      ),
                    ),
                    child: Icon(
                      Icons.sensors_rounded,
                      size: 48,
                      color: colors.primary,
                    ),
                  ),
                ),
              ),
              SizedBox(height: spacing.md),

              Text(
                'Emitiendo Beacon Criptográfico',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: spacing.xxs),
              Text(
                'Escuchando el Eco del Docente en el aula...',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceMuted,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: spacing.lg),

              // Roster: Bit Asignado (#XX) y Código Estudiantil
              Card(
                elevation: 0,
                color: colors.surfaceContainerHigh.withValues(
                  alpha: 0.6,
                ),
                shape: radii.cardShape(
                  side: BorderSide(
                    color: colors.outlineVariant.withValues(
                      alpha: 0.6,
                    ),
                  ),
                ),
                child: Padding(
                  padding: spacing.insetsMd,
                  child: Column(
                    children: <Widget>[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          // Bit asignado destacado
                          Container(
                            padding: spacing.symmetric(
                              horizontal: spacing.sm,
                              vertical: spacing.xxs,
                            ),
                            decoration: BoxDecoration(
                              color: colors.primary,
                              borderRadius: radii.borderSm,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(
                                  Icons.tag_rounded,
                                  size: 18,
                                  color: colors.onPrimary,
                                ),
                                SizedBox(width: spacing.xxs),
                                Text(
                                  'Bit #$bitIndexFormatted',
                                  style: TextStyle(
                                    color: colors.onPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // PIN en uso
                          Container(
                            padding: spacing.symmetric(
                              horizontal: spacing.xs,
                              vertical: spacing.xxs,
                            ),
                            decoration: BoxDecoration(
                              color: colors.primaryContainer,
                              borderRadius: radii.borderSm,
                            ),
                            child: Text(
                              'PIN: $_sessionPin',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colors.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Divider(height: spacing.lg),
                      Row(
                        children: <Widget>[
                          const Icon(Icons.person_outline, size: 20),
                          SizedBox(width: spacing.xs),
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
                      SizedBox(height: spacing.xxs),
                      Row(
                        children: <Widget>[
                          const Icon(Icons.badge_outlined, size: 20),
                          SizedBox(width: spacing.xs),
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
              SizedBox(height: spacing.md),

              // Tarjeta de Cuenta Regresiva de la Ventana HMAC (30 segundos)
              Container(
                padding: spacing.insetsMd,
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(
                    alpha: 0.35,
                  ),
                  borderRadius: radii.borderLg,
                  border: Border.all(
                    color: colors.primary.withValues(alpha: 0.3),
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
                              color: colors.primary,
                            ),
                            SizedBox(width: spacing.xxs),
                            Text(
                              'VENTANA HMAC ROTATIVA',
                              style: theme.textTheme.labelSmall?.copyWith(
                                letterSpacing: 1.1,
                                fontWeight: FontWeight.bold,
                                color: colors.primary,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Tick #$_currentTick',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.outline,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: spacing.sm),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: colors.primary.withValues(
                        alpha: 0.15,
                      ),
                      color: colors.primary,
                      borderRadius: radii.borderXs,
                    ),
                    SizedBox(height: spacing.xs),
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
                            color: colors.outline,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: spacing.md),

              // UUID de 128 bits emitido en el anuncio BLE
              Container(
                padding: spacing.insetsMd,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHigh.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: radii.borderLg,
                  border: Border.all(
                    color: colors.outlineVariant.withValues(
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
                            color: colors.primary,
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
                    SizedBox(height: spacing.xxs),
                    SelectableText(
                      _currentEmittedUuid ?? 'Calculando Service UUID...',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                    SizedBox(height: spacing.xxs),
                    Text(
                      'Payload de 16 bytes: [CourseHash:2][Flag+Bit:1][Pin:1][Tick:4][HMAC:8]',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.outline,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: spacing.md),

              // Aviso si el hardware BLE no está disponible localmente
              if (_bleWarning != null) ...<Widget>[
                Container(
                  padding: spacing.insetsSm,
                  decoration: BoxDecoration(
                    color: colors.statusAlertaContainer,
                    borderRadius: radii.borderMd,
                    border: Border.all(color: colors.statusAlerta.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 20,
                        color: colors.statusAlerta,
                      ),
                      SizedBox(width: spacing.xs),
                      Expanded(
                        child: Text(
                          _bleWarning!,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colors.onStatusAlertaContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: spacing.md),
              ],

              // Botón discreto de simulación para pruebas de escritorio / QA
              OutlinedButton.icon(
                onPressed: _simulateTeacherEcho,
                icon: const Icon(Icons.science_outlined, size: 20),
                label: const Text('Simular Eco Docente (Demo/Test)'),
                style: OutlinedButton.styleFrom(
                  padding: spacing.insetsVSm,
                  shape: radii.buttonShape(),
                  side: BorderSide(
                    color: colors.outline.withValues(alpha: 0.5),
                  ),
                ),
              ),
              SizedBox(height: spacing.sm),

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

  Widget _buildConfirmedStep(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

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
      padding: spacing.symmetric(horizontal: spacing.md, vertical: spacing.md),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Encabezado institucional del Sello Verde
              Container(
                width: double.infinity,
                padding: spacing.symmetric(
                  horizontal: spacing.md,
                  vertical: spacing.lg,
                ),
                decoration: BoxDecoration(
                  color: colors.statusNormal,
                  borderRadius: radii.borderXl,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: colors.statusNormal.withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: <Widget>[
                    // Ícono de verificación grande
                    Container(
                      padding: spacing.insetsMd,
                      decoration: BoxDecoration(
                        color: colors.onStatusNormal.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.verified_rounded,
                        size: 72,
                        color: colors.onStatusNormal,
                      ),
                    ),
                    SizedBox(height: spacing.md),

                    Text(
                      'UNIVERSIDAD DE LA GUAJIRA',
                      style: TextStyle(
                        color: colors.onStatusNormal.withValues(alpha: 0.8),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    SizedBox(height: spacing.xxs),
                    Text(
                      '¡ASISTENCIA REGISTRADA!',
                      style: TextStyle(
                        color: colors.onStatusNormal,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: spacing.xxs),
                    Container(
                      padding: spacing.symmetric(
                        horizontal: spacing.sm,
                        vertical: spacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: colors.onStatusNormal.withValues(alpha: 0.18),
                        borderRadius: radii.borderPill,
                      ),
                      child: Text(
                        'SELLO CRIPTOGRÁFICO OFICIAL',
                        style: TextStyle(
                          color: colors.onStatusNormal,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    SizedBox(height: spacing.lg),

                    // Código de verificación auditable en grande (UG-XXXXXXXX)
                    Container(
                      padding: spacing.symmetric(
                        horizontal: spacing.md,
                        vertical: spacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: radii.borderMd,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            verifyCode,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2.5,
                              color: colors.statusNormal,
                            ),
                          ),
                          SizedBox(width: spacing.xs),
                          IconButton(
                            icon: Icon(
                              Icons.copy_rounded,
                              size: 22,
                              color: colors.statusNormal,
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
                    SizedBox(height: spacing.xs),
                    Text(
                      'Comprobante inmutable emitido por el Eco del Docente',
                      style: TextStyle(
                        color: colors.onStatusNormal.withValues(alpha: 0.8),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: spacing.md),

              // Detalle auditable de la asistencia
              Card(
                elevation: 1,
                shape: radii.cardShape(
                  side: BorderSide(
                    color: colors.outlineVariant.withValues(
                      alpha: 0.5,
                    ),
                  ),
                ),
                child: Padding(
                  padding: spacing.symmetric(
                    horizontal: spacing.md,
                    vertical: spacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Datos del Registro',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Divider(height: spacing.lg),
                      _buildDetailRow(
                        icon: Icons.person_outline,
                        label: 'Estudiante',
                        value: widget.enrollment.fullName,
                        context: context,
                      ),
                      SizedBox(height: spacing.sm),
                      _buildDetailRow(
                        icon: Icons.badge_outlined,
                        label: 'Código Estudiantil',
                        value: widget.enrollment.studentCode,
                        isMonospace: true,
                        context: context,
                      ),
                      SizedBox(height: spacing.sm),
                      _buildDetailRow(
                        icon: Icons.menu_book_rounded,
                        label: 'Asignatura',
                        value:
                            '${widget.enrollment.courseName} (${widget.enrollment.courseCode})',
                        context: context,
                      ),
                      SizedBox(height: spacing.sm),
                      _buildDetailRow(
                        icon: Icons.tag_rounded,
                        label: 'Posición en Mapa de Bits',
                        value: 'Bit #$bitIndexFormatted (Confirmado en 1)',
                        isHighlight: true,
                        context: context,
                      ),
                      SizedBox(height: spacing.sm),
                      _buildDetailRow(
                        icon: Icons.access_time_rounded,
                        label: 'Hora Exacta',
                        value: formattedDate,
                        context: context,
                      ),
                      if (outcome?.sessionPin != null) ...<Widget>[
                        SizedBox(height: spacing.sm),
                        _buildDetailRow(
                          icon: Icons.pin_outlined,
                          label: 'PIN del Aula',
                          value: '${outcome!.sessionPin}',
                          context: context,
                        ),
                      ],
                      if (outcome?.rssi != null) ...<Widget>[
                        SizedBox(height: spacing.sm),
                        _buildDetailRow(
                          icon: Icons.signal_cellular_alt_rounded,
                          label: 'Potencia RSSI',
                          value: '${outcome!.rssi} dBm (Proximidad aceptada)',
                          context: context,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              SizedBox(height: spacing.lg),

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
                        padding: spacing.insetsVMd,
                        shape: radii.buttonShape(),
                      ),
                    ),
                  ),
                  SizedBox(width: spacing.sm),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Volver a Mis Cursos'),
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.statusNormal,
                        foregroundColor: colors.onStatusNormal,
                        padding: spacing.insetsVMd,
                        shape: radii.buttonShape(),
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

  Widget _buildCourseSummaryCard(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);

    final bitIndexFormatted = widget.enrollment.bitIndex
        .toString()
        .padLeft(2, '0');

    return Card(
      elevation: 0,
      color: colors.primaryContainer.withValues(alpha: 0.35),
      shape: radii.cardShape(
        side: BorderSide(
          color: colors.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Padding(
        padding: spacing.insetsMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: spacing.insetsXs,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: radii.borderSm,
                  ),
                  child: Icon(
                    Icons.school_rounded,
                    color: colors.onPrimary,
                    size: 20,
                  ),
                ),
                SizedBox(width: spacing.sm),
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
                          color: colors.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Divider(height: spacing.md),
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
                        color: colors.outline,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: spacing.symmetric(
                    horizontal: spacing.xs,
                    vertical: spacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: radii.borderSm,
                  ),
                  child: Text(
                    'Bit #$bitIndexFormatted',
                    style: TextStyle(
                      color: colors.onPrimary,
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
    required BuildContext context,
    bool isMonospace = false,
    bool isHighlight = false,
  }) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final spacing = AppSpacing.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          icon,
          size: 18,
          color: isHighlight ? colors.statusNormal : colors.primary,
        ),
        SizedBox(width: spacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.outline,
                ),
              ),
              SizedBox(height: spacing.xxs / 2),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: isMonospace ? 'monospace' : null,
                  fontWeight: isHighlight ? FontWeight.bold : FontWeight.w500,
                  color: isHighlight ? colors.statusNormal : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
