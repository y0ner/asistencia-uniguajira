import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/crypto/ble_packet_codec.dart';
import '../../core/models/attendance_record_model.dart';
import '../../core/models/course_model.dart';
import '../../core/models/session_model.dart';
import '../../core/models/student_enrollment_model.dart';
import '../../core/models/student_model.dart';
import '../local/app_database.dart';
import 'ble_attendance_service.dart';

/// Estado vivo de una sesión de aula abierta por el docente.
///
/// [bitmap8] y [session] se actualizan in situ mientras el radar BLE y la
/// lista invertida avanzan; el resto del roster permanece inmutable durante la
/// sesión.
class ActiveCourseSessionState {
  ActiveCourseSessionState({
    required this.session,
    required this.course,
    required this.pin,
    required List<StudentModel> students,
    required this.bitmap8,
    required Map<int, String> secretHexByBitIndex,
  }) : assert(bitmap8.length == BlePacketCodec.bitmapLength),
       students = List<StudentModel>.unmodifiable(students),
       secretHexByBitIndex = Map<int, String>.unmodifiable(
         secretHexByBitIndex,
       ) {
    studentByBitIndex = Map<int, StudentModel>.unmodifiable(<int, StudentModel>{
      for (final StudentModel student in this.students)
        student.bitIndex: student,
    });
    studentById = Map<String, StudentModel>.unmodifiable(<String, StudentModel>{
      for (final StudentModel student in this.students) student.id: student,
    });
  }

  /// Fila de la sesión, actualizada con Bitmap y cierre.
  SessionModel session;

  /// Curso al que pertenece la sesión.
  final CourseModel course;

  /// PIN verbal generado (10..99).
  final int pin;

  /// Roster congelado al iniciar la sesión, ordenado por `bitIndex`.
  final List<StudentModel> students;

  /// Mapa de 64 bits que se actualiza al detectar o marcar estudiantes.
  final Uint8List bitmap8;

  /// Secreto personal (`deviceSecret`) indexado por posición del Bitmap.
  final Map<int, String> secretHexByBitIndex;

  /// Estudiantes indexados por su posición en el Bitmap.
  late final Map<int, StudentModel> studentByBitIndex;

  /// Estudiantes indexados por su identificador interno.
  late final Map<String, StudentModel> studentById;

  /// Último aviso de disponibilidad BLE, sin interrumpir la sesión local.
  String? bleWarning;

  /// Identificador de la sesión activa.
  String get sessionId => session.id;

  /// Identificador del curso.
  String get courseId => course.id;

  /// PIN de dos dígitos tal como se guarda en SQLite.
  String get sessionPin => session.roomPin;

  /// Representación hexadecimal del Bitmap actual.
  String get bitmapHex => _bitmapToHex(bitmap8);

  /// Indica si la sesión sigue aceptando detecciones.
  bool get isOpen => session.closedAt == null;

  /// Indica si la sesión ya fue cerrada.
  bool get isClosed => !isOpen;

  /// Cantidad total de estudiantes matriculados al iniciar la sesión.
  int get totalEnrolled => students.length;

  /// Posiciones encendidas en el Bitmap actual.
  List<int> get presentBitIndices =>
      BlePacketCodec.extractPresentBitIndices(bitmap8);
}

/// Resultado de procesar un anuncio BLE de estudiante.
class StudentDetectionOutcome {
  const StudentDetectionOutcome({
    required this.isAccepted,
    this.failureReason,
    this.student,
    this.record,
    this.verifyCode,
    this.bitIndex,
    this.rssi,
    this.timeTick,
    this.bitmapHex,
  });

  /// `true` si el paquete fue verificado y la asistencia quedó persistida.
  final bool isAccepted;

  /// Motivo del rechazo; `null` cuando [isAccepted] es `true`.
  final String? failureReason;

  /// Estudiante identificado por el Bitmap, cuando fue posible.
  final StudentModel? student;

  /// Registro persistido; `null` en un rechazo.
  final AttendanceRecordModel? record;

  /// Token auditable `UG-XXXXXXXX`; `null` en un rechazo.
  final String? verifyCode;

  /// Posición del estudiante en el Bitmap.
  final int? bitIndex;

  /// RSSI del anuncio recibido.
  final int? rssi;

  /// Tick local usado para verificar y firmar la detección.
  final int? timeTick;

  /// Bitmap vigente después de la detección.
  final String? bitmapHex;

  /// Alias de compatibilidad para consumidores que usan `isValid`.
  bool get isValid => isAccepted;

  /// Alias de compatibilidad para consumidores que usan `isSuccess`.
  bool get isSuccess => isAccepted;

  /// Alias del registro persistido.
  AttendanceRecordModel? get attendanceRecord => record;

  /// Alias del token auditable.
  String? get token => verifyCode;
}

/// Resultado del Sello Verde consultado por el teléfono del estudiante.
class StudentConfirmationOutcome {
  const StudentConfirmationOutcome({
    required this.isConfirmed,
    this.failureReason,
    this.verifyCode,
    this.confirmedAt,
    this.bitmapHex,
    this.bitIndex,
    this.rssi,
    this.sessionPin,
  });

  /// `true` si el eco docente es auténtico y el bit del estudiante está en 1.
  final bool isConfirmed;

  /// Motivo por el que aún no hay Sello Verde.
  final String? failureReason;

  /// Token auditable `UG-XXXXXXXX`.
  final String? verifyCode;

  /// Instante de la confirmación.
  final DateTime? confirmedAt;

  /// Bitmap de 8 bytes recibido del docente, en hexadecimal.
  final String? bitmapHex;

  /// Posición del estudiante en el Bitmap.
  final int? bitIndex;

  /// RSSI del eco docente.
  final int? rssi;

  /// PIN verbal usado por el estudiante.
  final int? sessionPin;

  /// Alias semántico para la UI del Sello Verde.
  bool get isGreenSeal => isConfirmed;

  /// Alias de compatibilidad.
  bool get isValid => isConfirmed;

  /// Timestamp ISO8601 de confirmación, cuando existe.
  String? get confirmedAtIso => confirmedAt?.toIso8601String();

  /// Indica si el eco llegó dentro del umbral de proximidad del aula.
  bool get isNearby => rssi != null && rssi! >= AppConstants.minRssiDbm;

  /// Alias del token.
  String? get token => verifyCode;
}

/// Acta inmutable de cierre firmada con HMAC-SHA256.
class SignedSessionActa {
  SignedSessionActa({
    required this.sessionId,
    required this.courseId,
    required this.courseCode,
    required this.courseName,
    required this.sessionPin,
    required this.startedAtIso,
    required this.closedAtIso,
    required this.totalEnrolled,
    required this.presentBleCount,
    required this.presentManualCount,
    required this.absentCount,
    required this.bitmapHex,
    required List<SessionActaRecord> records,
    required this.actaHmacSignature,
  }) : records = List<SessionActaRecord>.unmodifiable(records);

  /// Identificador de la sesión cerrada.
  final String sessionId;

  /// Identificador del curso.
  final String courseId;

  /// Código institucional del curso.
  final String courseCode;

  /// Nombre del curso.
  final String courseName;

  /// PIN verbal de dos dígitos.
  final String sessionPin;

  /// Inicio de la sesión en ISO8601.
  final String startedAtIso;

  /// Cierre de la sesión en ISO8601.
  final String closedAtIso;

  /// Total de estudiantes matriculados.
  final int totalEnrolled;

  /// Presentes registrados por BLE.
  final int presentBleCount;

  /// Presentes registrados por la lista invertida.
  final int presentManualCount;

  /// Estudiantes sin registro de presencia.
  final int absentCount;

  /// Bitmap final de 8 bytes en hexadecimal de 16 caracteres.
  final String bitmapHex;

  /// Registros de todos los matriculados, ordenados por `bitIndex`.
  final List<SessionActaRecord> records;

  /// Firma HMAC-SHA256 hexadecimal del JSON canónico sin firma.
  final String actaHmacSignature;

  /// Devuelve una copia con la firma definitiva.
  SignedSessionActa copyWith({String? actaHmacSignature}) {
    return SignedSessionActa(
      sessionId: sessionId,
      courseId: courseId,
      courseCode: courseCode,
      courseName: courseName,
      sessionPin: sessionPin,
      startedAtIso: startedAtIso,
      closedAtIso: closedAtIso,
      totalEnrolled: totalEnrolled,
      presentBleCount: presentBleCount,
      presentManualCount: presentManualCount,
      absentCount: absentCount,
      bitmapHex: bitmapHex,
      records: records,
      actaHmacSignature: actaHmacSignature ?? this.actaHmacSignature,
    );
  }

  /// Mapa canónico que se firma: mismas claves y orden, sin la firma.
  Map<String, Object?> toCanonicalMap() {
    return <String, Object?>{
      'sessionId': sessionId,
      'courseId': courseId,
      'courseCode': courseCode,
      'courseName': courseName,
      'sessionPin': sessionPin,
      'startedAtIso': startedAtIso,
      'closedAtIso': closedAtIso,
      'totalEnrolled': totalEnrolled,
      'presentBleCount': presentBleCount,
      'presentManualCount': presentManualCount,
      'absentCount': absentCount,
      'bitmapHex': bitmapHex,
      'records': records
          .map((SessionActaRecord record) => record.toJson())
          .toList(growable: false),
    };
  }

  /// JSON canónico usado como mensaje de la firma HMAC.
  String get canonicalJson => jsonEncode(toCanonicalMap());

  /// Acta completa, incluyendo la firma.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      ...toCanonicalMap(),
      'actaHmacSignature': actaHmacSignature,
    };
  }

  /// Alias de [toJson] para consumidores de persistencia.
  Map<String, Object?> toMap() => toJson();

  /// Verifica la firma con el secreto compartido del curso.
  bool verifySignature(String courseSecretHex) {
    final expected = _signCanonicalJson(canonicalJson, courseSecretHex);
    return _constantTimeEquals(expected, actaHmacSignature.toLowerCase());
  }

  /// Alias de la firma.
  String get signature => actaHmacSignature;
}

/// Fila del reporte de cierre para un estudiante.
class SessionActaRecord {
  const SessionActaRecord({
    required this.bitIndex,
    required this.studentCode,
    required this.fullName,
    required this.status,
    this.method,
    this.verifyCode,
    this.rssi,
  });

  /// Estado de presencia usado en el acta.
  static const String presentStatus = AppConstants.attendanceStatusPresent;

  /// Estado de ausencia usado en el acta.
  static const String absentStatus = AppConstants.attendanceStatusAbsent;

  /// Posición fija en el Bitmap.
  final int bitIndex;

  /// Código institucional del estudiante.
  final String studentCode;

  /// Nombre completo normalizado.
  final String fullName;

  /// `PRESENT` o `ABSENT`.
  final String status;

  /// `BLE_HMAC` o `MANUAL_INVERTED`; `null` si está ausente.
  final String? method;

  /// Token `UG-XXXXXXXX` de una detección BLE.
  final String? verifyCode;

  /// RSSI de la detección BLE.
  final int? rssi;

  /// Indica si el estudiante quedó presente.
  bool get isPresent => status == presentStatus;

  /// Indica si el estudiante quedó ausente.
  bool get isAbsent => status == absentStatus;

  /// Serializa la fila con el contrato exacto del acta.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'bitIndex': bitIndex,
      'studentCode': studentCode,
      'fullName': fullName,
      'status': status,
      'method': method,
      'verifyCode': verifyCode,
      'rssi': rssi,
    };
  }
}

/// Coordina el flujo docente y estudiante de una sesión de aula.
///
/// Persiste cada transición en SQLite antes de publicar el nuevo Bitmap y
/// mantiene el radar BLE como una fuente adicional de detecciones. Los fallos
/// de hardware BLE no pierden la sesión local: se exponen en
/// [ActiveCourseSessionState.bleWarning] y la lista invertida sigue operativa.
class AttendanceSessionController {
  AttendanceSessionController({
    required this.database,
    BleAttendanceService? bleService,
  }) : _bleService = bleService ?? BleAttendanceService(),
       _ownsBleService = bleService == null;

  /// Base local compartida por los flujos docente y estudiante.
  final AppDatabase database;
  final BleAttendanceService _bleService;
  final bool _ownsBleService;
  final Uuid _uuid = const Uuid();
  final Random _random = Random.secure();

  ActiveCourseSessionState? _state;
  SignedSessionActa? _signedActa;
  StudentDetectionOutcome? _lastDetectionOutcome;
  StreamSubscription<BlePacketEvent>? _bleSubscription;
  StreamSubscription<BleRuntimeIssue>? _bleIssuesSubscription;
  Timer? _echoTimer;
  Future<void> _operationQueue = Future<void>.value();
  Future<void> _echoQueue = Future<void>.value();
  String? _lastBleWarning;
  String? _lastAsyncError;
  bool _closing = false;
  bool _disposed = false;

  /// Estado de la sesión actual, si existe.
  ActiveCourseSessionState? get activeSession => _state;

  /// Alias corto de [activeSession].
  ActiveCourseSessionState? get state => _state;

  /// Última detección procesada, incluyendo rechazos del radar.
  StudentDetectionOutcome? get lastDetectionOutcome => _lastDetectionOutcome;

  /// Última acta firmada en esta instancia.
  SignedSessionActa? get signedActa => _signedActa;

  /// Último aviso BLE no fatal.
  String? get bleWarning => _state?.bleWarning ?? _lastBleWarning;

  /// Stream de incidencias y anomalías de hardware o runtime BLE.
  Stream<BleRuntimeIssue> get bleIssues => _bleService.issues;

  /// Último error de una detección automática del Stream BLE.
  String? get lastAsyncError => _lastAsyncError;

  /// Abre una sesión docente, crea el Bitmap vacío y arranca el radar BLE.
  Future<ActiveCourseSessionState> startTeacherSession({
    required CourseModel course,
    int? customPin,
  }) {
    _ensureNotDisposed();
    return _serialize(
      () => _startTeacherSession(course: course, customPin: customPin),
    );
  }

  Future<ActiveCourseSessionState> _startTeacherSession({
    required CourseModel course,
    int? customPin,
  }) async {
    _ensureNotDisposed();
    final current = _state;
    if (current != null && current.isOpen) {
      throw StateError(
        'Ya hay una sesión abierta para el curso ${current.course.id}.',
      );
    }

    final pin = customPin ?? _generatePin();
    _validatePin(pin);
    await _stopBleRuntime();
    _signedActa = null;
    _lastDetectionOutcome = null;
    _lastBleWarning = null;
    _lastAsyncError = null;
    _closing = false;

    final students = await database.getStudentsByCourse(course.id);
    final secrets = <int, String>{
      for (final StudentModel student in students)
        student.bitIndex: student.personalSecret,
    };
    final startedAt = DateTime.now().toIso8601String();
    final session = SessionModel(
      id: _uuid.v4(),
      courseId: course.id,
      startedAt: startedAt,
      roomPin: pin.toString().padLeft(AppConstants.roomPinLength, '0'),
      bitmapHex: AppConstants.emptyBitmapHex,
    );
    await database.upsertSession(session);

    final activeState = ActiveCourseSessionState(
      session: session,
      course: course,
      pin: pin,
      students: students,
      bitmap8: BlePacketCodec.createEmptyBitmap8(),
      secretHexByBitIndex: secrets,
    );
    _state = activeState;
    _subscribeToBle();
    await _tryStartScan();
    await _publishTeacherEcho();
    return activeState;
  }

  /// Procesa un anuncio de estudiante y aplica la transacción de asistencia.
  Future<StudentDetectionOutcome> processIncomingStudentPacket({
    required Uint8List packet16,
    required int rssi,
    DateTime? nowOverride,
  }) {
    _ensureNotDisposed();
    return _serialize(
      () => _processIncomingStudentPacket(
        packet16: packet16,
        rssi: rssi,
        nowOverride: nowOverride,
      ),
    );
  }

  Future<StudentDetectionOutcome> _processIncomingStudentPacket({
    required Uint8List packet16,
    required int rssi,
    DateTime? nowOverride,
  }) async {
    _ensureNotDisposed();
    final state = _state;
    if (state == null || !state.isOpen || _closing) {
      return const StudentDetectionOutcome(
        isAccepted: false,
        failureReason: 'No hay una sesión docente abierta.',
      );
    }

    final now = nowOverride ?? DateTime.now();
    final currentTimeTick = BlePacketCodec.computeTimeTick(now);
    if (rssi < AppConstants.minRssiDbm) {
      return StudentDetectionOutcome(
        isAccepted: false,
        failureReason:
            'El RSSI $rssi dBm no alcanza el umbral '
            '${AppConstants.minRssiDbm} dBm.',
        rssi: rssi,
        timeTick: currentTimeTick,
        bitmapHex: state.bitmapHex,
      );
    }

    final verification = BlePacketCodec.verifyStudentBeaconBytes(
      packet16: packet16,
      expectedCourseId: state.course.id,
      expectedSessionPin: state.pin,
      secretHexByBitIndex: state.secretHexByBitIndex,
      currentTimeTick: currentTimeTick,
    );
    if (!verification.isValid) {
      return StudentDetectionOutcome(
        isAccepted: false,
        failureReason: verification.failureReason,
        bitIndex: verification.bitIndex,
        rssi: rssi,
        timeTick: verification.timeTick,
        bitmapHex: state.bitmapHex,
      );
    }

    final int? bitIndex = verification.bitIndex;
    final StudentModel? student = bitIndex == null
        ? null
        : state.studentByBitIndex[bitIndex];
    if (bitIndex == null || student == null) {
      return StudentDetectionOutcome(
        isAccepted: false,
        failureReason: 'El anuncio no corresponde a un estudiante matriculado.',
        bitIndex: bitIndex,
        rssi: rssi,
        timeTick: currentTimeTick,
        bitmapHex: state.bitmapHex,
      );
    }

    final nextBitmap = BlePacketCodec.setStudentBit(state.bitmap8, bitIndex);
    final bitmapHex = _bitmapToHex(nextBitmap);
    final verifyCode = BlePacketCodec.generateAttendanceVerifyCode(
      courseId: state.course.id,
      studentCode: student.studentCode,
      bitIndex: bitIndex,
      timeTick: currentTimeTick,
      secretHex: student.personalSecret,
    );
    final record = AttendanceRecordModel(
      id: _recordId(state.session.id, student.id),
      sessionId: state.session.id,
      studentId: student.id,
      bitIndex: bitIndex,
      method: AppConstants.attendanceMethodBleHmac,
      rssiAvg: rssi.toDouble(),
      recordedAt: now.toIso8601String(),
      hmacTag: verifyCode,
      timeTick: currentTimeTick,
    );

    await database.upsertAttendanceRecord(record, bitmapHex: bitmapHex);
    _applyBitmap(state, nextBitmap);
    state.session = state.session.copyWith(bitmapHex: bitmapHex);
    await _publishTeacherEcho();

    final outcome = StudentDetectionOutcome(
      isAccepted: true,
      student: student,
      record: record,
      verifyCode: verifyCode,
      bitIndex: bitIndex,
      rssi: rssi,
      timeTick: currentTimeTick,
      bitmapHex: bitmapHex,
    );
    _lastDetectionOutcome = outcome;
    return outcome;
  }

  /// Enciende o apaga la asistencia manual de un estudiante en la lista
  /// invertida, manteniendo Bitmap y SQLite en una sola transacción.
  Future<void> toggleManualAttendance({
    required String studentId,
    required bool isPresent,
    String? observation,
  }) {
    _ensureNotDisposed();
    return _serialize(
      () => _toggleManualAttendance(
        studentId: studentId,
        isPresent: isPresent,
        observation: observation,
      ),
    );
  }

  Future<void> _toggleManualAttendance({
    required String studentId,
    required bool isPresent,
    String? observation,
  }) async {
    _ensureNotDisposed();
    final state = _requireOpenState();
    if (_closing) {
      throw StateError('La sesión se está cerrando.');
    }
    final student = state.studentById[studentId];
    if (student == null) {
      throw ArgumentError.value(
        studentId,
        'studentId',
        'El estudiante no pertenece a la sesión activa.',
      );
    }

    final now = DateTime.now();
    final nextBitmap = isPresent
        ? BlePacketCodec.setStudentBit(state.bitmap8, student.bitIndex)
        : BlePacketCodec.clearStudentBit(state.bitmap8, student.bitIndex);
    final bitmapHex = _bitmapToHex(nextBitmap);

    if (isPresent) {
      final cleanObservation = observation?.trim();
      final record = AttendanceRecordModel(
        id: _recordId(state.session.id, student.id),
        sessionId: state.session.id,
        studentId: student.id,
        bitIndex: student.bitIndex,
        method: AppConstants.attendanceMethodManualInverted,
        recordedAt: now.toIso8601String(),
        timeTick: BlePacketCodec.computeTimeTick(now),
        observation: cleanObservation == null || cleanObservation.isEmpty
            ? null
            : cleanObservation,
      );
      await database.upsertAttendanceRecord(record, bitmapHex: bitmapHex);
    } else {
      await database.deleteAttendanceRecord(
        sessionId: state.session.id,
        studentId: student.id,
        bitmapHex: bitmapHex,
      );
    }

    _applyBitmap(state, nextBitmap);
    state.session = state.session.copyWith(bitmapHex: bitmapHex);
    await _publishTeacherEcho();
  }

  /// Cierra la sesión, persiste el acta firmada y devuelve su contrato.
  Future<SignedSessionActa> closeAndSignSession({DateTime? closedAtOverride}) {
    _ensureNotDisposed();
    return _serialize(
      () => _closeAndSignSession(closedAtOverride: closedAtOverride),
    );
  }

  Future<SignedSessionActa> _closeAndSignSession({
    DateTime? closedAtOverride,
  }) async {
    _ensureNotDisposed();
    final state = _state;
    if (state == null) {
      throw StateError('No hay una sesión docente para cerrar.');
    }
    final previous = _signedActa;
    if (previous != null) {
      return previous;
    }
    if (!state.isOpen) {
      throw StateError('La sesión ${state.session.id} ya está cerrada.');
    }

    _closing = true;
    try {
      await _stopBleRuntime();
      final closedAt = closedAtOverride ?? DateTime.now();
      final closedAtIso = closedAt.toIso8601String();

      final students = await database.getStudentsByCourse(state.course.id);
      students.sort(
        (StudentModel left, StudentModel right) =>
            left.bitIndex.compareTo(right.bitIndex),
      );
      final storedRecords = await database.getAttendanceRecordsBySession(
        state.session.id,
      );
      final recordsByStudent = <String, AttendanceRecordModel>{
        for (final AttendanceRecordModel record in storedRecords)
          record.studentId: record,
      };

      var bitmap = Uint8List.fromList(state.bitmap8);
      var presentBleCount = 0;
      var presentManualCount = 0;
      final actaRecords = <SessionActaRecord>[];

      for (final StudentModel student in students) {
        final record = recordsByStudent[student.id];
        final bool present = record != null;
        if (present) {
          bitmap = BlePacketCodec.setStudentBit(bitmap, student.bitIndex);
          if (record.method == AppConstants.attendanceMethodBleHmac) {
            presentBleCount++;
          } else {
            presentManualCount++;
          }
        } else {
          bitmap = BlePacketCodec.clearStudentBit(bitmap, student.bitIndex);
        }

        actaRecords.add(
          SessionActaRecord(
            bitIndex: student.bitIndex,
            studentCode: student.studentCode,
            fullName: student.fullName,
            status: present
                ? AppConstants.attendanceStatusPresent
                : AppConstants.attendanceStatusAbsent,
            method: present ? record.method : null,
            verifyCode: present ? record.hmacTag : null,
            rssi: present ? record.rssiAvg?.round() : null,
          ),
        );
      }

      final bitmapHex = _bitmapToHex(bitmap);
      final unsignedActa = SignedSessionActa(
        sessionId: state.session.id,
        courseId: state.course.id,
        courseCode: state.course.code,
        courseName: state.course.name,
        sessionPin: state.session.roomPin,
        startedAtIso: state.session.startedAt,
        closedAtIso: closedAtIso,
        totalEnrolled: students.length,
        presentBleCount: presentBleCount,
        presentManualCount: presentManualCount,
        absentCount: students.length - presentBleCount - presentManualCount,
        bitmapHex: bitmapHex,
        records: actaRecords,
        actaHmacSignature: '',
      );
      final signature = _signCanonicalJson(
        unsignedActa.canonicalJson,
        state.course.courseSecret,
      );
      final acta = unsignedActa.copyWith(actaHmacSignature: signature);
      final actHash = sha256
          .convert(utf8.encode(acta.canonicalJson))
          .toString();

      await database.closeSessionWithActa(
        sessionId: state.session.id,
        closedAt: closedAtIso,
        bitmapHex: bitmapHex,
        actaJson: jsonEncode(acta.toJson()),
        actaHmacSignature: signature,
        actHash: actHash,
      );

      _applyBitmap(state, bitmap);
      state.session = state.session.copyWith(
        closedAt: closedAtIso,
        bitmapHex: bitmapHex,
        actHash: actHash,
      );
      _signedActa = acta;
      return acta;
    } finally {
      _closing = false;
    }
  }

  /// Comprueba el eco docente y devuelve el Sello Verde del estudiante.
  Future<StudentConfirmationOutcome> checkTeacherEchoForStudent({
    required StudentEnrollmentModel enrollment,
    required int sessionPin,
    required Uint8List teacherPacket16,
    required int rssi,
    DateTime? nowOverride,
  }) async {
    _ensureNotDisposed();
    _validatePin(sessionPin);

    final verification = BlePacketCodec.verifyTeacherEchoBytes(
      packet16: teacherPacket16,
      expectedCourseId: enrollment.courseId,
      sharedSecretHex: enrollment.sharedSecret,
    );
    if (!verification.isValid) {
      return StudentConfirmationOutcome(
        isConfirmed: false,
        failureReason: verification.failureReason,
        bitIndex: enrollment.bitIndex,
        rssi: rssi,
        sessionPin: sessionPin,
      );
    }

    final Uint8List bitmap8 = verification.bitmap8!;
    final bitmapHex = _bitmapToHex(bitmap8);
    if (!BlePacketCodec.isStudentBitSet(bitmap8, enrollment.bitIndex)) {
      return StudentConfirmationOutcome(
        isConfirmed: false,
        failureReason:
            'El docente aún no ha marcado al estudiante como presente.',
        bitmapHex: bitmapHex,
        bitIndex: enrollment.bitIndex,
        rssi: rssi,
        sessionPin: sessionPin,
      );
    }

    final now = nowOverride ?? DateTime.now();
    final timeTick = BlePacketCodec.computeTimeTick(now);
    final verifyCode = BlePacketCodec.generateAttendanceVerifyCode(
      courseId: enrollment.courseId,
      studentCode: enrollment.studentCode,
      bitIndex: enrollment.bitIndex,
      timeTick: timeTick,
      secretHex: enrollment.deviceSecret,
    );
    return StudentConfirmationOutcome(
      isConfirmed: true,
      verifyCode: verifyCode,
      confirmedAt: now,
      bitmapHex: bitmapHex,
      bitIndex: enrollment.bitIndex,
      rssi: rssi,
      sessionPin: sessionPin,
    );
  }

  /// Detiene el radar y libera el servicio BLE propio, sin cerrar SQLite.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _closing = true;
    await _stopBleRuntime();
    await _operationQueue;
    if (_ownsBleService) {
      await _bleService.dispose();
    }
    _state = null;
  }

  void _subscribeToBle() {
    _bleSubscription = _bleService.packetEvents.listen(
      (BlePacketEvent event) {
        unawaited(_processBleEvent(event));
      },
      onError: (Object error, StackTrace stackTrace) {
        _lastAsyncError = '$error\n$stackTrace';
        _warn('Error en canal de paquetes BLE: $error');
      },
    );
    _bleIssuesSubscription = _bleService.issues.listen(
      (BleRuntimeIssue issue) {
        _warn(issue.message);
      },
    );
  }

  Future<void> _processBleEvent(BlePacketEvent event) async {
    try {
      _lastDetectionOutcome = await processIncomingStudentPacket(
        packet16: event.packet16,
        rssi: event.rssi,
      );
    } catch (error) {
      _lastAsyncError = error.toString();
    }
  }

  Future<void> _tryStartScan() async {
    try {
      await _bleService.startScan();
    } catch (error) {
      _warn('No se pudo iniciar el escaneo BLE: $error');
    }
  }

  Future<void> _publishTeacherEcho() {
    final state = _state;
    if (state == null) {
      return Future<void>.value();
    }
    final bitmap = Uint8List.fromList(state.bitmap8);
    final task = _echoQueue.then((_) async {
      if (_disposed ||
          _closing ||
          !state.isOpen ||
          _state?.session.id != state.session.id) {
        return;
      }
      try {
        await _bleService.startTeacherEcho(
          courseId: state.course.id,
          sessionId: state.session.id,
          bitmap8: bitmap,
          sharedSecretHex: state.course.courseSecret,
        );
        _scheduleEchoTimer();
      } catch (error) {
        _warn('No se pudo emitir el eco docente: $error');
      }
    });
    _echoQueue = task.catchError((Object _) {});
    return task;
  }

  void _scheduleEchoTimer() {
    if (_disposed ||
        _closing ||
        _state == null ||
        !_state!.isOpen ||
        _echoTimer != null) {
      return;
    }
    _echoTimer = Timer.periodic(
      const Duration(seconds: AppConstants.teacherEchoIntervalSeconds),
      (Timer _) {
        unawaited(_publishTeacherEcho());
      },
    );
  }

  Future<void> _stopBleRuntime() async {
    final timer = _echoTimer;
    _echoTimer = null;
    timer?.cancel();

    final subscription = _bleSubscription;
    _bleSubscription = null;
    await subscription?.cancel();

    final issuesSubscription = _bleIssuesSubscription;
    _bleIssuesSubscription = null;
    await issuesSubscription?.cancel();

    try {
      await _bleService.stopScan();
    } catch (error) {
      _warn('No se pudo detener el escaneo BLE: $error');
    }
    try {
      await _bleService.stopAdvertising();
    } catch (error) {
      _warn('No se pudo detener el eco BLE: $error');
    }
  }

  ActiveCourseSessionState _requireOpenState() {
    final state = _state;
    if (state == null) {
      throw StateError('No hay una sesión docente activa.');
    }
    if (!state.isOpen) {
      throw StateError('La sesión ${state.session.id} está cerrada.');
    }
    return state;
  }

  void _applyBitmap(ActiveCourseSessionState state, Uint8List bitmap) {
    state.bitmap8.setRange(0, BlePacketCodec.bitmapLength, bitmap);
  }

  int _generatePin() {
    return AppConstants.minimumSessionPin +
        _random.nextInt(
          AppConstants.maximumSessionPin - AppConstants.minimumSessionPin + 1,
        );
  }

  static void _validatePin(int pin) {
    if (pin < AppConstants.minimumSessionPin ||
        pin > AppConstants.maximumSessionPin) {
      throw ArgumentError.value(
        pin,
        'customPin',
        'El PIN debe estar entre '
            '${AppConstants.minimumSessionPin} y '
            '${AppConstants.maximumSessionPin}.',
      );
    }
  }

  static String _recordId(String sessionId, String studentId) {
    return '${sessionId}_$studentId';
  }

  void _warn(String message) {
    _lastBleWarning = message;
    _state?.bleWarning = message;
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationQueue = _operationQueue.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('AttendanceSessionController ya fue liberado.');
    }
  }
}

String _bitmapToHex(Uint8List bitmap8) {
  return bitmap8
      .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}

String _signCanonicalJson(String canonicalJson, String secretHex) {
  return Hmac(
    sha256,
    utf8.encode(secretHex.toLowerCase()),
  ).convert(utf8.encode(canonicalJson)).toString();
}

bool _constantTimeEquals(String left, String right) {
  if (left.length != right.length) {
    return false;
  }
  var difference = 0;
  for (var i = 0; i < left.length; i++) {
    difference |= left.codeUnitAt(i) ^ right.codeUnitAt(i);
  }
  return difference == 0;
}
