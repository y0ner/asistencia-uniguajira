import 'dart:convert';

import 'package:asistencia_uniguajira/core/models/student_enrollment_model.dart';
import 'package:asistencia_uniguajira/data/local/app_database.dart';
import 'package:asistencia_uniguajira/data/services/student_enrollment_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const String _courseSecret =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const String _deviceSecret =
    'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';

Map<String, Object?> _qrPayload({
  String courseId = 'course-1',
  String courseCode = 'ING-101',
  String courseName = 'Introducción a la Ingeniería',
  String studentId = 'student-1',
  String studentCode = '0182120016',
  String fullName = 'JOSE ANGEL PEREZ',
  int bitmapIndex = 7,
  String deviceSecret = _deviceSecret,
  String sharedSecret = _courseSecret,
}) {
  return <String, Object?>{
    'courseId': courseId,
    'courseCode': courseCode,
    'courseName': courseName,
    'studentId': studentId,
    'studentCode': studentCode,
    'fullName': fullName,
    'bitmapIndex': bitmapIndex,
    'deviceSecret': deviceSecret,
    'sharedSecret': sharedSecret,
  };
}

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late StudentEnrollmentService service;

  setUp(() {
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    service = StudentEnrollmentService(database);
  });

  tearDown(() async {
    await database.close();
  });

  group('StudentEnrollmentModel', () {
    test('interpreta el JSON del QR y conserva el contrato exacto', () {
      final payload = jsonEncode(_qrPayload());
      final model = StudentEnrollmentModel.fromQrPayloadJson(payload);

      expect(model.id, 'course-1_0182120016');
      expect(model.courseId, 'course-1');
      expect(model.courseCode, 'ING-101');
      expect(model.courseName, 'Introducción a la Ingeniería');
      expect(model.studentId, 'student-1');
      expect(model.studentCode, '0182120016');
      expect(model.fullName, 'JOSE ANGEL PEREZ');
      expect(model.bitIndex, 7);
      expect(model.bitmapIndex, 7);
      expect(model.deviceSecret, _deviceSecret);
      expect(model.sharedSecret, _courseSecret);
      expect(model.enrolledAtEpochMs, greaterThan(0));

      expect(model.toJson().keys.toSet(), <String>{
        'courseId',
        'courseCode',
        'courseName',
        'studentId',
        'studentCode',
        'fullName',
        'bitmapIndex',
        'deviceSecret',
        'sharedSecret',
      });
      final fromJson = StudentEnrollmentModel.fromQrPayloadJson(
        jsonEncode(model.toJson()),
      );
      expect(fromJson.courseId, model.courseId);
      expect(fromJson.studentCode, model.studentCode);
      expect(fromJson.bitIndex, model.bitIndex);

      final fromMap = StudentEnrollmentModel.fromMap(model.toMap());
      expect(fromMap.id, model.id);
      expect(fromMap.courseName, model.courseName);
      expect(fromMap.studentCode, '0182120016');
      expect(fromMap.bitIndex, 7);
      expect(fromMap.enrolledAtEpochMs, model.enrolledAtEpochMs);
    });

    test('rechaza bitmapIndex fuera de rango o JSON corrupto', () {
      expect(
        () => StudentEnrollmentModel.fromQrPayloadJson(
          jsonEncode(_qrPayload(bitmapIndex: 64)),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => StudentEnrollmentModel.fromQrPayloadJson('{no-json'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => StudentEnrollmentModel.fromQrPayloadJson('[]'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => StudentEnrollmentModel.fromQrPayloadJson(
          jsonEncode(<String, Object?>{'courseId': 'course-1'}),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('StudentEnrollmentService', () {
    test(
      'valida, guarda y consulta una credencial sin exigir el curso local',
      () async {
        final enrollment = await service.enrollFromQrPayload(
          jsonEncode(_qrPayload()),
        );

        expect(enrollment.studentCode, '0182120016');
        final stored = await database.getStudentEnrollmentByCourse('course-1');
        expect(stored, isNotNull);
        expect(stored!.id, 'course-1_0182120016');
        expect(stored.bitIndex, 7);
        expect(stored.deviceSecret, _deviceSecret);

        final all = await service.getEnrolledCourses();
        expect(all, hasLength(1));
        expect(all.single.studentCode, '0182120016');
      },
    );

    test(
      'reemplaza la credencial del mismo curso y permite eliminarla',
      () async {
        await service.enrollFromQrPayload(jsonEncode(_qrPayload()));
        final updated = await service.enrollFromQrPayload(
          jsonEncode(_qrPayload(studentCode: '0182120099', bitmapIndex: 8)),
        );

        expect(updated.id, 'course-1_0182120099');
        final all = await service.getEnrolledCourses();
        expect(all, hasLength(1));
        expect(all.single.studentCode, '0182120099');
        final byCourse = await database.getStudentEnrollmentByCourse(
          'course-1',
        );
        expect(byCourse!.studentCode, '0182120099');

        await service.removeEnrollment(updated.id);
        expect(await service.getEnrolledCourses(), isEmpty);
        expect(await database.getStudentEnrollmentByCourse('course-1'), isNull);
      },
    );

    test(
      'rechaza QR vacíos, ajenos, incompletos o con semillas vacías',
      () async {
        final invalidPayloads = <String>[
          '',
          'no-es-json',
          '[]',
          jsonEncode(_qrPayload(bitmapIndex: 64)),
          jsonEncode(_qrPayload(studentCode: '')),
          jsonEncode(_qrPayload(deviceSecret: '')),
          jsonEncode(_qrPayload(sharedSecret: '')),
          jsonEncode(<String, Object?>{
            'courseId': 'course-1',
            'studentCode': '0182120016',
            'bitmapIndex': 1,
          }),
        ];

        for (final String payload in invalidPayloads) {
          await expectLater(
            service.enrollFromQrPayload(payload),
            throwsA(isA<FormatException>()),
            reason: 'Debe rechazar el payload: $payload',
          );
        }

        expect(await service.getEnrolledCourses(), isEmpty);
      },
    );
  });
}
