import 'dart:convert';

import 'package:asistencia_uniguajira/core/constants/app_constants.dart';
import 'package:asistencia_uniguajira/core/models/attendance_record_model.dart';
import 'package:asistencia_uniguajira/core/models/course_model.dart';
import 'package:asistencia_uniguajira/core/models/session_model.dart';
import 'package:asistencia_uniguajira/core/models/student_model.dart';
import 'package:asistencia_uniguajira/data/local/app_database.dart';
import 'package:asistencia_uniguajira/data/services/roster_import_service.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const String _courseSecret =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const String _personalSecret =
    'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';

CourseModel _course({String id = 'course-1'}) {
  return CourseModel(
    id: id,
    code: 'ING-101',
    name: 'Introducción a la Ingeniería',
    groupCode: '01',
    semester: '2026-2',
    courseSecret: _courseSecret,
    createdAt: '2026-11-06T08:00:00.000-05:00',
  );
}

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late RosterImportService service;

  setUp(() {
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    service = RosterImportService(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  group('CSV', () {
    test('conserva ceros, normaliza nombres y aplica las dos deduplicaciones',
        () async {
      final course = _course();
      await database.insertCourse(course);
      const csv = 'codigo,nombre,correo\r\n'
          '0182120016,  José   Ángel  Pérez ,jose@uniguajira.edu.co\r\n'
          '0182110072,María Camila Ipuana,\r\n'
          '0182120016,Otra Persona,otra@uniguajira.edu.co\r\n'
          '0182120099,José Ángel Pérez,duplicado@uniguajira.edu.co\r\n'
          ',"SIN CODIGO",\r\n';

      final result = await service.importFromCsvString(course.id, csv);

      expect(result.insertedCount, 2);
      expect(result.duplicatesSkipped, 2);
      expect(result.invalidRowsSkipped, 1);
      expect(
        result.insertedStudents.map((StudentModel student) => student.studentCode),
        <String>['0182120016', '0182110072'],
      );
      expect(
        result.insertedStudents.map((StudentModel student) => student.fullName),
        <String>['JOSE ANGEL PEREZ', 'MARIA CAMILA IPUANA'],
      );
      expect(
        result.insertedStudents.map((StudentModel student) => student.bitIndex),
        <int>[0, 1],
      );
      expect(result.insertedStudents.first.email, 'jose@uniguajira.edu.co');
      expect(result.insertedStudents.last.email, isNull);
      expect(
        RegExp(r'^[0-9a-f]{64}$')
            .hasMatch(result.insertedStudents.first.personalSecret),
        isTrue,
      );

      final again = await service.importFromCsvString(course.id, csv);
      expect(again.insertedCount, 0);
      expect(again.duplicatesSkipped, 4);
      expect(again.invalidRowsSkipped, 1);
      expect(await database.getStudentsByCourse(course.id), hasLength(2));
    });
  });

  group('portapapeles', () {
    test('acepta tabulador, punto y coma, coma y guion como separadores',
        () async {
      final course = _course();
      await database.insertCourse(course);
      const text = '0182120016\tAna Maria  Gómez\n'
          '0182110072;Luis Alberto\n'
          '0182120099,Carlos\n'
          '0182120098 - Diana   Pérez\n'
          '0182120097-Juan Pérez\n'
          'SINSEPARADOR\n';

      final result = await service.importFromClipboardText(course.id, text);

      expect(result.insertedCount, 5);
      expect(result.duplicatesSkipped, 0);
      expect(result.invalidRowsSkipped, 1);
      expect(
        result.insertedStudents.map((StudentModel student) => student.fullName),
        <String>[
          'ANA MARIA GOMEZ',
          'LUIS ALBERTO',
          'CARLOS',
          'DIANA PEREZ',
          'JUAN PEREZ',
        ],
      );
      expect(
        result.insertedStudents.map((StudentModel student) => student.bitIndex),
        <int>[0, 1, 2, 3, 4],
      );
    });
  });

  group('Excel', () {
    test('lee .xlsx preservando códigos como texto', () async {
      final course = _course();
      await database.insertCourse(course);
      final workbook = Excel.createExcel();
      final sheet = workbook['Sheet1'];
      sheet.appendRow(<CellValue>[
        TextCellValue('Código'),
        TextCellValue('Nombre'),
        TextCellValue('Correo'),
      ]);
      sheet.appendRow(<CellValue>[
        TextCellValue('0182120016'),
        TextCellValue('José   Ángel Pérez'),
        TextCellValue('jose@uniguajira.edu.co'),
      ]);
      sheet.appendRow(<CellValue>[
        TextCellValue('0182110072'),
        TextCellValue('María Camila Ipuana'),
        TextCellValue(''),
      ]);
      final bytes = workbook.encode();
      expect(bytes, isNotNull);

      final result = await service.importFromExcelBytes(course.id, bytes!);

      expect(result.insertedCount, 2);
      expect(
        result.insertedStudents.map((StudentModel student) => student.studentCode),
        <String>['0182120016', '0182110072'],
      );
      expect(result.insertedStudents.first.fullName, 'JOSE ANGEL PEREZ');
    });
  });

  group('alta manual y capacidad', () {
    test('normaliza el alta manual y rechaza código o nombre repetido',
        () async {
      final course = _course();
      await database.insertCourse(course);

      final student = await service.addManualStudent(
        courseId: course.id,
        studentCode: ' 0182120016 ',
        fullName: '  José   Ángel  Pérez ',
        email: ' jose@uniguajira.edu.co ',
      );

      expect(student.studentCode, '0182120016');
      expect(student.fullName, 'JOSE ANGEL PEREZ');
      expect(student.email, 'jose@uniguajira.edu.co');
      expect(student.bitIndex, 0);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(student.personalSecret), isTrue);

      await expectLater(
        service.addManualStudent(
          courseId: course.id,
          studentCode: '0182120016',
          fullName: 'Otra Persona',
        ),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        service.addManualStudent(
          courseId: course.id,
          studentCode: '0182120099',
          fullName: 'José Ángel Pérez',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('asigna el último bit libre y respeta el límite de 64', () async {
      final course = _course();
      await database.insertCourse(course);
      for (var i = 0; i < 63; i++) {
        await database.insertStudent(
          StudentModel(
            id: 'pre-$i',
            courseId: course.id,
            studentCode: i.toString().padLeft(10, '0'),
            fullName: 'PRE ${i.toString().padLeft(2, '0')}',
            bitIndex: i,
            personalSecret: _personalSecret,
            enrolledAt: '2026-11-06T08:02:00.000-05:00',
          ),
        );
      }

      final result = await service.importFromCsvString(
        course.id,
        'codigo,nombre\n9999999991,Andrea Uno\n9999999992,Andrea Dos\n',
      );

      expect(result.insertedCount, 1);
      expect(result.insertedStudents.single.bitIndex, 63);
      expect(result.invalidRowsSkipped, 1);
      expect(await database.getStudentsByCourse(course.id), hasLength(64));
      await expectLater(
        service.addManualStudent(
          courseId: course.id,
          studentCode: '9999999993',
          fullName: 'Andrea Tres',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('QR y cursos', () {
    test('genera el payload compacto de enrolamiento', () {
      const course = CourseModel(
        id: 'course-1',
        code: 'ING-101',
        name: 'Introducción a la Ingeniería',
        groupCode: '01',
        semester: '2026-2',
        courseSecret: _courseSecret,
        createdAt: '2026-11-06T08:00:00.000-05:00',
      );
      const student = StudentModel(
        id: 'student-1',
        courseId: 'course-1',
        studentCode: '0182120016',
        fullName: 'JOSE ANGEL PEREZ',
        bitIndex: 7,
        personalSecret: _personalSecret,
      );

      final payload = service.generateEnrollmentQrPayload(
        course: course,
        student: student,
      );
      final decoded = jsonDecode(payload) as Map<String, dynamic>;

      expect(decoded['courseId'], 'course-1');
      expect(decoded['courseCode'], 'ING-101');
      expect(decoded['courseName'], 'Introducción a la Ingeniería');
      expect(decoded['studentId'], 'student-1');
      expect(decoded['studentCode'], '0182120016');
      expect(decoded['fullName'], 'JOSE ANGEL PEREZ');
      expect(decoded['bitmapIndex'], 7);
      expect(decoded['deviceSecret'], _personalSecret);
      expect(decoded['sharedSecret'], _courseSecret);
      expect(payload.contains('\n'), isFalse);
    });

    test('getCourses y deleteCourse eliminan el curso en cascada', () async {
      final course = _course();
      await database.insertCourse(course);
      final student = await service.addManualStudent(
        courseId: course.id,
        studentCode: '0182120016',
        fullName: 'José Ángel Pérez',
      );
      await database.insertSession(
        SessionModel(
          id: 'session-1',
          courseId: course.id,
          startedAt: '2026-11-06T08:05:00.000-05:00',
          roomPin: '42',
        ),
      );
      await database.insertAttendanceRecord(
        AttendanceRecordModel(
          id: 'record-1',
          sessionId: 'session-1',
          studentId: student.id,
          bitIndex: student.bitIndex,
          method: AppConstants.attendanceMethodManualInverted,
          recordedAt: '2026-11-06T08:06:00.000-05:00',
        ),
      );

      expect(await database.getCourses(), hasLength(1));
      await database.deleteCourse(course.id);
      expect(await database.getCourses(), isEmpty);
      expect(await database.getCourseById(course.id), isNull);
      expect(await database.getStudentsByCourse(course.id), isEmpty);
      expect(await database.getSessionsByCourse(course.id), isEmpty);
      expect(
        await database.getAttendanceRecordsBySession('session-1'),
        isEmpty,
      );
    });
  });
}
