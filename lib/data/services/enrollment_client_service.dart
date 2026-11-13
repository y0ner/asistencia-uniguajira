import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/crypto/enrollment_crypto.dart';
import '../../core/crypto/enrollment_packet_codec.dart';
import '../../core/models/student_enrollment_model.dart';
import '../local/app_database.dart';
import 'ble_attendance_service.dart';

/// Datos del QR de la clase (versión 2).
class ClassInvite {
  const ClassInvite({
    required this.courseId,
    required this.courseCode,
    required this.courseName,
    required this.sharedSecretHex,
    required this.teacherPublicKeyHex,
  });

  final String courseId;
  final String courseCode;
  final String courseName;
  final String sharedSecretHex;
  final String teacherPublicKeyHex;

  /// Interpreta el texto del QR. Lanza [FormatException] si no es de una clase.
  factory ClassInvite.parse(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw.trim());
    } on FormatException {
      throw const FormatException('El código no es de una clase.');
    }
    if (decoded is! Map<String, Object?> || decoded['v'] != 2) {
      throw const FormatException('El código no es de una clase.');
    }
    final Map<String, Object?> map = decoded;
    String field(String key) {
      final value = map[key];
      if (value is! String || value.trim().isEmpty) {
        throw const FormatException('El código de la clase está incompleto.');
      }
      return value.trim();
    }

    final invite = ClassInvite(
      courseId: field('courseId'),
      courseCode: field('courseCode'),
      courseName: field('courseName'),
      sharedSecretHex: field('sharedSecret'),
      teacherPublicKeyHex: field('teacherKey'),
    );
    final hex = RegExp(r'^[0-9a-fA-F]{64}$');
    if (!hex.hasMatch(invite.sharedSecretHex) || !hex.hasMatch(invite.teacherPublicKeyHex)) {
      throw const FormatException('El código de la clase está dañado.');
    }
    return invite;
  }
}

/// En qué va la solicitud del estudiante.
enum EnrollmentClientPhase {
  /// Emitiendo la solicitud; aún sin respuesta del docente.
  searching,

  /// El docente la recibió y debe aprobarla.
  pending,

  /// Inscrito: [EnrollmentClientUpdate.enrollment] trae la inscripción guardada.
  accepted,

  rejected,
  classFull,

  /// Pasó el tiempo de espera sin oír al docente.
  timedOut,
}

class EnrollmentClientUpdate {
  const EnrollmentClientUpdate(this.phase, {this.enrollment});

  final EnrollmentClientPhase phase;
  final StudentEnrollmentModel? enrollment;

  bool get isFinal => phase != EnrollmentClientPhase.searching && phase != EnrollmentClientPhase.pending;
}

/// Lado estudiante de la inscripción: pide unirse y espera la respuesta.
class EnrollmentClientService {
  EnrollmentClientService({
    required AppDatabase database,
    required BleAttendanceService bleService,
    this.fragmentInterval = const Duration(milliseconds: 400),
    this.timeout = const Duration(seconds: 60),
    Random? random,
    DateTime Function()? now,
  })  : _database = database, // ignore: prefer_initializing_formals
        _ble = bleService,
        _random = random ?? Random.secure(),
        _now = now ?? DateTime.now;

  final AppDatabase _database;
  final BleAttendanceService _ble;
  final Random _random;
  final DateTime Function() _now;

  /// Cada cuánto se cambia de fragmento.
  final Duration fragmentInterval;

  /// Espera máxima sin oír al docente. Se reinicia con cada respuesta "en revisión".
  final Duration timeout;

  StreamController<EnrollmentClientUpdate>? _updates;
  StreamSubscription<BlePacketEvent>? _subscription;
  Timer? _fragmentTimer;
  Timer? _timeoutTimer;
  bool _finishing = false;

  /// Pide unirse a la clase. El flujo termina con un estado final o al llamar a [cancel].
  Stream<EnrollmentClientUpdate> request({
    required ClassInvite invite,
    required String studentCode,
    required String displayName,
  }) {
    final code = studentCode.trim();
    if (!EnrollmentPacketCodec.isValidStudentCode(code)) {
      throw ArgumentError.value(studentCode, 'studentCode', 'El código debe tener solo números (de 4 a 12).');
    }
    if (_updates != null) {
      throw StateError('Ya hay una solicitud en curso.');
    }
    final controller = StreamController<EnrollmentClientUpdate>();
    _updates = controller;
    _finishing = false;
    unawaited(_run(controller, invite, code, displayName.trim()));
    return controller.stream;
  }

  /// Cancela la solicitud en curso (si la hay).
  Future<void> cancel() async {
    final controller = _updates;
    if (controller == null) return;
    await _teardown();
    if (!controller.isClosed) await controller.close();
  }

  Future<void> _run(
    StreamController<EnrollmentClientUpdate> controller,
    ClassInvite invite,
    String code,
    String displayName,
  ) async {
    try {
      final pair = await EnrollmentCrypto.generateKeyPair();
      final deviceSecret = await EnrollmentCrypto.deriveDeviceSecret(
        ownPrivateKeyHex: pair.privateKeyHex,
        peerPublicKeyHex: invite.teacherPublicKeyHex,
        sharedSecretHex: invite.sharedSecretHex,
        studentCode: code,
      );
      if (_updates != controller) return; // cancelada mientras se generaban las claves
      final requestId = _random.nextInt(0x10000);
      final fragments = EnrollmentPacketCodec.buildRequestFragments(
        courseId: invite.courseId,
        requestId: requestId,
        studentCode: code,
        studentPublicKeyHex: pair.publicKeyHex,
        sharedSecretHex: invite.sharedSecretHex,
      );

      controller.add(const EnrollmentClientUpdate(EnrollmentClientPhase.searching));

      _subscription = _ble.packetEvents.listen((event) {
        final response = EnrollmentPacketCodec.verifyResponse(
          packet16: event.packet16,
          expectedCourseId: invite.courseId,
          expectedRequestId: requestId,
          deviceSecretHex: deviceSecret,
        );
        if (response == null || _finishing) return;
        unawaited(_onResponse(controller, response, invite, code, displayName, deviceSecret));
      });
      await _ble.startScan();

      var index = 0;
      Future<void> advertiseNext() async {
        if (_finishing || _updates != controller) return;
        final Uint8List packet = fragments[index % fragments.length];
        index++;
        try {
          await _ble.startAdvertisingPacket(packet);
        } catch (error) {
          // El servicio Bluetooth también lo publica por `issues` (la pantalla lo
          // muestra); se reintenta en el siguiente turno.
          debugPrint('Inscripción: no se pudo anunciar el fragmento: $error');
        }
      }

      await advertiseNext();
      _fragmentTimer = Timer.periodic(fragmentInterval, (_) => unawaited(advertiseNext()));
      _armTimeout(controller);
    } catch (error, stackTrace) {
      if (!controller.isClosed) controller.addError(error, stackTrace);
      await _teardown();
      if (!controller.isClosed) await controller.close();
    }
  }

  void _armTimeout(StreamController<EnrollmentClientUpdate> controller) {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(timeout, () {
      if (_finishing || _updates != controller) return;
      unawaited(_finish(controller, const EnrollmentClientUpdate(EnrollmentClientPhase.timedOut)));
    });
  }

  Future<void> _onResponse(
    StreamController<EnrollmentClientUpdate> controller,
    EnrollmentResponse response,
    ClassInvite invite,
    String code,
    String displayName,
    String deviceSecret,
  ) async {
    switch (response.status) {
      case EnrollmentStatus.pending:
        _armTimeout(controller); // el docente está decidiendo: se sigue esperando
        if (!controller.isClosed) {
          controller.add(const EnrollmentClientUpdate(EnrollmentClientPhase.pending));
        }
      case EnrollmentStatus.accepted:
        _finishing = true;
        final enrollment = StudentEnrollmentModel(
          id: '${invite.courseId}:$code',
          courseId: invite.courseId,
          courseCode: invite.courseCode,
          courseName: invite.courseName,
          studentId: '${invite.courseId}:$code',
          studentCode: code,
          fullName: displayName,
          bitIndex: response.bitIndex!,
          deviceSecret: deviceSecret,
          sharedSecret: invite.sharedSecretHex,
          enrolledAtEpochMs: _now().millisecondsSinceEpoch,
        );
        await _database.upsertStudentEnrollment(enrollment);
        await _finish(controller, EnrollmentClientUpdate(EnrollmentClientPhase.accepted, enrollment: enrollment));
      case EnrollmentStatus.rejected:
        await _finish(controller, const EnrollmentClientUpdate(EnrollmentClientPhase.rejected));
      case EnrollmentStatus.classFull:
        await _finish(controller, const EnrollmentClientUpdate(EnrollmentClientPhase.classFull));
    }
  }

  Future<void> _finish(StreamController<EnrollmentClientUpdate> controller, EnrollmentClientUpdate update) async {
    _finishing = true;
    await _teardown();
    if (!controller.isClosed) {
      controller.add(update);
      await controller.close();
    }
  }

  Future<void> _teardown() async {
    _finishing = true;
    _fragmentTimer?.cancel();
    _fragmentTimer = null;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    _updates = null;
    await _ble.stopAdvertising();
    await _ble.stopScan();
  }
}
