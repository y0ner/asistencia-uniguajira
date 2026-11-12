import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/crypto/ble_packet_codec.dart';
import '../../core/models/student_enrollment_model.dart';
import '../../data/local/app_database.dart';
import '../../data/services/attendance_session_controller.dart';
import '../../data/services/ble_attendance_service.dart';
import '../../data/services/ble_permission_service.dart';
import '../../ui/ui.dart';

extension on BuildContext {
  UiColors get uiColors => Theme.of(this).extension<UiColors>()!;
}

/// Fases del flujo de emisión y confirmación de asistencia en el estudiante.
enum StudentBeaconPhase {
  /// Paso 1: Ingreso del PIN dictado por el profesor en el aula.
  inputPin,

  /// Paso 2: Emitiendo anuncio y buscando al profesor.
  broadcasting,

  /// Paso 3: Asistencia confirmada.
  confirmed,
}

/// Pantalla de asistencia en vivo para el estudiante (PIN -> Acercar -> ¡Presente!).
class StudentLiveBeaconScreen extends StatefulWidget {
  const StudentLiveBeaconScreen({
    super.key,
    required this.enrollment,
    this.bleService,
    this.sessionController,
    this.permissionService,
    this.database,
  });

  /// Credencial local del estudiante para este curso.
  final StudentEnrollmentModel enrollment;

  /// Servicio BLE inyectable para pruebas o mocks.
  final BleAttendanceService? bleService;

  /// Controlador de sesión inyectable para verificar la confirmación.
  final AttendanceSessionController? sessionController;

  /// Servicio de permisos BLE inyectable para pruebas.
  final BlePermissionService? permissionService;

  /// Base de datos local inyectable.
  final AppDatabase? database;

  @override
  State<StudentLiveBeaconScreen> createState() =>
      _StudentLiveBeaconScreenState();
}

class _StudentLiveBeaconScreenState extends State<StudentLiveBeaconScreen> {
  late final BleAttendanceService _bleService;
  late final bool _ownsBleService;
  late final BlePermissionService _permissionService;
  late final AttendanceSessionController _sessionController;
  late final bool _ownsSessionController;

  StudentBeaconPhase _phase = StudentBeaconPhase.inputPin;

  String _pin = '';
  bool _pinHasError = false;

  int? _sessionPin;
  StreamSubscription<BlePacketEvent>? _bleSubscription;
  StreamSubscription<BleRuntimeIssue>? _bleIssuesSubscription;
  Timer? _tickerTimer;
  DateTime _now = DateTime.now();
  DateTime? _broadcastingStartedAt;
  int _currentTick = 0;
  int? _lastEmittedTick;
  int? _lastTeacherRssi;

  StudentConfirmationOutcome? _confirmationOutcome;
  DateTime? _confirmedAt;

  /// Resultado de la confirmación recibido del docente.
  StudentConfirmationOutcome? get confirmationOutcome => _confirmationOutcome;

  String? _bleWarning;
  BlePermissionResult? _permissionResult;
  bool _isProcessingPacket = false;

  @override
  void initState() {
    super.initState();
    unawaited(WakelockPlus.enable());
    _bleService = widget.bleService ?? BleAttendanceService();
    _ownsBleService = widget.bleService == null;

    final db = widget.database ?? AppDatabase.instance;
    _sessionController =
        widget.sessionController ??
        AttendanceSessionController(database: db, bleService: _bleService);
    _ownsSessionController = widget.sessionController == null;

    _permissionService =
        widget.permissionService ?? BlePermissionService();

    _bleIssuesSubscription = _bleService.issues.listen((BleRuntimeIssue issue) {
      if (mounted) {
        setState(() {
          _bleWarning = issue.message;
        });
      }
    });
  }

  @override
  void dispose() {
    unawaited(WakelockPlus.disable());
    _tickerTimer?.cancel();
    _bleSubscription?.cancel();
    _bleIssuesSubscription?.cancel();

    if (_phase == StudentBeaconPhase.broadcasting) {
      unawaited(_bleService.stopAdvertising());
      unawaited(_bleService.stopScan());
    }

    if (_ownsSessionController) {
      unawaited(_sessionController.dispose());
    } else if (_ownsBleService) {
      unawaited(_bleService.dispose());
    }

    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Lógica de Protocolo y Confirmación
  // ---------------------------------------------------------------------------

  Future<void> _startBroadcasting(int pin) async {
    final permResult = await _permissionService.ensureReady();
    if (!permResult.isReady) {
      if (mounted) {
        setState(() {
          _permissionResult = permResult;
          _bleWarning = permResult.failureMessage;
        });
      }
      return;
    }

    _permissionResult = null;
    _sessionPin = pin;
    _now = DateTime.now();
    _broadcastingStartedAt = _now;
    _currentTick = BlePacketCodec.computeTimeTick(_now);
    _lastEmittedTick = _currentTick;
    _lastTeacherRssi = null;

    final packet = BlePacketCodec.buildStudentBeaconBytes(
      courseId: widget.enrollment.courseId,
      bitIndex: widget.enrollment.bitIndex,
      sessionPin: pin,
      secretHex: widget.enrollment.deviceSecret,
      timeTick: _currentTick,
    );

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
          _bleWarning = 'Aviso de conexión: $error';
        });
      },
    );

    try {
      await _bleService.startAdvertisingPacket(packet);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bleWarning = 'No se pudo emitir la señal: $e';
      });
    }

    try {
      await _bleService.startScan();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bleWarning ??= 'No se pudo iniciar la búsqueda: $e';
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
    } catch (e) {
      if (mounted) {
        setState(() {
          _bleWarning = 'Error al actualizar la señal: $e';
        });
      }
    }
  }

  Future<void> _handleIncomingPacket(Uint8List packet16, int rssi) async {
    if (_phase != StudentBeaconPhase.broadcasting ||
        _isProcessingPacket ||
        _sessionPin == null) {
      return;
    }
    _isProcessingPacket = true;
    _lastTeacherRssi = rssi;
    if (mounted) setState(() {});
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
    } catch (e) {
      debugPrint('Paquete descartado durante verificación: $e');
    } finally {
      _isProcessingPacket = false;
    }
  }

  Future<void> _onConfirmed(StudentConfirmationOutcome outcome) async {
    unawaited(WakelockPlus.disable());
    _tickerTimer?.cancel();
    _tickerTimer = null;
    unawaited(_bleSubscription?.cancel());
    _bleSubscription = null;

    try {
      await _bleService.stopAdvertising();
    } catch (e) {
      debugPrint('Aviso al detener anuncio tras confirmación: $e');
    }
    try {
      await _bleService.stopScan();
    } catch (e) {
      debugPrint('Aviso al detener escaneo tras confirmación: $e');
    }

    try {
      await HapticFeedback.mediumImpact();
    } catch (e) {
      debugPrint('Aviso de vibración no disponible: $e');
    }

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
    unawaited(_bleSubscription?.cancel());
    _bleSubscription = null;

    try {
      await _bleService.stopAdvertising();
    } catch (e) {
      debugPrint('Aviso al detener anuncio en cancelación: $e');
    }
    try {
      await _bleService.stopScan();
    } catch (e) {
      debugPrint('Aviso al detener escaneo en cancelación: $e');
    }

    if (!mounted) return;
    setState(() {
      _phase = StudentBeaconPhase.inputPin;
      _sessionPin = null;
      _bleWarning = null;
      _broadcastingStartedAt = null;
      _lastTeacherRssi = null;
    });
  }

  void _onDigit(String d) {
    if (_pin.length >= 2) return;
    final next = _pin + d;
    setState(() {
      _pin = next;
      if (next.length == 2) {
        final parsed = int.tryParse(next);
        _pinHasError = parsed != null && parsed < 10;
      } else {
        _pinHasError = false;
      }
    });
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _pinHasError = false;
    });
  }

  int _computeSignal() {
    final rssi = _lastTeacherRssi;
    if (rssi == null) return 1;
    if (rssi >= -65) return 3;
    if (rssi >= -80) return 2;
    return 1;
  }

  String _signalText(int signal) => switch (signal) {
    3 => 'Señal fuerte: ya casi',
    2 => 'Señal media: acércate un poco más',
    _ => 'Señal débil: acércate más',
  };

  Duration get _elapsed => _broadcastingStartedAt != null
      ? _now.difference(_broadcastingStartedAt!)
      : Duration.zero;

  // ---------------------------------------------------------------------------
  // Construcción de la Interfaz
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colors = context.uiColors;
    final step = switch (_phase) {
      StudentBeaconPhase.inputPin => 1,
      StudentBeaconPhase.broadcasting => 2,
      StudentBeaconPhase.confirmed => 3,
    };

    return PopScope(
      canPop: _phase != StudentBeaconPhase.broadcasting,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop && _phase == StudentBeaconPhase.broadcasting) {
          _cancelBroadcasting();
        }
      },
      child: UiPage(
        header: UiTopBar(
          title: widget.enrollment.courseName,
          onBack: () {
            if (_phase == StudentBeaconPhase.broadcasting) {
              _cancelBroadcasting();
            } else {
              Navigator.of(context).pop();
            }
          },
          below: UiStepBar(current: step, total: 3),
          trailing: Text(
            'Paso $step de 3',
            style: UiText.label.copyWith(color: colors.muted),
          ),
        ),
        body: switch (_phase) {
          StudentBeaconPhase.inputPin => _buildInputPinStep(context),
          StudentBeaconPhase.broadcasting => _buildBroadcastingStep(context),
          StudentBeaconPhase.confirmed => _buildConfirmedStep(context),
        },
        bottom: switch (_phase) {
          StudentBeaconPhase.inputPin => _buildInputPinBottom(context),
          StudentBeaconPhase.broadcasting => _buildBroadcastingBottom(context),
          StudentBeaconPhase.confirmed => _buildConfirmedBottom(context),
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Paso 1: PIN
  // ---------------------------------------------------------------------------

  Widget _buildInputPinStep(BuildContext context) {
    final colors = context.uiColors;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const UiPageHeading(
                    title: 'Escribe el PIN que dictó tu profesor',
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: UiSpace.page),
                    child: UiPinEntry(
                      value: _pin,
                      hasError: _pinHasError,
                    ),
                  ),
                  if (_pinHasError)
                    Padding(
                      padding: const EdgeInsets.only(
                        top: UiSpace.sm,
                        left: UiSpace.page,
                        right: UiSpace.page,
                      ),
                      child: Text(
                        'El PIN tiene dos dígitos, entre 10 y 99.',
                        style: UiText.label.copyWith(color: colors.absentText),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (_permissionResult != null && !_permissionResult!.isReady)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        UiSpace.page,
                        UiSpace.md,
                        UiSpace.page,
                        0,
                      ),
                      child: _buildPermissionWarning(context),
                    ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: UiPinKeypad(
                      onDigit: _onDigit,
                      onBackspace: _onBackspace,
                    ),
                  ),
                  const SizedBox(height: UiSpace.md),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPermissionWarning(BuildContext context) {
    final res = _permissionResult!;
    final isBtOff = res.onlyBluetoothOff;
    final parsed = int.tryParse(_pin);
    final isValidPin = parsed != null && parsed >= 10 && _pin.length == 2;

    return UiCard(
      tone: UiTone.manual,
      radius: UiRadius.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                isBtOff
                    ? Icons.bluetooth_disabled
                    : Icons.security_update_warning_outlined,
                size: 22,
              ),
              const SizedBox(width: UiSpace.sm),
              Expanded(
                child: Text(
                  isBtOff
                      ? 'El Bluetooth está apagado'
                      : 'Falta un permiso',
                  style: UiText.bodyStrong,
                ),
              ),
            ],
          ),
          const SizedBox(height: UiSpace.xs),
          Text(
            isBtOff
                ? 'Enciéndelo para registrar tu asistencia.'
                : res.requiresAppSettings
                    ? 'Abre los ajustes y permite «Dispositivos cercanos» para registrar tu asistencia.'
                    : 'Permite el acceso a «Dispositivos cercanos» para registrar tu asistencia.',
            style: UiText.label,
          ),
          const SizedBox(height: UiSpace.md),
          if (isBtOff) ...[
            UiButton(
              label: 'Encender Bluetooth',
              compact: true,
              onPressed: () async {
                await _permissionService.turnOnBluetooth();
                if (isValidPin) {
                  await _startBroadcasting(parsed);
                } else {
                  final updated = await _permissionService.ensureReady();
                  if (mounted) setState(() => _permissionResult = updated);
                }
              },
            ),
            const SizedBox(height: UiSpace.sm),
          ] else if (res.requiresAppSettings) ...[
            UiButton(
              label: 'Abrir ajustes',
              compact: true,
              onPressed: () => _permissionService.openAppSettings(),
            ),
            const SizedBox(height: UiSpace.sm),
          ],
          UiButton(
            label: 'Volver a intentar',
            compact: true,
            variant: UiButtonVariant.tonal,
            onPressed: () async {
              if (isValidPin) {
                await _startBroadcasting(parsed);
              } else {
                final updated = await _permissionService.ensureReady();
                if (mounted) setState(() => _permissionResult = updated);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInputPinBottom(BuildContext context) {
    return UiButton(
      label: 'Continuar',
      onPressed: _pin.length == 2
          ? () {
              final parsed = int.tryParse(_pin);
              if (parsed == null || parsed < 10) {
                setState(() {
                  _pinHasError = true;
                });
              } else {
                _startBroadcasting(parsed);
              }
            }
          : null,
    );
  }

  // ---------------------------------------------------------------------------
  // Paso 2: Acercar
  // ---------------------------------------------------------------------------

  Widget _buildBroadcastingStep(BuildContext context) {
    final colors = context.uiColors;
    final signal = _computeSignal();
    final elapsedSec = _elapsed.inSeconds;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: UiSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const UiPageHeading(
            title: 'Acerca tu celular al del profesor',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: UiSpace.page),
            child: UiCard(
              tone: UiTone.tint,
              radius: UiRadius.xxl,
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      spacing: UiSpace.sm,
                      runSpacing: UiSpace.sm,
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        UiPill(
                          label: 'PIN ${_sessionPin ?? ''}',
                          background: colors.surface,
                          foreground: colors.ink,
                        ),
                        const UiPill(
                          label: 'Buscando al profesor',
                          dot: true,
                          tone: UiTone.primary,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: UiSpace.xl),
                  UiTwoPhones(
                    signal: signal,
                    searching: true,
                  ),
                  const SizedBox(height: UiSpace.xl),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          _signalText(signal),
                          style: UiText.label.copyWith(
                            color: colors.tintText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: UiSpace.sm),
                      Text(
                        UiFormat.elapsed(_elapsed),
                        style: UiText.label.copyWith(
                          color: colors.tintText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              UiSpace.page,
              UiSpace.md,
              UiSpace.page,
              0,
            ),
            child: Text(
              'Deja esta pantalla abierta. Te avisamos apenas quedes registrado.',
              style: UiText.body.copyWith(color: colors.muted),
            ),
          ),
          if (elapsedSec >= 45)
            const Padding(
              padding: EdgeInsets.fromLTRB(
                UiSpace.page,
                UiSpace.md,
                UiSpace.page,
                0,
              ),
              child: UiBanner(
                tone: UiBannerTone.warning,
                message:
                    'Aún no te encuentra. Revisa que el PIN sea el correcto y acércate al celular del profesor.',
              ),
            ),
          if (_bleWarning != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                UiSpace.page,
                UiSpace.md,
                UiSpace.page,
                0,
              ),
              child: UiBanner(
                tone: UiBannerTone.warning,
                message: _bleWarning!,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBroadcastingBottom(BuildContext context) {
    return UiButton(
      label: 'Cambiar PIN',
      variant: UiButtonVariant.outline,
      onPressed: _cancelBroadcasting,
    );
  }

  // ---------------------------------------------------------------------------
  // Paso 3: ¡Presente!
  // ---------------------------------------------------------------------------

  Widget _buildConfirmedStep(BuildContext context) {
    final colors = context.uiColors;
    final confirmedAt = _confirmedAt ?? DateTime.now();

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: UiSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: UiSpace.page),
            child: UiHeroCard(
              motifSize: 220,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: colors.onPrimary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      size: 30,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(height: UiSpace.xxl),
                  Text(
                    'Asistencia registrada',
                    style: UiText.bodyStrong.copyWith(color: colors.onPrimary),
                  ),
                  const SizedBox(height: UiSpace.xs),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '¡Presente!',
                      style: UiText.display.copyWith(color: colors.onPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              UiSpace.page,
              UiSpace.md,
              UiSpace.page,
              0,
            ),
            child: UiListGroup(
              children: [
                UiInfoRow(
                  label: 'Clase',
                  value: widget.enrollment.courseName,
                ),
                UiInfoRow(
                  label: 'Fecha y hora',
                  value: UiFormat.shortDateTime(confirmedAt),
                ),
                const UiInfoRow(
                  label: 'Confirmó',
                  value: 'El celular del profesor',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              UiSpace.page,
              UiSpace.md,
              UiSpace.page,
              0,
            ),
            child: Text(
              'Ya puedes guardar el celular.',
              style: UiText.body.copyWith(color: colors.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmedBottom(BuildContext context) {
    return UiButton(
      label: 'Listo',
      onPressed: () => Navigator.of(context).pop(),
    );
  }
}
