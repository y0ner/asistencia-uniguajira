import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/attendance_record_model.dart';
import '../../core/models/course_model.dart';
import '../../core/models/student_model.dart';
import '../../data/local/app_database.dart';
import '../../data/services/attendance_session_controller.dart';
import '../../data/services/ble_attendance_service.dart';
import '../../data/services/ble_permission_service.dart';
import '../../ui/ui.dart';
import 'signed_acta_dialog.dart';

/// Filtro de visualización de la lista de asistencia.
enum _AttendanceFilter { all, missing, present }

typedef _Palette = UiColors;

/// Pantalla de Sesión de Asistencia Docente en Vivo.
///
/// Permite al docente monitorear la asistencia de los estudiantes en tiempo real,
/// verificar llegadas por Bluetooth, marcar o editar notas de asistencia a mano,
/// y cerrar y firmar la sesión de la clase.
class LiveAttendanceSessionScreen extends StatefulWidget {
  const LiveAttendanceSessionScreen({
    super.key,
    required this.course,
    this.database,
    this.controller,
    this.bleService,
    this.permissionService,
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

  /// Servicio de permisos BLE inyectable para pruebas.
  final BlePermissionService? permissionService;

  /// PIN verbal personalizado de prueba (10..99).
  final int? customPin;

  @override
  State<LiveAttendanceSessionScreen> createState() =>
      _LiveAttendanceSessionScreenState();
}

class _LiveAttendanceSessionScreenState
    extends State<LiveAttendanceSessionScreen> {
  late final AppDatabase _database;
  late final BleAttendanceService _bleService;
  late final BlePermissionService _permissionService;
  late final AttendanceSessionController _controller;
  late final bool _ownsController;

  bool _isStarting = true;
  bool _isClosing = false;
  String? _initError;
  BlePermissionResult? _permissionResult;
  BleRuntimeIssue? _lastBleIssue;

  List<StudentModel> _students = <StudentModel>[];
  Map<String, AttendanceRecordModel> _recordsByStudentId =
      <String, AttendanceRecordModel>{};

  StreamSubscription<BlePacketEvent>? _bleEventsSub;
  StreamSubscription<BleRuntimeIssue>? _bleIssuesSub;
  Timer? _periodicRefreshTimer;

  _AttendanceFilter _selectedFilter = _AttendanceFilter.all;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  late final DateTime _sessionStartTime;

  @override
  void initState() {
    super.initState();
    _sessionStartTime = DateTime.now();
    unawaited(WakelockPlus.enable());
    _database = widget.database ?? AppDatabase.instance;
    _bleService = widget.bleService ?? BleAttendanceService();
    _permissionService =
        widget.permissionService ?? BlePermissionService();
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
    unawaited(WakelockPlus.disable());
    _searchController.dispose();
    _periodicRefreshTimer?.cancel();
    _bleEventsSub?.cancel();
    _bleIssuesSub?.cancel();
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  Future<void> _initializeSession() async {
    setState(() {
      _isStarting = true;
      _initError = null;
      _permissionResult = null;
    });

    try {
      final permResult = await _permissionService.ensureReady();
      if (!permResult.isReady) {
        if (mounted) {
          setState(() {
            _permissionResult = permResult;
            _isStarting = false;
          });
        }
        return;
      }

      final studentsList =
          await _database.getStudentsByCourse(widget.course.id);
      studentsList.sort(
        (StudentModel a, StudentModel b) => a.bitIndex.compareTo(b.bitIndex),
      );

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

      _bleEventsSub = _bleService.packetEvents.listen((_) {
        Future<void>.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            _reloadRecords();
          }
        });
      });

      _bleIssuesSub = _bleService.issues.listen((issue) {
        if (mounted) {
          setState(() {
            _lastBleIssue = issue;
          });
        }
      });

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
    } catch (e) {
      debugPrint('Aviso transitorio al recargar registros de asistencia: $e');
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
      showUiSnack(context, 'No se pudo actualizar la asistencia: $e');
    }
  }

  Future<void> _handleMarkStudent(StudentModel student) async {
    await _handleToggleManual(student, true);
    if (!mounted) return;
    await _showObservationSheet(student, isEditing: false);
  }

  Future<void> _showObservationSheet(
    StudentModel student, {
    required bool isEditing,
  }) async {
    final currentRecord = _recordsByStudentId[student.id];
    final textController =
        TextEditingController(text: currentRecord?.observation ?? '');

    await showUiSheet<void>(
      context,
      builder: (sheetContext) {
        final c = _Palette.of(sheetContext);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: UiSpace.lg),
            Text(
              isEditing ? 'Editar nota' : 'Nota (opcional)',
              style: UiText.h2.copyWith(color: c.ink),
            ),
            const SizedBox(height: UiSpace.xs),
            Text(
              student.fullName,
              style: UiText.caption.copyWith(color: c.muted),
            ),
            const SizedBox(height: UiSpace.md),
            TextField(
              controller: textController,
              autofocus: true,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'No trajo celular',
              ),
            ),
            const SizedBox(height: UiSpace.lg),
            Row(
              children: [
                Expanded(
                  child: UiButton(
                    label: isEditing ? 'Cancelar' : 'Omitir',
                    variant: UiButtonVariant.outline,
                    onPressed: () => Navigator.of(sheetContext).pop(),
                  ),
                ),
                const SizedBox(width: UiSpace.md),
                Expanded(
                  child: UiButton(
                    label: 'Guardar',
                    variant: UiButtonVariant.primary,
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      final obs = textController.text.trim();
                      _handleToggleManual(
                        student,
                        true,
                        observation: obs.isEmpty ? null : obs,
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _showManualActionSheet(StudentModel student) async {
    final action = await showUiSheet<String>(
      context,
      builder: (sheetContext) {
        final c = _Palette.of(sheetContext);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: UiSpace.lg),
            Text(
              student.fullName,
              style: UiText.h2.copyWith(color: c.ink),
            ),
            const SizedBox(height: UiSpace.xs),
            Text(
              'Asistencia registrada a mano',
              style: UiText.caption.copyWith(color: c.muted),
            ),
            const SizedBox(height: UiSpace.lg),
            UiButton(
              label: 'Editar nota',
              variant: UiButtonVariant.tonal,
              icon: Icons.edit_outlined,
              onPressed: () => Navigator.of(sheetContext).pop('edit'),
            ),
            const SizedBox(height: UiSpace.sm),
            UiButton(
              label: 'Quitar marca',
              variant: UiButtonVariant.outline,
              icon: Icons.remove_circle_outline_rounded,
              onPressed: () => Navigator.of(sheetContext).pop('remove'),
            ),
          ],
        );
      },
    );

    if (!mounted || action == null) return;

    if (action == 'remove') {
      await _handleToggleManual(student, false);
    } else if (action == 'edit') {
      await _showObservationSheet(student, isEditing: true);
    }
  }

  Future<bool> _confirmLeaveSession() {
    return showUiConfirm(
      context,
      title: '¿Salir de la sesión?',
      message: 'La sesión sigue abierta. Puedes volver desde la clase.',
      confirmLabel: 'Salir',
      cancelLabel: 'Seguir aquí',
    );
  }

  Future<void> _handleBackPress() async {
    final shouldLeave = await _confirmLeaveSession();
    if (shouldLeave && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleCloseAndSignSession() async {
    final state = _controller.state;
    if (state == null || !state.isOpen) {
      showUiSnack(context, 'La sesión ya ha sido cerrada.');
      return;
    }

    final presentCount = _recordsByStudentId.length;
    final totalCount = _students.length;
    final missingCount = totalCount - presentCount;

    final confirmed = await showUiConfirm(
      context,
      title: '¿Cerrar la sesión?',
      message:
          'Llegaron $presentCount de $totalCount. Los $missingCount que faltan quedarán con falta. Después de firmar no se puede cambiar.',
      confirmLabel: 'Cerrar y firmar',
      cancelLabel: 'Cancelar',
    );

    if (!confirmed || !mounted) {
      return;
    }

    setState(() => _isClosing = true);

    try {
      final signedActa = await _controller.closeAndSignSession();
      unawaited(WakelockPlus.disable());
      if (!mounted) return;

      setState(() => _isClosing = false);

      await SignedActaDialog.show(
        context,
        acta: signedActa,
        courseSecretHex: widget.course.courseSecret,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isClosing = false);
      showUiSnack(context, 'No se pudo cerrar la sesión: $e');
    }
  }

  List<StudentModel> _getFilteredStudents() {
    final query = _searchQuery.trim().toLowerCase();

    var list = _students;
    if (query.isNotEmpty) {
      list = list.where((s) {
        return s.fullName.toLowerCase().contains(query) ||
            s.studentCode.toLowerCase().contains(query);
      }).toList();
    }

    switch (_selectedFilter) {
      case _AttendanceFilter.missing:
        return list
            .where((s) => !_recordsByStudentId.containsKey(s.id))
            .toList();
      case _AttendanceFilter.present:
        final recent = <StudentModel>[];
        final others = <StudentModel>[];
        final now = DateTime.now();
        for (final s in list) {
          final r = _recordsByStudentId[s.id];
          if (r == null) continue;
          final t = DateTime.tryParse(r.recordedAt);
          if (t != null && now.difference(t).inSeconds.abs() < 10) {
            recent.add(s);
          } else {
            others.add(s);
          }
        }
        return [...recent, ...others];
      case _AttendanceFilter.all:
        final recent = <StudentModel>[];
        final others = <StudentModel>[];
        final now = DateTime.now();
        for (final s in list) {
          final r = _recordsByStudentId[s.id];
          if (r != null) {
            final t = DateTime.tryParse(r.recordedAt);
            if (t != null && now.difference(t).inSeconds.abs() < 10) {
              recent.add(s);
              continue;
            }
          }
          others.add(s);
        }
        return [...recent, ...others];
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _Palette.of(context);

    if (_isStarting) {
      return UiPage(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: UiSpace.lg),
              Text(
                'Abriendo la sesión…',
                style: UiText.bodyStrong.copyWith(color: c.ink),
              ),
            ],
          ),
        ),
      );
    }

    if (_permissionResult != null && !_permissionResult!.isReady) {
      final perm = _permissionResult!;
      final isBluetoothOff = perm.onlyBluetoothOff;
      final title =
          isBluetoothOff ? 'El Bluetooth está apagado' : 'Falta un permiso';
      // El texto lo decide la pantalla: el del servicio repite el título.
      final message = isBluetoothOff
          ? 'Enciéndelo para que tus estudiantes puedan registrarse.'
          : perm.requiresAppSettings
              ? 'Abre los ajustes y permite «Dispositivos cercanos» para tomar asistencia.'
              : 'Permite el acceso a «Dispositivos cercanos» para tomar asistencia.';

      return UiPage(
        header: UiTopBar(
          title: widget.course.name,
          onBack: () => Navigator.of(context).pop(),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(UiSpace.xxxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.tint,
                    borderRadius: BorderRadius.circular(UiRadius.xxl),
                  ),
                  child: Icon(
                    isBluetoothOff
                        ? Icons.bluetooth_disabled_rounded
                        : Icons.security_update_warning_rounded,
                    size: 40,
                    color: c.tintText,
                  ),
                ),
                const SizedBox(height: UiSpace.xl),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: UiText.h2.copyWith(color: c.ink),
                ),
                const SizedBox(height: UiSpace.sm),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: UiText.body.copyWith(color: c.muted),
                ),
                const SizedBox(height: UiSpace.xl),
                if (perm.requiresAppSettings) ...[
                  UiButton(
                    label: 'Abrir ajustes',
                    onPressed: () async {
                      await _permissionService.openAppSettings();
                    },
                  ),
                  const SizedBox(height: UiSpace.sm),
                ] else if (isBluetoothOff) ...[
                  UiButton(
                    label: 'Encender Bluetooth',
                    onPressed: () async {
                      await _permissionService.turnOnBluetooth();
                      await _initializeSession();
                    },
                  ),
                  const SizedBox(height: UiSpace.sm),
                ],
                UiButton(
                  label: 'Volver a intentar',
                  variant: UiButtonVariant.outline,
                  onPressed: _initializeSession,
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_initError != null) {
      return UiPage(
        header: UiTopBar(
          title: widget.course.name,
          onBack: () => Navigator.of(context).pop(),
        ),
        body: UiEmptyState(
          title: 'No se pudo abrir la sesión',
          message: _initError!,
          icon: Icons.error_outline_rounded,
          actionLabel: 'Volver a intentar',
          onAction: _initializeSession,
        ),
      );
    }

    final activeState = _controller.state;
    final pinStr = activeState?.sessionPin ??
        (widget.customPin?.toString().padLeft(2, '0') ?? '00');

    final presentCount = _recordsByStudentId.length;
    final totalStudents = _students.length;
    final missingCount = totalStudents - presentCount;

    final displayedStudents = _getFilteredStudents();

    final bleWarning = _controller.bleWarning;
    final hasBleIssue =
        _lastBleIssue != null || (bleWarning != null && bleWarning.isNotEmpty);
    final bleIssueMessage = _lastBleIssue?.message ?? bleWarning ?? '';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        await _handleBackPress();
      },
      child: UiPage(
        header: UiTopBar(
          title: widget.course.name,
          close: true,
          backTooltip: 'Salir de la sesión',
          onBack: _handleBackPress,
          // Bajo el título y no a la derecha: así el nombre de la clase no se corta.
          below: Align(
            alignment: Alignment.centerLeft,
            child: UiPill(
              label: 'En vivo · ${UiFormat.time(_sessionStartTime)}',
              dot: true,
            ),
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: UiSpace.page),
              child: UiCard(
                radius: UiRadius.xl,
                padding: const EdgeInsets.all(UiSpace.lg),
                child: Row(
                  children: [
                    UiProgressRing.count(
                      count: presentCount,
                      total: totalStudents,
                    ),
                    const SizedBox(width: UiSpace.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'PIN de la clase',
                            style: UiText.caption.copyWith(
                              color: c.muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: UiSpace.xs),
                          UiPinDisplay(pin: pinStr),
                          const SizedBox(height: UiSpace.xs),
                          Text(
                            'Díctalo en voz alta',
                            style: UiText.caption.copyWith(color: c.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (hasBleIssue) ...[
              const SizedBox(height: UiSpace.sm),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: UiSpace.page),
                child: UiBanner(
                  tone: UiBannerTone.warning,
                  message: bleIssueMessage,
                  actionLabel: _lastBleIssue?.type == BleRuntimeIssueType.adapterOff
                      ? 'Encender Bluetooth'
                      : (_lastBleIssue?.type == BleRuntimeIssueType.permission
                          ? 'Abrir ajustes'
                          : null),
                  onAction: _lastBleIssue?.type == BleRuntimeIssueType.adapterOff
                      ? () async {
                          await _permissionService.turnOnBluetooth();
                          await _reloadRecords();
                        }
                      : (_lastBleIssue?.type == BleRuntimeIssueType.permission
                          ? () async {
                              await _permissionService.openAppSettings();
                            }
                          : null),
                ),
              ),
            ],
            const SizedBox(height: UiSpace.md),
            UiFilterPills<_AttendanceFilter>(
              options: [
                UiFilterOption(
                  value: _AttendanceFilter.all,
                  label: 'Todos $totalStudents',
                ),
                UiFilterOption(
                  value: _AttendanceFilter.missing,
                  label: 'Faltan $missingCount',
                ),
                UiFilterOption(
                  value: _AttendanceFilter.present,
                  label: 'Llegaron $presentCount',
                ),
              ],
              selected: _selectedFilter,
              onSelected: (filter) => setState(() => _selectedFilter = filter),
            ),
            if (totalStudents > 12) ...[
              const SizedBox(height: UiSpace.sm),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: UiSpace.page),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _searchQuery = value),
                  decoration: InputDecoration(
                    hintText: 'Buscar estudiante',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                  ),
                ),
              ),
            ],
            if (presentCount == 0 && totalStudents > 0) ...[
              const SizedBox(height: UiSpace.sm),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: UiSpace.page),
                child: UiBanner(
                  tone: UiBannerTone.info,
                  message:
                      'Dicta el PIN y pide a tus estudiantes que acerquen el celular al tuyo.',
                ),
              ),
            ],
            const SizedBox(height: UiSpace.sm),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: UiSpace.page),
                child: Material(
                  color: c.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(UiRadius.lg),
                    side: BorderSide(color: c.line),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _buildStudentList(context, displayedStudents),
                ),
              ),
            ),
          ],
        ),
        bottom: UiButton(
          label: 'Cerrar y firmar la sesión',
          loading: _isClosing,
          onPressed: _isClosing ? null : _handleCloseAndSignSession,
        ),
      ),
    );
  }

  Widget _buildStudentList(
    BuildContext context,
    List<StudentModel> displayedStudents,
  ) {
    if (displayedStudents.isEmpty) {
      if (_selectedFilter == _AttendanceFilter.missing) {
        return const UiEmptyState(
          title: 'Ya llegaron todos',
          message: 'Todos los estudiantes de la clase están presentes.',
          icon: Icons.check_circle_outline_rounded,
        );
      }
      if (_selectedFilter == _AttendanceFilter.present) {
        return const UiEmptyState(
          title: 'Aún no llega nadie',
          message: 'Los estudiantes aparecerán aquí cuando confirmen.',
          icon: Icons.people_outline_rounded,
        );
      }
      return const UiEmptyState(
        title: 'Sin resultados',
        message: 'No encontramos estudiantes con ese nombre o código.',
        icon: Icons.search_off_rounded,
      );
    }

    final c = _Palette.of(context);
    return ListView.separated(
      itemCount: displayedStudents.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        thickness: 1,
        color: c.line,
      ),
      itemBuilder: (context, index) {
        final student = displayedStudents[index];
        final record = _recordsByStudentId[student.id];
        return _buildStudentRow(context, student, record);
      },
    );
  }

  Widget _buildStudentRow(
    BuildContext context,
    StudentModel student,
    AttendanceRecordModel? record,
  ) {
    if (record == null) {
      return UiPersonRow(
        name: student.fullName,
        subtitle: 'Aún no llega',
        avatarTone: UiTone.neutral,
        trailing: UiButton(
          label: 'Marcar',
          variant: UiButtonVariant.outline,
          compact: true,
          expand: false,
          onPressed: () => _handleMarkStudent(student),
        ),
      );
    }

    final recordedTime = DateTime.tryParse(record.recordedAt);
    final timeStr = recordedTime != null ? UiFormat.time(recordedTime) : '';

    if (record.method == AppConstants.attendanceMethodBleHmac) {
      final isRecent = recordedTime != null &&
          DateTime.now().difference(recordedTime).inSeconds.abs() < 10;
      final subtitle = isRecent
          ? 'Acaba de llegar · Bluetooth'
          : (timeStr.isNotEmpty ? '$timeStr · Bluetooth' : 'Bluetooth');

      return UiPersonRow(
        name: student.fullName,
        subtitle: subtitle,
        avatarTone: UiTone.tint,
        highlighted: isRecent,
        trailing: UiStatusChip(
          status: UiStatus.present,
          solid: isRecent,
        ),
      );
    }

    // Marcado a mano
    final note = record.observation;
    final prefix = timeStr.isNotEmpty ? '$timeStr · ' : '';
    final subtitle = (note != null && note.isNotEmpty)
        ? '$prefix$note'
        : '${prefix}A mano';

    return UiPersonRow(
      name: student.fullName,
      subtitle: subtitle,
      avatarTone: UiTone.manual,
      trailing: const UiStatusChip(status: UiStatus.manual),
      onTap: () => _showManualActionSheet(student),
    );
  }
}
