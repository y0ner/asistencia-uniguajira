import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/crypto/ble_packet_codec.dart';
import '../../core/crypto/enrollment_crypto.dart';
import '../../core/crypto/enrollment_packet_codec.dart';
import '../../core/models/course_model.dart';
import '../../core/models/student_model.dart';
import '../local/app_database.dart';
import 'ble_attendance_service.dart';

/// Por qué una solicitud espera la decisión del docente.
enum PendingEnrollmentKind {
  /// El código no está en la lista de la clase.
  notInRoster,

  /// El código ya tiene otro celular vinculado.
  deviceConflict,

  /// El código es de un estudiante retirado que quiere volver.
  retiredReturning,
}

/// Solicitud que el docente debe aprobar o rechazar.
class PendingEnrollment {
  const PendingEnrollment({
    required this.requestId,
    required this.studentCode,
    required this.kind,
    required this.receivedAt,
    this.existingStudent,
  });

  final int requestId;
  final String studentCode;
  final PendingEnrollmentKind kind;
  final DateTime receivedAt;

  /// El estudiante ya registrado con ese código (conflicto o retirado).
  final StudentModel? existingStudent;
}

/// Lo que la pantalla "Inscribir estudiantes" necesita dibujar.
class EnrollmentHostState {
  const EnrollmentHostState({
    this.students = const <StudentModel>[],
    this.pending = const <PendingEnrollment>[],
    this.recentlyEnrolled = const <StudentModel>[],
  });

  /// Estudiantes activos de la clase.
  final List<StudentModel> students;

  /// Solicitudes que esperan decisión, de la más antigua a la más reciente.
  final List<PendingEnrollment> pending;

  /// Inscritos en esta sesión de inscripción, del más reciente al más antiguo.
  final List<StudentModel> recentlyEnrolled;

  int get totalStudents => students.length;

  int get boundCount => students.where((s) => s.hasDevice).length;
}

class _Decision {
  _Decision({required this.status, required this.deviceSecretHex, this.bitIndex});

  EnrollmentStatus status;
  final String deviceSecretHex;
  int? bitIndex;
  DateTime lastHeard = DateTime.fromMillisecondsSinceEpoch(0);
}

class _PendingData {
  _PendingData({required this.info, required this.publicKeyHex, required this.deviceSecretHex});

  final PendingEnrollment info;
  final String publicKeyHex;
  final String deviceSecretHex;
}

/// Lado docente de la inscripción con un solo QR de clase.
///
/// Escucha solicitudes por Bluetooth, acepta sola a quien está en la lista y
/// no tiene celular, deja en espera lo demás y responde a cada estudiante.
class EnrollmentHostService {
  EnrollmentHostService({
    required this.course,
    required AppDatabase database,
    required BleAttendanceService bleService,
    DateTime Function()? now,
    this.responseInterval = const Duration(milliseconds: 600),
    this.responseLinger = const Duration(seconds: 3),
    Random? random,
  })  : _database = database, // ignore: prefer_initializing_formals
        _ble = bleService,
        _now = now ?? DateTime.now,
        _random = random ?? Random.secure();

  final CourseModel course;
  final AppDatabase _database;
  final BleAttendanceService _ble;
  final DateTime Function() _now;
  final Random _random;

  /// Cada cuánto cambia la respuesta que se anuncia.
  final Duration responseInterval;

  /// Cuánto se sigue respondiendo a un estudiante después de oírlo por última vez.
  final Duration responseLinger;

  static const Uuid _uuid = Uuid();

  final StreamController<EnrollmentHostState> _states = StreamController<EnrollmentHostState>.broadcast();
  final Map<int, _Decision> _decisions = <int, _Decision>{};
  final Map<int, _PendingData> _pending = <int, _PendingData>{};
  final List<StudentModel> _recent = <StudentModel>[];
  final Set<int> _inFlight = <int>{};

  EnrollmentHostState _state = const EnrollmentHostState();
  EnrollmentRequestAssembler? _assembler;
  StreamSubscription<BlePacketEvent>? _subscription;
  Timer? _responseTimer;
  ({String privateKeyHex, String publicKeyHex})? _keys;
  int _rotation = 0;
  bool _running = false;

  Stream<EnrollmentHostState> get states => _states.stream;

  EnrollmentHostState get state => _state;

  bool get isRunning => _running;

  /// Contenido del QR de la clase (versión 2).
  Future<String> buildClassQrPayload() async {
    final keys = await _ensureKeys();
    return jsonEncode(<String, Object?>{
      'v': 2,
      'courseId': course.id,
      'courseCode': course.code,
      'courseName': course.name,
      'sharedSecret': course.courseSecret,
      'teacherKey': keys.publicKeyHex,
    });
  }

  /// Empieza a escuchar solicitudes y a responderlas.
  Future<void> start() async {
    if (_running) return;
    await _ensureKeys();
    _assembler = EnrollmentRequestAssembler(courseId: course.id, sharedSecretHex: course.courseSecret);
    await _refreshState();
    _subscription = _ble.packetEvents.listen((event) => _onPacket(event.packet16));
    await _ble.startScan();
    _responseTimer = Timer.periodic(responseInterval, (_) => unawaited(_advertiseNextResponse()));
    _running = true;
  }

  /// Termina la inscripción. Las solicitudes sin resolver se descartan.
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _responseTimer?.cancel();
    _responseTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    _pending.clear();
    _decisions.clear();
    _assembler?.clear();
    await _ble.stopAdvertising();
    await _ble.stopScan();
    await _refreshState();
  }

  Future<void> dispose() async {
    await stop();
    await _states.close();
  }

  /// Acepta a alguien que no estaba en la lista (o a un retirado que vuelve).
  Future<StudentModel> approve(int requestId, {required String fullName, String? email}) async {
    final data = _pending[requestId];
    if (data == null) {
      throw StateError('La solicitud ya no está disponible.');
    }
    final name = fullName.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) {
      throw ArgumentError.value(fullName, 'fullName', 'Escribe el nombre del estudiante.');
    }
    final cleanEmail = (email == null || email.trim().isEmpty) ? null : email.trim().toLowerCase();
    final nowIso = _now().toIso8601String();
    final keyId = EnrollmentCrypto.keyId(data.publicKeyHex);

    late final StudentModel student;
    switch (data.info.kind) {
      case PendingEnrollmentKind.notInRoster:
        final all = await _database.getAllStudentsByCourse(course.id);
        final bit = _firstFreeBit(all);
        if (bit == null) {
          _decide(requestId, EnrollmentStatus.classFull, data.deviceSecretHex);
          _pending.remove(requestId);
          await _refreshState();
          throw StateError('La clase ya está completa (${AppConstants.bitmapBitCount} estudiantes).');
        }
        student = StudentModel(
          id: _uuid.v4(),
          courseId: course.id,
          studentCode: data.info.studentCode,
          fullName: name,
          email: cleanEmail,
          bitIndex: bit,
          personalSecret: data.deviceSecretHex,
          enrolledAt: nowIso,
          origin: AppConstants.studentOriginAddedInClass,
          deviceKeyId: keyId,
          deviceBoundAt: nowIso,
        );
        await _database.insertStudent(student);
      case PendingEnrollmentKind.retiredReturning:
        final existing = data.info.existingStudent!;
        await _database.reactivateStudent(existing.id);
        await _database.updateStudentIdentity(studentId: existing.id, fullName: name, email: cleanEmail ?? existing.email);
        await _bind(existing.id, data, nowIso);
        student = (await _database.getStudentById(existing.id))!;
      case PendingEnrollmentKind.deviceConflict:
        throw StateError('Un conflicto de celular se resuelve con replaceDevice().');
    }

    _decide(requestId, EnrollmentStatus.accepted, data.deviceSecretHex, bitIndex: student.bitIndex);
    _pending.remove(requestId);
    _remember(student);
    await _refreshState();
    return student;
  }

  /// Resuelve un conflicto: el celular nuevo reemplaza al anterior.
  Future<StudentModel> replaceDevice(int requestId) async {
    final data = _pending[requestId];
    if (data == null || data.info.kind != PendingEnrollmentKind.deviceConflict) {
      throw StateError('La solicitud ya no está disponible.');
    }
    final existing = data.info.existingStudent!;
    await _bind(existing.id, data, _now().toIso8601String());
    final student = (await _database.getStudentById(existing.id))!;
    _decide(requestId, EnrollmentStatus.accepted, data.deviceSecretHex, bitIndex: student.bitIndex);
    _pending.remove(requestId);
    _remember(student);
    await _refreshState();
    return student;
  }

  /// Rechaza una solicitud en espera.
  Future<void> reject(int requestId) async {
    final data = _pending.remove(requestId);
    if (data == null) return;
    _decide(requestId, EnrollmentStatus.rejected, data.deviceSecretHex);
    await _refreshState();
  }

  // ---------------------------------------------------------------------------

  Future<({String privateKeyHex, String publicKeyHex})> _ensureKeys() async {
    final cached = _keys;
    if (cached != null) return cached;
    var keys = await _database.getCourseEnrollKeys(course.id);
    if (keys == null) {
      final pair = await EnrollmentCrypto.generateKeyPair();
      await _database.setCourseEnrollKeys(
        courseId: course.id,
        privateKeyHex: pair.privateKeyHex,
        publicKeyHex: pair.publicKeyHex,
      );
      keys = (privateKeyHex: pair.privateKeyHex, publicKeyHex: pair.publicKeyHex);
    }
    return _keys = keys;
  }

  void _onPacket(Uint8List packet16) {
    if (!_running || !EnrollmentPacketCodec.isRequestFragment(packet16)) return;
    final data = ByteData.sublistView(packet16);
    if (data.getUint16(0, Endian.big) != BlePacketCodec.computeCourseHash16(course.id)) return;
    final requestId = data.getUint16(3, Endian.big);

    final known = _decisions[requestId];
    if (known != null) {
      known.lastHeard = _now();
      return;
    }
    final request = _assembler?.add(packet16);
    if (request == null || _inFlight.contains(request.requestId)) return;
    _inFlight.add(request.requestId);
    unawaited(_handleRequest(request).whenComplete(() => _inFlight.remove(request.requestId)));
  }

  Future<void> _handleRequest(EnrollmentRequest request) async {
    final keys = await _ensureKeys();
    final deviceSecret = await EnrollmentCrypto.deriveDeviceSecret(
      ownPrivateKeyHex: keys.privateKeyHex,
      peerPublicKeyHex: request.studentPublicKeyHex,
      sharedSecretHex: course.courseSecret,
      studentCode: request.studentCode,
    );
    if (!_running) return;
    final keyId = EnrollmentCrypto.keyId(request.studentPublicKeyHex);
    final all = await _database.getAllStudentsByCourse(course.id);
    StudentModel? existing;
    for (final s in all) {
      if (s.studentCode.trim() == request.studentCode) {
        existing = s;
        break;
      }
    }

    // El mismo celular volvió a pedir con otro número de solicitud: se reemplaza la anterior.
    _pending.removeWhere((id, p) {
      final same = p.publicKeyHex == request.studentPublicKeyHex && p.info.studentCode == request.studentCode;
      if (same) _decisions.remove(id);
      return same;
    });

    if (existing != null && existing.isActive && (!existing.hasDevice || existing.deviceKeyId == keyId)) {
      await _database.bindStudentDevice(
        studentId: existing.id,
        deviceSecretHex: deviceSecret,
        deviceKeyId: keyId,
        boundAt: _now().toIso8601String(),
      );
      _decide(request.requestId, EnrollmentStatus.accepted, deviceSecret, bitIndex: existing.bitIndex);
      _remember((await _database.getStudentById(existing.id))!);
    } else if (existing == null && _firstFreeBit(all) == null) {
      _decide(request.requestId, EnrollmentStatus.classFull, deviceSecret);
    } else {
      final kind = existing == null
          ? PendingEnrollmentKind.notInRoster
          : existing.isRetired
              ? PendingEnrollmentKind.retiredReturning
              : PendingEnrollmentKind.deviceConflict;
      _pending[request.requestId] = _PendingData(
        info: PendingEnrollment(
          requestId: request.requestId,
          studentCode: request.studentCode,
          kind: kind,
          receivedAt: _now(),
          existingStudent: existing,
        ),
        publicKeyHex: request.studentPublicKeyHex,
        deviceSecretHex: deviceSecret,
      );
      _decide(request.requestId, EnrollmentStatus.pending, deviceSecret);
    }
    await _refreshState();
  }

  Future<void> _bind(String studentId, _PendingData data, String nowIso) {
    return _database.bindStudentDevice(
      studentId: studentId,
      deviceSecretHex: data.deviceSecretHex,
      deviceKeyId: EnrollmentCrypto.keyId(data.publicKeyHex),
      boundAt: nowIso,
    );
  }

  void _decide(int requestId, EnrollmentStatus status, String deviceSecretHex, {int? bitIndex}) {
    final decision = _decisions[requestId];
    if (decision == null) {
      _decisions[requestId] = _Decision(status: status, deviceSecretHex: deviceSecretHex, bitIndex: bitIndex)
        ..lastHeard = _now();
    } else {
      decision
        ..status = status
        ..bitIndex = bitIndex
        ..lastHeard = _now();
    }
  }

  void _remember(StudentModel student) {
    _recent
      ..removeWhere((s) => s.id == student.id)
      ..insert(0, student);
  }

  static int? _firstFreeBit(List<StudentModel> all) {
    final used = all.map((s) => s.bitIndex).toSet();
    for (var bit = 0; bit < AppConstants.bitmapBitCount; bit++) {
      if (!used.contains(bit)) return bit;
    }
    return null;
  }

  /// Anuncia, por turnos, la respuesta de cada estudiante que sigue pidiendo.
  Future<void> _advertiseNextResponse() async {
    if (!_running) return;
    final now = _now();
    final active = _decisions.entries
        .where((e) => now.difference(e.value.lastHeard) <= responseLinger)
        .toList(growable: false);
    // Limpieza: decisiones finales que nadie reclama hace rato.
    _decisions.removeWhere(
      (id, d) => d.status.isFinal && now.difference(d.lastHeard) > const Duration(minutes: 5),
    );
    if (active.isEmpty) {
      if (_ble.isAdvertising) await _ble.stopAdvertising();
      return;
    }
    final entry = active[_rotation % active.length];
    _rotation++;
    final packet = EnrollmentPacketCodec.buildResponse(
      courseId: course.id,
      requestId: entry.key,
      status: entry.value.status,
      deviceSecretHex: entry.value.deviceSecretHex,
      bitIndex: entry.value.bitIndex,
    );
    try {
      await _ble.startAdvertisingPacket(packet);
    } catch (error) {
      // El servicio Bluetooth también lo publica por `issues` (la pantalla lo
      // muestra); aquí se registra y se sigue con la rotación.
      debugPrint('Inscripción: no se pudo anunciar la respuesta: $error');
    }
  }

  Future<void> _refreshState() async {
    final students = await _database.getStudentsByCourse(course.id);
    final pending = _pending.values.map((p) => p.info).toList()
      ..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
    _state = EnrollmentHostState(
      students: students,
      pending: List<PendingEnrollment>.unmodifiable(pending),
      recentlyEnrolled: List<StudentModel>.unmodifiable(_recent),
    );
    if (!_states.isClosed) _states.add(_state);
  }

  /// Secreto aleatorio de 32 bytes (para invalidar celulares al desvincular o retirar).
  String newRandomSecretHex() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return EnrollmentCrypto.bytesToHex(bytes);
  }
}
