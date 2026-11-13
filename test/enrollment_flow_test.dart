import 'dart:io';

import 'package:asistencia_uniguajira/core/constants/app_constants.dart';
import 'package:asistencia_uniguajira/core/crypto/ble_packet_codec.dart';
import 'package:asistencia_uniguajira/core/models/course_model.dart';
import 'package:asistencia_uniguajira/core/models/student_model.dart';
import 'package:asistencia_uniguajira/data/local/app_database.dart';
import 'package:asistencia_uniguajira/data/services/enrollment_client_service.dart';
import 'package:asistencia_uniguajira/data/services/enrollment_host_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_ble_air.dart';

const _secret = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

final _course = CourseModel(
  id: 'curso-bd2',
  code: 'SIST-401',
  name: 'Bases de Datos II',
  groupCode: '01',
  semester: '2026-2',
  courseSecret: _secret,
  createdAt: '2026-11-01T08:00:00.000-05:00',
);

StudentModel _rosterStudent(String code, int bit, {String? name}) => StudentModel(
      id: 'st-$code',
      courseId: _course.id,
      studentCode: code,
      fullName: name ?? 'Estudiante $code',
      bitIndex: bit,
      personalSecret: 'ff' * 32,
      enrolledAt: '2026-11-01T08:00:00.000-05:00',
    );

/// Un celular de estudiante: su propia base de datos y su Bluetooth.
class _Phone {
  _Phone(this.db, this.ble) {
    client = EnrollmentClientService(
      database: db,
      bleService: ble,
      fragmentInterval: const Duration(milliseconds: 8),
      timeout: const Duration(milliseconds: 900),
    );
  }

  final AppDatabase db;
  final AirBle ble;
  late final EnrollmentClientService client;

  /// Pide unirse y devuelve todos los estados hasta el final.
  Future<List<EnrollmentClientUpdate>> join(ClassInvite invite, String code, {String name = 'Yo'}) {
    return client.request(invite: invite, studentCode: code, displayName: name).toList();
  }
}

void main() {
  sqfliteFfiInit();

  late Directory tmp;
  late BleAir air;
  late AppDatabase teacherDb;
  late EnrollmentHostService host;
  late ClassInvite invite;
  final phones = <_Phone>[];
  var dbCount = 0;

  AppDatabase newDb() =>
      AppDatabase(factory: databaseFactoryFfi, databasePath: p.join(tmp.path, 'db${dbCount++}.sqlite'));

  _Phone newPhone() {
    final phone = _Phone(newDb(), air.node());
    phones.add(phone);
    return phone;
  }

  Future<void> waitUntil(bool Function() condition, {String reason = ''}) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) fail('No se cumplió a tiempo: $reason');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('inscripcion_');
    air = BleAir();
    teacherDb = newDb();
    await teacherDb.insertCourse(_course);
    host = EnrollmentHostService(
      course: _course,
      database: teacherDb,
      bleService: air.node(),
      responseInterval: const Duration(milliseconds: 10),
      responseLinger: const Duration(milliseconds: 150),
    );
  });

  Future<void> openEnrollment() async {
    await host.start();
    invite = ClassInvite.parse(await host.buildClassQrPayload());
  }

  tearDown(() async {
    for (final phone in phones) {
      await phone.client.cancel();
      await phone.db.close();
    }
    phones.clear();
    await host.dispose();
    await air.dispose();
    await teacherDb.close();
    tmp.deleteSync(recursive: true);
  });

  test('estudiante de la lista entra solo y queda vinculado', () async {
    await teacherDb.insertStudent(_rosterStudent('0182120016', 5, name: 'Yoner Isaza'));
    await openEnrollment();
    expect(host.state.totalStudents, 1);
    expect(host.state.boundCount, 0);

    final phone = newPhone();
    final updates = await phone.join(invite, '0182120016', name: 'Yoner');

    expect(updates.first.phase, EnrollmentClientPhase.searching);
    expect(updates.last.phase, EnrollmentClientPhase.accepted);
    final enrollment = updates.last.enrollment!;
    expect(enrollment.bitIndex, 5);
    expect(enrollment.fullName, 'Yoner'); // nombre local del estudiante
    expect(enrollment.courseName, 'Bases de Datos II');

    final stored = (await teacherDb.getStudentByCode(courseId: _course.id, studentCode: '0182120016'))!;
    expect(stored.hasDevice, isTrue);
    expect(stored.fullName, 'Yoner Isaza'); // el registro oficial es el del docente
    expect(stored.personalSecret, enrollment.deviceSecret);
    expect(stored.origin, AppConstants.studentOriginRoster);
    expect(host.state.boundCount, 1);
    expect(host.state.recentlyEnrolled.single.studentCode, '0182120016');
    expect((await phone.db.getStudentEnrollments()).single.courseId, _course.id);
  });

  test('después de inscribirse, la asistencia verifica con el secreto acordado', () async {
    await teacherDb.insertStudent(_rosterStudent('0182120016', 9));
    await openEnrollment();
    final enrollment = (await newPhone().join(invite, '0182120016')).last.enrollment!;

    final beacon = BlePacketCodec.buildStudentBeaconBytes(
      courseId: enrollment.courseId,
      bitIndex: enrollment.bitIndex,
      sessionPin: 47,
      secretHex: enrollment.deviceSecret,
      timeTick: 1000,
    );
    final students = await teacherDb.getStudentsByCourse(_course.id);
    final result = BlePacketCodec.verifyStudentBeaconBytes(
      packet16: beacon,
      expectedCourseId: _course.id,
      expectedSessionPin: 47,
      secretHexByBitIndex: {for (final s in students) s.bitIndex: s.personalSecret},
      currentTimeTick: 1000,
    );
    expect(result.isValid, isTrue);
    expect(result.bitIndex, 9);
  });

  test('fuera de la lista: espera, el docente lo agrega con nombre y correo', () async {
    await openEnrollment();
    final phone = newPhone();
    final future = phone.join(invite, '0182120099');

    await waitUntil(() => host.state.pending.isNotEmpty, reason: 'solicitud en Por aprobar');
    final pending = host.state.pending.single;
    expect(pending.kind, PendingEnrollmentKind.notInRoster);
    expect(pending.studentCode, '0182120099');
    expect(await teacherDb.getStudentsByCourse(_course.id), isEmpty); // nunca entra solo

    final added = await host.approve(pending.requestId, fullName: '  María   Epieyú ', email: 'MEpieyu@uniguajira.edu.co');
    final updates = await future;

    expect(updates.map((u) => u.phase), contains(EnrollmentClientPhase.pending));
    expect(updates.last.phase, EnrollmentClientPhase.accepted);
    expect(added.fullName, 'María Epieyú');
    expect(added.email, 'mepieyu@uniguajira.edu.co');
    expect(added.origin, AppConstants.studentOriginAddedInClass);
    expect(added.hasDevice, isTrue);
    expect(updates.last.enrollment!.bitIndex, added.bitIndex);
    expect(host.state.pending, isEmpty);
  });

  test('el docente rechaza: no se crea el estudiante', () async {
    await openEnrollment();
    final future = newPhone().join(invite, '0182120099');
    await waitUntil(() => host.state.pending.isNotEmpty);
    await host.reject(host.state.pending.single.requestId);

    expect((await future).last.phase, EnrollmentClientPhase.rejected);
    expect(await teacherDb.getAllStudentsByCourse(_course.id), isEmpty);
  });

  test('aprobar exige el nombre', () async {
    await openEnrollment();
    final future = newPhone().join(invite, '0182120099');
    await waitUntil(() => host.state.pending.isNotEmpty);
    final id = host.state.pending.single.requestId;
    expect(() => host.approve(id, fullName: '   '), throwsArgumentError);
    await host.reject(id);
    await future;
  });

  test('un código ya vinculado no entra solo: conflicto y reemplazo de celular', () async {
    await teacherDb.insertStudent(_rosterStudent('0182120016', 3, name: 'Ana Pérez'));
    await openEnrollment();

    final first = (await newPhone().join(invite, '0182120016')).last.enrollment!;
    final secondFuture = newPhone().join(invite, '0182120016');

    await waitUntil(() => host.state.pending.isNotEmpty, reason: 'conflicto visible');
    final conflict = host.state.pending.single;
    expect(conflict.kind, PendingEnrollmentKind.deviceConflict);
    expect(conflict.existingStudent!.fullName, 'Ana Pérez');
    // Mientras el docente no decide, sigue valiendo el primer celular.
    expect((await teacherDb.getStudentById('st-0182120016'))!.personalSecret, first.deviceSecret);

    await host.replaceDevice(conflict.requestId);
    final second = (await secondFuture).last;
    expect(second.phase, EnrollmentClientPhase.accepted);
    expect(second.enrollment!.bitIndex, 3);
    final stored = (await teacherDb.getStudentById('st-0182120016'))!;
    expect(stored.personalSecret, second.enrollment!.deviceSecret);
    expect(stored.personalSecret, isNot(first.deviceSecret)); // el celular anterior ya no sirve
  });

  test('conflicto rechazado: se conserva el celular original', () async {
    await teacherDb.insertStudent(_rosterStudent('0182120016', 3));
    await openEnrollment();
    final first = (await newPhone().join(invite, '0182120016')).last.enrollment!;
    final secondFuture = newPhone().join(invite, '0182120016');
    await waitUntil(() => host.state.pending.isNotEmpty);
    await host.reject(host.state.pending.single.requestId);

    expect((await secondFuture).last.phase, EnrollmentClientPhase.rejected);
    expect((await teacherDb.getStudentById('st-0182120016'))!.personalSecret, first.deviceSecret);
  });

  test('dos estudiantes a la vez quedan en casillas distintas', () async {
    await teacherDb.insertStudent(_rosterStudent('0182120016', 0));
    await teacherDb.insertStudent(_rosterStudent('0182120017', 1));
    await openEnrollment();

    final results = await Future.wait([
      newPhone().join(invite, '0182120016'),
      newPhone().join(invite, '0182120017'),
    ]);
    expect(results.map((r) => r.last.phase), everyElement(EnrollmentClientPhase.accepted));
    expect(results.map((r) => r.last.enrollment!.bitIndex).toSet(), {0, 1});
    expect(host.state.boundCount, 2);
  });

  test('clase completa: se avisa y no se agrega', () async {
    for (var i = 0; i < AppConstants.bitmapBitCount; i++) {
      await teacherDb.insertStudent(_rosterStudent('01821${i.toString().padLeft(5, '0')}', i));
    }
    await openEnrollment();
    final updates = await newPhone().join(invite, '0999999999');
    expect(updates.last.phase, EnrollmentClientPhase.classFull);
    expect(host.state.pending, isEmpty);
  });

  test('un retirado que vuelve necesita aprobación y recupera su lugar', () async {
    await teacherDb.insertStudent(_rosterStudent('0182120016', 4, name: 'Carlos Iguarán'));
    await teacherDb.retireStudent(
      studentId: 'st-0182120016',
      retiredAt: '2026-11-10T08:00:00.000-05:00',
      newSecretHex: 'ee' * 32,
    );
    await openEnrollment();
    expect(host.state.totalStudents, 0);

    final future = newPhone().join(invite, '0182120016');
    await waitUntil(() => host.state.pending.isNotEmpty);
    final pending = host.state.pending.single;
    expect(pending.kind, PendingEnrollmentKind.retiredReturning);

    final back = await host.approve(pending.requestId, fullName: 'Carlos Iguarán');
    expect((await future).last.phase, EnrollmentClientPhase.accepted);
    expect(back.isActive, isTrue);
    expect(back.bitIndex, 4);
    expect(back.hasDevice, isTrue);
  });

  test('sin docente escuchando, la solicitud vence', () async {
    invite = ClassInvite.parse(await host.buildClassQrPayload()); // QR visto, pero inscripción cerrada
    final updates = await newPhone().join(invite, '0182120016');
    expect(updates.last.phase, EnrollmentClientPhase.timedOut);
  });

  test('con el QR de otra clase el docente no responde', () async {
    await teacherDb.insertStudent(_rosterStudent('0182120016', 0));
    await openEnrollment();
    final other = ClassInvite(
      courseId: invite.courseId,
      courseCode: invite.courseCode,
      courseName: invite.courseName,
      sharedSecretHex: 'ab' * 32,
      teacherPublicKeyHex: invite.teacherPublicKeyHex,
    );
    final updates = await newPhone().join(other, '0182120016');
    expect(updates.last.phase, EnrollmentClientPhase.timedOut);
    expect((await teacherDb.getStudentById('st-0182120016'))!.hasDevice, isFalse);
  });

  test('al cerrar la inscripción se descartan las solicitudes sin resolver', () async {
    await openEnrollment();
    final future = newPhone().join(invite, '0182120099');
    await waitUntil(() => host.state.pending.isNotEmpty);
    await host.stop();
    expect(host.state.pending, isEmpty);
    expect((await future).last.phase, EnrollmentClientPhase.timedOut);
  });

  test('el docente deja de anunciar cuando ya nadie pide', () async {
    await teacherDb.insertStudent(_rosterStudent('0182120016', 0));
    await openEnrollment();
    final teacherBle = air.node(); // observador
    await teacherBle.startScan();
    await newPhone().join(invite, '0182120016');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    var heard = 0;
    final sub = teacherBle.packetEvents.listen((_) => heard++);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await sub.cancel();
    expect(heard, 0, reason: 'no debe quedar ningún anuncio activo');
  });

  group('QR de la clase', () {
    test('rechaza textos que no son de una clase', () {
      for (final bad in ['', 'hola', '{"v":1}', '{"v":2,"courseId":"x"}', '[]']) {
        expect(() => ClassInvite.parse(bad), throwsFormatException, reason: bad);
      }
    });

    test('el QR lleva la clave pública del docente y no la privada', () async {
      final raw = await host.buildClassQrPayload();
      final keys = (await teacherDb.getCourseEnrollKeys(_course.id))!;
      expect(raw, contains(keys.publicKeyHex));
      expect(raw, isNot(contains(keys.privateKeyHex)));
      // La clave de la clase no cambia entre aperturas.
      expect(await host.buildClassQrPayload(), raw);
    });
  });
}
