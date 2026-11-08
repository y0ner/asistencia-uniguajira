import 'dart:convert';
import 'dart:typed_data';

import 'package:asistencia_uniguajira/core/constants/app_constants.dart';
import 'package:asistencia_uniguajira/core/crypto/ble_packet_codec.dart';
import 'package:asistencia_uniguajira/core/models/course_model.dart';
import 'package:asistencia_uniguajira/core/models/session_model.dart';
import 'package:asistencia_uniguajira/core/models/student_model.dart';
import 'package:asistencia_uniguajira/data/local/app_database.dart';
import 'package:asistencia_uniguajira/data/services/attendance_session_controller.dart';
import 'package:asistencia_uniguajira/data/services/ble_attendance_service.dart';
import 'package:asistencia_uniguajira/data/services/cloud_sync_service.dart';
import 'package:asistencia_uniguajira/data/services/demo_seed_service.dart';
import 'package:asistencia_uniguajira/data/services/excel_report_service.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Implementación simulada del transceptor BLE para el entorno de pruebas en memoria.
class _FakeBleAttendanceService extends BleAttendanceService {
  bool isScanActive = false;
  Uint8List? lastAdvertisedPacket;

  @override
  Future<void> startScan({Duration? timeout}) async {
    isScanActive = true;
  }

  @override
  Future<void> stopScan() async {
    isScanActive = false;
  }

  @override
  Future<void> startAdvertisingPacket(Uint8List packet16) async {
    lastAdvertisedPacket = packet16;
  }

  @override
  Future<void> stopAdvertising() async {
    lastAdvertisedPacket = null;
  }
}

/// Extrae de forma segura el valor en texto de una celda de Excel.
String _extractCellString(Data? cell) {
  final CellValue? value = cell?.value;
  if (value == null) {
    return '';
  }
  if (value is TextCellValue) {
    return value.value.text ?? '';
  }
  if (value is IntCellValue) {
    return value.value.toString();
  }
  if (value is DoubleCellValue) {
    return value.value.toString();
  }
  if (value is BoolCellValue) {
    return value.value.toString();
  }
  return value.toString();
}

void main() {
  sqfliteFfiInit();

  group('Suite Exhaustiva E2E de Sustentación (Etapa 5B)', () {
    late AppDatabase database;
    late DemoSeedService seedService;
    late CourseModel course;

    setUp(() async {
      database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      seedService = DemoSeedService(database: database);

      final result = await seedService.seedDefenseDemonstrationData(
        resetExisting: true,
      );
      course = result.course;
    });

    tearDown(() async {
      await database.close();
    });

    // -------------------------------------------------------------------------
    // Escenario 1: Siembra completa del escenario oficial
    // -------------------------------------------------------------------------
    test('1. Siembra completa del escenario oficial: verifica que seedDefenseDemonstrationData(resetExisting: true) crea el curso ING-SIS-1002, 12 estudiantes, 4 sesiones cerradas y 4 actas firmadas', () async {
      final result = await seedService.seedDefenseDemonstrationData(
        resetExisting: true,
      );

      expect(result.wasReset, isTrue);
      expect(result.course.code, DemoSeedService.demoCourseCode);
      expect(result.course.code, 'ING-SIS-1002');
      expect(result.course.name, DemoSeedService.demoCourseName);
      expect(result.course.name, 'PROYECTOS DE INGENIERIA II');
      expect(result.course.groupCode, DemoSeedService.demoCourseGroup);
      expect(result.course.groupCode, 'A1');
      expect(result.course.semester, DemoSeedService.demoSemester);
      expect(result.course.semester, '2026-2');
      expect(result.studentsSeeded, 12);
      expect(result.closedSessionsSeeded, 4);
      expect(result.signedActasCount, 4);
      expect(result.enrolledStudentCode, DemoSeedService.primaryStudentCode);
      expect(result.enrolledStudentCode, '0182120016');
      expect(result.enrolledBitIndex, 0);

      final dbCourse = await database.getCourseById(result.course.id);
      expect(dbCourse, isNotNull);
      expect(dbCourse!.code, 'ING-SIS-1002');
      expect(dbCourse.name, 'PROYECTOS DE INGENIERIA II');
      expect(dbCourse.groupCode, 'A1');
      expect(dbCourse.courseSecret, DemoSeedService.demoCourseSecret);

      final students = await database.getStudentsByCourse(result.course.id);
      expect(students.length, 12);

      final sessions = await database.getSessionsByCourse(result.course.id);
      expect(sessions.length, 4);

      for (final SessionModel session in sessions) {
        expect(session.closedAt, isNotNull);
        expect(session.closedAt, isNotEmpty);
        expect(session.bitmapHex, hasLength(AppConstants.bitmapHexLength));

        final signature = await database.getSessionActaSignature(session.id);
        expect(signature, isNotNull);
        expect(signature, hasLength(64));
        expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(signature!), isTrue);

        final actaJson = await database.getSessionActaJson(session.id);
        expect(actaJson, isNotNull);
        expect(actaJson, isNotEmpty);
      }
    });

    // -------------------------------------------------------------------------
    // Escenario 2: Preservación de ceros a la izquierda y asignación de bits
    // -------------------------------------------------------------------------
    test('2. Preservación de ceros a la izquierda y asignación de bits de los autores: comprueba que el Bit 00 tiene studentCode == "0182120016" (ISAZA VIDES YONER DE JESUS) y el Bit 01 tiene studentCode == "0182110072" (GARRIDO MEDINA ALVARO LUIS)', () async {
      final students = await database.getStudentsByCourse(course.id);
      expect(students.length, 12);

      // Bit 00: Autor Principal Yoner Isaza
      final author0 = students.firstWhere((StudentModel s) => s.bitIndex == 0);
      expect(author0.studentCode, '0182120016');
      expect(author0.studentCode, DemoSeedService.primaryStudentCode);
      expect(author0.studentCode.startsWith('0'), isTrue);
      expect(author0.studentCode.length, 10);
      expect(author0.fullName, 'ISAZA VIDES YONER DE JESUS');
      expect(author0.email, 'yisaza@uniguajira.edu.co');
      expect(author0.personalSecret, hasLength(64));

      // Bit 01: Coautor Álvaro Garrido
      final author1 = students.firstWhere((StudentModel s) => s.bitIndex == 1);
      expect(author1.studentCode, '0182110072');
      expect(author1.studentCode, DemoSeedService.secondaryStudentCode);
      expect(author1.studentCode.startsWith('0'), isTrue);
      expect(author1.studentCode.length, 10);
      expect(author1.fullName, 'GARRIDO MEDINA ALVARO LUIS');
      expect(author1.email, 'agarrido@uniguajira.edu.co');
      expect(author1.personalSecret, hasLength(64));

      // Verificación de unicidad e integridad para toda la nómina de 12
      final sortedBits = students.map((s) => s.bitIndex).toList()..sort();
      expect(sortedBits, List<int>.generate(12, (int i) => i));

      for (var i = 0; i < DemoSeedService.officialRoster.length; i++) {
        final officialEntry = DemoSeedService.officialRoster[i];
        final student = students.firstWhere((s) => s.bitIndex == i);

        expect(student.studentCode, officialEntry['code']);
        expect(student.studentCode.startsWith('0'), isTrue);
        expect(student.studentCode.length, 10);
        expect(student.fullName, officialEntry['name']);
        expect(student.email, officialEntry['email']);
        expect(student.personalSecret, hasLength(64));
        expect(
          RegExp(r'^[0-9a-f]{64}$').hasMatch(student.personalSecret),
          isTrue,
        );
      }
    });

    // -------------------------------------------------------------------------
    // Escenario 3: Auto-enrolamiento del expositor y verificación BLE
    // -------------------------------------------------------------------------
    test('3. Auto-enrolamiento del estudiante Bit 00 y verificación criptográfica BLE: comprueba que student_enrollments contiene la credencial de "0182120016" y que el paquete BLE de 16 bytes generado con sus semillas es validado exitosamente por BlePacketCodec.verifyStudentPacket', () async {
      final enrollments = await database.getStudentEnrollments();
      expect(enrollments, isNotEmpty);

      final enrollment = await database.getStudentEnrollmentByCourse(course.id);
      expect(enrollment, isNotNull);
      expect(enrollment!.studentCode, '0182120016');
      expect(enrollment.studentCode, DemoSeedService.primaryStudentCode);
      expect(enrollment.fullName, 'ISAZA VIDES YONER DE JESUS');
      expect(enrollment.bitIndex, 0);
      expect(enrollment.courseId, course.id);
      expect(enrollment.courseCode, 'ING-SIS-1002');
      expect(enrollment.courseName, 'PROYECTOS DE INGENIERIA II');
      expect(enrollment.deviceSecret, hasLength(64));
      expect(enrollment.sharedSecret, course.courseSecret);

      final student0 = await database.getStudentByCode(
        courseId: course.id,
        studentCode: '0182120016',
      );
      expect(student0, isNotNull);
      expect(enrollment.deviceSecret, student0!.personalSecret);

      // Construcción del paquete de anuncio BLE de 16 bytes
      final testTime = DateTime.utc(2026, 11, 8, 10, 15, 0);
      final timeTick = BlePacketCodec.computeTimeTick(testTime);
      const sessionPin = 42;

      final packet16 = BlePacketCodec.buildStudentBeaconBytes(
        courseId: course.id,
        bitIndex: enrollment.bitIndex,
        sessionPin: sessionPin,
        secretHex: enrollment.deviceSecret,
        timeTick: timeTick,
      );

      expect(packet16, hasLength(16));
      expect(packet16[2] & 0x80, BlePacketCodec.studentPacketFlag);
      expect(packet16[2] & 0x3F, 0);
      expect(packet16[3], sessionPin);

      // Verificación con BlePacketCodec.verifyStudentBeaconBytes
      final verification = BlePacketCodec.verifyStudentBeaconBytes(
        packet16: packet16,
        expectedCourseId: course.id,
        expectedSessionPin: sessionPin,
        secretHexByBitIndex: <int, String>{
          enrollment.bitIndex: enrollment.deviceSecret,
        },
        currentTimeTick: timeTick,
      );

      expect(verification.isValid, isTrue);
      expect(verification.bitIndex, 0);
      expect(verification.timeTick, timeTick);
      expect(verification.failureReason, isNull);

      // Prueba de rechazo de paquete alterado: PIN incorrecto
      final wrongPinVerification = BlePacketCodec.verifyStudentBeaconBytes(
        packet16: packet16,
        expectedCourseId: course.id,
        expectedSessionPin: 99,
        secretHexByBitIndex: <int, String>{
          enrollment.bitIndex: enrollment.deviceSecret,
        },
        currentTimeTick: timeTick,
      );
      expect(wrongPinVerification.isValid, isFalse);
      expect(wrongPinVerification.failureReason, contains('PIN'));

      // Prueba de rechazo de paquete alterado: Secreto personal inválido
      final wrongSecretVerification = BlePacketCodec.verifyStudentBeaconBytes(
        packet16: packet16,
        expectedCourseId: course.id,
        expectedSessionPin: sessionPin,
        secretHexByBitIndex: <int, String>{
          0: '0000000000000000000000000000000000000000000000000000000000000000',
        },
        currentTimeTick: timeTick,
      );
      expect(wrongSecretVerification.isValid, isFalse);
      expect(wrongSecretVerification.failureReason, contains('HMAC'));
    });

    // -------------------------------------------------------------------------
    // Escenario 4: Integridad e invariante matemático de las 4 actas
    // -------------------------------------------------------------------------
    test('4. Integridad e invariante matemático de las 4 actas en session_actas: verifica que las 4 actas poseen firmas HMAC-SHA256 de 64 caracteres hexadecimales y que en cada sesión la suma de presentes BLE, presentes MANUAL_INVERTED y ausentes es exactamente 12 (presentBle + presentManual + absent == 12)', () async {
      final sessions = await database.getSessionsByCourse(course.id);
      expect(sessions.length, 4);

      for (var i = 0; i < sessions.length; i++) {
        final session = sessions[i];

        final signature = await database.getSessionActaSignature(session.id);
        expect(signature, isNotNull);
        expect(signature, hasLength(64));
        expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(signature!), isTrue);

        final actaJsonString = await database.getSessionActaJson(session.id);
        expect(actaJsonString, isNotNull);
        final actaMap = jsonDecode(actaJsonString!) as Map<String, dynamic>;

        final totalEnrolled = actaMap['totalEnrolled'] as int;
        final presentBle = actaMap['presentBleCount'] as int;
        final presentManual = actaMap['presentManualCount'] as int;
        final absent = actaMap['absentCount'] as int;

        expect(totalEnrolled, 12);

        // INVARIANTE MATEMÁTICO CONTABLE ESTRICTO
        expect(
          presentBle + presentManual + absent,
          12,
          reason:
              'Invariante roto en sesión ${i + 1}: BLE=$presentBle, '
              'Manual=$presentManual, Ausentes=$absent',
        );

        final rawRecords = (actaMap['records'] as List)
            .cast<Map<String, dynamic>>();
        expect(rawRecords.length, 12);

        var bleCount = 0;
        var manualCount = 0;
        var absentCount = 0;

        for (final recordMap in rawRecords) {
          final status = recordMap['status'] as String;
          final method = recordMap['method'] as String?;

          if (status == AppConstants.attendanceStatusPresent) {
            if (method == AppConstants.attendanceMethodBleHmac) {
              bleCount++;
              expect(recordMap['verifyCode'], isNotNull);
              expect(recordMap['verifyCode'] as String, startsWith('UG-'));
              expect(recordMap['rssi'], isNotNull);
            } else if (method == AppConstants.attendanceMethodManualInverted) {
              manualCount++;
              expect(recordMap['verifyCode'], isNull);
            }
          } else if (status == AppConstants.attendanceStatusAbsent) {
            absentCount++;
            expect(method, isNull);
          }
        }

        expect(bleCount, presentBle);
        expect(manualCount, presentManual);
        expect(absentCount, absent);
        expect(bleCount + manualCount + absentCount, 12);

        // Verificación de integridad criptográfica contra el secreto del curso
        final canonicalMap = <String, Object?>{
          'sessionId': actaMap['sessionId'],
          'courseId': actaMap['courseId'],
          'courseCode': actaMap['courseCode'],
          'courseName': actaMap['courseName'],
          'sessionPin': actaMap['sessionPin'],
          'startedAtIso': actaMap['startedAtIso'],
          'closedAtIso': actaMap['closedAtIso'],
          'totalEnrolled': totalEnrolled,
          'presentBleCount': presentBle,
          'presentManualCount': presentManual,
          'absentCount': absent,
          'bitmapHex': actaMap['bitmapHex'],
          'records': rawRecords,
        };
        final canonicalJson = jsonEncode(canonicalMap);
        final computedSignature = DemoSeedService.signActaPayload(
          canonicalJson,
          course.courseSecret,
        );

        expect(signature, computedSignature);
      }
    });

    // -------------------------------------------------------------------------
    // Escenario 5: Verificación matemática del semáforo académico
    // -------------------------------------------------------------------------
    test('5. Verificación matemática del semáforo académico en ExcelReportService.buildCourseSummary: comprueba que existen exactamente 8 estudiantes en estado NORMAL (100% asistencia), 2 en ALERTA_INASISTENCIA (75% asistencia / 25% fallas) y 2 en PERDIDA_POR_FALLAS (50% asistencia / 50% fallas)', () async {
      final excelService = ExcelReportService(
        database: database,
        teacherEmail: DemoSeedService.demoTeacherEmail,
      );

      final summary = await excelService.buildCourseSummary(course.id);
      expect(summary.totalClosedSessions, 4);
      expect(summary.totalSignedActas, 4);
      expect(summary.students.length, 12);

      // 1. Grupo NORMAL: 8 estudiantes con 100% de asistencia
      final normalStudents = summary.students
          .where((s) => s.alertStatus == AttendanceAlertStatus.normal)
          .toList(growable: false);
      expect(
        normalStudents.length,
        8,
        reason: 'Debe haber exactamente 8 estudiantes en estado NORMAL',
      );
      for (final student in normalStudents) {
        expect(student.totalSessions, 4);
        expect(student.totalAttendances, 4);
        expect(student.totalAbsences, 0);
        expect(student.attendancePercentage, 100.0);
        expect(student.absencePercentage, 0.0);
        expect(student.isNormal, isTrue);
        expect(student.requiresAttention, isFalse);
        expect(student.failedByAbsences, isFalse);
      }

      // 2. Grupo ALERTA_INASISTENCIA: 2 estudiantes con 75% asistencia (25% fallas: 1 falla de 4)
      final alertStudents = summary.students
          .where((s) => s.alertStatus == AttendanceAlertStatus.attendanceAlert)
          .toList(growable: false);
      expect(
        alertStudents.length,
        2,
        reason: 'Debe haber exactamente 2 estudiantes en estado ALERTA_INASISTENCIA',
      );
      for (final student in alertStudents) {
        expect(student.totalSessions, 4);
        expect(student.totalAttendances, 3);
        expect(student.totalAbsences, 1);
        expect(student.attendancePercentage, 75.0);
        expect(student.absencePercentage, 25.0);
        expect(student.requiresAttention, isTrue);
        expect(student.isNormal, isFalse);
        expect(student.failedByAbsences, isFalse);
      }
      expect(alertStudents.map((s) => s.bitIndex).toSet(), <int>{
        8,
        9,
      }, reason: 'Los bits 8 y 9 deben ser quienes están en ALERTA');

      // 3. Grupo PERDIDA_POR_FALLAS: 2 estudiantes con 50% asistencia (50% fallas: 2 fallas de 4)
      final lostStudents = summary.students
          .where(
            (s) => s.alertStatus == AttendanceAlertStatus.failureByAbsences,
          )
          .toList(growable: false);
      expect(
        lostStudents.length,
        2,
        reason:
            'Debe haber exactamente 2 estudiantes en estado PERDIDA_POR_FALLAS',
      );
      for (final student in lostStudents) {
        expect(student.totalSessions, 4);
        expect(student.totalAttendances, 2);
        expect(student.totalAbsences, 2);
        expect(student.attendancePercentage, 50.0);
        expect(student.absencePercentage, 50.0);
        expect(student.failedByAbsences, isTrue);
        expect(student.isNormal, isFalse);
        expect(student.requiresAttention, isFalse);
      }
      expect(
        lostStudents.map((s) => s.bitIndex).toSet(),
        <int>{10, 11},
        reason:
            'Los bits 10 y 11 deben ser quienes están en PERDIDA POR FALLAS',
      );

      // Comprobación individual de los autores de la tesis
      final yonerMetric = summary.students.firstWhere(
        (s) => s.studentCode == '0182120016',
      );
      expect(yonerMetric.alertStatus, AttendanceAlertStatus.normal);
      expect(yonerMetric.bleAttendances, 4);
      expect(yonerMetric.manualAttendances, 0);
      expect(yonerMetric.totalAttendances, 4);

      final alvaroMetric = summary.students.firstWhere(
        (s) => s.studentCode == '0182110072',
      );
      expect(alvaroMetric.alertStatus, AttendanceAlertStatus.normal);
      expect(alvaroMetric.bleAttendances, 2);
      expect(alvaroMetric.manualAttendances, 2);
      expect(alvaroMetric.totalAttendances, 4);
    });

    // -------------------------------------------------------------------------
    // Escenario 6: Generación y decodificación binaria del Excel oficial
    // -------------------------------------------------------------------------
    test('6. Generación y decodificación binaria del Excel oficial (.xlsx de 4 hojas) sobre el curso sembrado: verifica las hojas Resumen, Detalle, Sesiones y Metadatos, la preservación como texto de "0182120016" y "0182110072", y la huella HMAC-SHA256 en Metadatos', () async {
      final excelService = ExcelReportService(
        database: database,
        teacherEmail: DemoSeedService.demoTeacherEmail,
      );

      final Uint8List workbookBytes = await excelService
          .generateCourseAttendanceWorkbook(course.id);
      expect(workbookBytes, isNotEmpty);

      final Excel excel = Excel.decodeBytes(workbookBytes);

      // 4 hojas reglamentarias
      const expectedSheets = <String>[
        'Resumen',
        'Detalle',
        'Sesiones',
        'Metadatos',
      ];
      expect(excel.tables.keys.toSet(), expectedSheets.toSet());
      expect(excel.tables.keys.length, 4);

      // ---------------------------------------------------------------------
      // Hoja 1: Resumen
      // ---------------------------------------------------------------------
      final Sheet summarySheet = excel.tables['Resumen']!;
      expect(summarySheet.rows.length, 13); // 1 encabezado + 12 estudiantes

      final summaryHeaders = summarySheet.rows[0]
          .map(_extractCellString)
          .toList(growable: false);
      expect(summaryHeaders, <String>[
        'BitIndex',
        'CodigoEstudiantil',
        'NombreCompleto',
        'Email',
        'TotalSesionesCerradas',
        'AsistenciasBLE',
        'AsistenciasManualInvertida',
        'TotalAsistencias',
        'TotalInasistencias',
        'PorcentajeAsistencia',
        'EstadoAlerta',
      ]);

      // Verificación de celda de texto para Yoner
      final rowYoner = summarySheet.rows.firstWhere(
        (r) => _extractCellString(r[1]) == '0182120016',
      );
      expect(rowYoner[1]?.value, isA<TextCellValue>());
      expect(_extractCellString(rowYoner[1]), '0182120016');
      expect(_extractCellString(rowYoner[2]), 'ISAZA VIDES YONER DE JESUS');
      expect(_extractCellString(rowYoner[4]), '4');
      expect(_extractCellString(rowYoner[5]), '4'); // 4 BLE
      expect(_extractCellString(rowYoner[6]), '0'); // 0 Manual
      expect(_extractCellString(rowYoner[7]), '4');
      expect(_extractCellString(rowYoner[8]), '0');
      expect(_extractCellString(rowYoner[9]), '100.0');
      expect(_extractCellString(rowYoner[10]), 'NORMAL');

      // Verificación de celda de texto para Álvaro
      final rowAlvaro = summarySheet.rows.firstWhere(
        (r) => _extractCellString(r[1]) == '0182110072',
      );
      expect(rowAlvaro[1]?.value, isA<TextCellValue>());
      expect(_extractCellString(rowAlvaro[1]), '0182110072');
      expect(_extractCellString(rowAlvaro[2]), 'GARRIDO MEDINA ALVARO LUIS');
      expect(_extractCellString(rowAlvaro[4]), '4');
      expect(_extractCellString(rowAlvaro[5]), '2'); // 2 BLE
      expect(_extractCellString(rowAlvaro[6]), '2'); // 2 Manual
      expect(_extractCellString(rowAlvaro[7]), '4');
      expect(_extractCellString(rowAlvaro[8]), '0');
      expect(_extractCellString(rowAlvaro[9]), '100.0');
      expect(_extractCellString(rowAlvaro[10]), 'NORMAL');

      // ---------------------------------------------------------------------
      // Hoja 2: Detalle
      // ---------------------------------------------------------------------
      final Sheet detailSheet = excel.tables['Detalle']!;
      expect(
        detailSheet.rows.length,
        49,
      ); // 1 encabezado + 48 registros (4 sesiones * 12)

      final detailHeaders = detailSheet.rows[0]
          .map(_extractCellString)
          .toList(growable: false);
      expect(
        detailHeaders,
        containsAll(<String>[
          'SesionID',
          'FechaSesion',
          'CodigoEstudiantil',
          'NombreCompleto',
          'Estado',
          'Metodo',
        ]),
      );

      final yonerDetailRows = detailSheet.rows
          .where((r) => _extractCellString(r[4]) == '0182120016')
          .toList(growable: false);
      expect(yonerDetailRows.length, 4);
      for (final row in yonerDetailRows) {
        expect(row[4]?.value, isA<TextCellValue>());
        expect(_extractCellString(row[4]), '0182120016');
        expect(_extractCellString(row[6]), 'PRESENT');
        expect(
          _extractCellString(row[7]),
          AppConstants.attendanceMethodBleHmac,
        );
      }

      final alvaroDetailRows = detailSheet.rows
          .where((r) => _extractCellString(r[4]) == '0182110072')
          .toList(growable: false);
      expect(alvaroDetailRows.length, 4);
      for (final row in alvaroDetailRows) {
        expect(row[4]?.value, isA<TextCellValue>());
        expect(_extractCellString(row[4]), '0182110072');
        expect(_extractCellString(row[6]), 'PRESENT');
      }

      // ---------------------------------------------------------------------
      // Hoja 3: Sesiones
      // ---------------------------------------------------------------------
      final Sheet sessionsSheet = excel.tables['Sesiones']!;
      expect(sessionsSheet.rows.length, 5); // 1 encabezado + 4 sesiones
      for (var i = 1; i <= 4; i++) {
        final row = sessionsSheet.rows[i];
        expect(_extractCellString(row[1]), course.id);
        expect(_extractCellString(row[4]), 'CERRADA');
        expect(_extractCellString(row[6]), hasLength(16));
        final hashActa = _extractCellString(row[10]);
        expect(hashActa, hasLength(64));
        expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(hashActa), isTrue);
      }

      // ---------------------------------------------------------------------
      // Hoja 4: Metadatos
      // ---------------------------------------------------------------------
      final Sheet metadataSheet = excel.tables['Metadatos']!;
      final metaMap = <String, String>{
        for (final row in metadataSheet.rows.skip(1))
          _extractCellString(row[0]): _extractCellString(row[1]),
      };

      expect(metaMap['Institucion'], 'Universidad de La Guajira');
      expect(metaMap['CodigoCurso'], 'ING-SIS-1002');
      expect(metaMap['NombreCurso'], 'PROYECTOS DE INGENIERIA II');
      expect(metaMap['Grupo'], 'A1');
      expect(metaMap['Semestre'], '2026-2');
      expect(metaMap['DocenteEmail'], DemoSeedService.demoTeacherEmail);
      expect(metaMap['TotalEstudiantesMatriculados'], '12');
      expect(metaMap['TotalSesionesCerradas'], '4');
      expect(metaMap['TotalActasFirmadas'], '4');

      final reportHmac = metaMap['HuellaIntegridadReporteHmacSha256'];
      expect(reportHmac, isNotNull);
      expect(reportHmac, hasLength(64));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(reportHmac!), isTrue);
    });

    // -------------------------------------------------------------------------
    // Escenario 7: Sincronización institucional hacia Google Sheets
    // -------------------------------------------------------------------------
    test('7. Sincronización institucional con CloudSyncService usando "mromero@uniguajira.edu.co": verifica que el payload JSON de Google Sheets es válido e incluye las 4 hojas y la firma del reporte', () async {
      final excelService = ExcelReportService(
        database: database,
        teacherEmail: DemoSeedService.demoTeacherEmail,
      );
      final cloudSyncService = CloudSyncService(
        database: database,
        excelReportService: excelService,
      );

      expect(
        cloudSyncService.isValidInstitutionalEmail(
          DemoSeedService.demoTeacherEmail,
        ),
        isTrue,
      );
      expect(
        cloudSyncService.isValidInstitutionalEmail('mromero@uniguajira.edu.co'),
        isTrue,
      );
      expect(
        cloudSyncService.isValidInstitutionalEmail('mromero@gmail.com'),
        isFalse,
      );
      expect(
        cloudSyncService.isValidInstitutionalEmail('invalido@hotmail.com'),
        isFalse,
      );

      final payload = await cloudSyncService.buildGoogleSheetsPayload(
        course.id,
      );
      expect(payload.courseId, course.id);
      expect(payload.courseCode, 'ING-SIS-1002');
      expect(payload.courseName, 'PROYECTOS DE INGENIERIA II');
      expect(payload.reportHmacSha256, hasLength(64));
      expect(
        RegExp(r'^[0-9a-f]{64}$').hasMatch(payload.reportHmacSha256),
        isTrue,
      );
      expect(payload.sheetNames, <String>[
        'Resumen',
        'Detalle',
        'Sesiones',
        'Metadatos',
      ]);
      expect(payload.workbookBytes, isNotNull);
      expect(payload.workbookBytes!, isNotEmpty);

      final jsonPayload = payload.toJson(includeWorkbookBytes: true);
      expect(jsonPayload['courseId'], course.id);
      expect(jsonPayload['courseCode'], 'ING-SIS-1002');
      expect(jsonPayload['courseName'], 'PROYECTOS DE INGENIERIA II');
      expect(jsonPayload['reportHmacSha256'], payload.reportHmacSha256);
      expect(jsonPayload['workbookBase64'], isNotNull);

      final sheetsMap = jsonPayload['sheets'] as Map<String, dynamic>;
      expect(
        sheetsMap.keys,
        containsAll(<String>['Resumen', 'Detalle', 'Sesiones', 'Metadatos']),
      );
      expect((sheetsMap['Resumen'] as List).length, 13);
      expect((sheetsMap['Detalle'] as List).length, 49);
      expect((sheetsMap['Sesiones'] as List).length, 5);
      expect((sheetsMap['Metadatos'] as List).length, greaterThan(10));

      var transportInvoked = false;
      CloudSyncPayload? deliveredPayload;

      final syncResult = await cloudSyncService.syncCourseToInstitutionalCloud(
        courseId: course.id,
        institutionalEmail: DemoSeedService.demoTeacherEmail,
        transportOverride: (CloudSyncPayload p) async {
          transportInvoked = true;
          deliveredPayload = p;
          return true;
        },
      );

      expect(transportInvoked, isTrue);
      expect(syncResult.status, CloudSyncStatus.synced);
      expect(syncResult.isSynced, isTrue);
      expect(syncResult.transportUsed, isTrue);
      expect(syncResult.transportSucceeded, isTrue);
      expect(syncResult.institutionalEmail, DemoSeedService.demoTeacherEmail);
      expect(syncResult.reportSignatureHmac, payload.reportHmacSha256);
      expect(deliveredPayload, isNotNull);
      expect(deliveredPayload!.reportHmacSha256, payload.reportHmacSha256);
    });

    // -------------------------------------------------------------------------
    // Escenario 8: Idempotencia y reinicio limpio
    // -------------------------------------------------------------------------
    test('8. Idempotencia y reinicio limpio: comprueba que llamar a seedDefenseDemonstrationData(resetExisting: false) no duplica datos, y que llamar con resetExisting: true tras agregar datos extra restaura exactamente los 12 estudiantes y las 4 sesiones', () async {
      // 1. Estado inicial sembrado en setUp
      final initialCourses = await database.getAllCourses();
      expect(initialCourses.length, 1);
      final initialCourse = initialCourses.first;
      final initialStudents = await database.getStudentsByCourse(
        initialCourse.id,
      );
      expect(initialStudents.length, 12);
      final initialSessions = await database.getSessionsByCourse(
        initialCourse.id,
      );
      expect(initialSessions.length, 4);

      // 2. Invocación idempotente sin reseteo
      final idempotentResult = await seedService.seedDefenseDemonstrationData(
        resetExisting: false,
      );
      expect(idempotentResult.wasReset, isFalse);
      expect(idempotentResult.course.id, initialCourse.id);
      expect(idempotentResult.studentsSeeded, 12);
      expect(idempotentResult.closedSessionsSeeded, 4);
      expect(idempotentResult.signedActasCount, 4);

      final coursesAfterIdempotence = await database.getAllCourses();
      expect(coursesAfterIdempotence.length, 1);
      final studentsAfterIdempotence = await database.getStudentsByCourse(
        initialCourse.id,
      );
      expect(studentsAfterIdempotence.length, 12);
      final sessionsAfterIdempotence = await database.getSessionsByCourse(
        initialCourse.id,
      );
      expect(sessionsAfterIdempotence.length, 4);

      // 3. Contaminación del escenario: inserción de estudiante y sesión extra
      final extraStudent = StudentModel(
        id: 'intrusive-student-uuid',
        courseId: initialCourse.id,
        studentCode: '0182199999',
        fullName: 'ESTUDIANTE INTRUSO DE PRUEBA',
        email: 'intruso@uniguajira.edu.co',
        bitIndex: 12,
        personalSecret:
            '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        enrolledAt: DateTime.now().toIso8601String(),
      );
      await database.insertStudent(extraStudent);

      final extraSession = SessionModel(
        id: 'intrusive-session-uuid',
        courseId: initialCourse.id,
        startedAt: DateTime.now().toIso8601String(),
        roomPin: '99',
        bitmapHex: AppConstants.emptyBitmapHex,
      );
      await database.insertSession(extraSession);

      expect((await database.getStudentsByCourse(initialCourse.id)).length, 13);
      expect((await database.getSessionsByCourse(initialCourse.id)).length, 5);

      // 4. Reinicio limpio con resetExisting: true
      final cleanResetResult = await seedService.seedDefenseDemonstrationData(
        resetExisting: true,
      );
      expect(cleanResetResult.wasReset, isTrue);
      expect(cleanResetResult.studentsSeeded, 12);
      expect(cleanResetResult.closedSessionsSeeded, 4);
      expect(cleanResetResult.signedActasCount, 4);

      final coursesAfterReset = await database.getAllCourses();
      expect(coursesAfterReset.length, 1);
      final cleanCourse = coursesAfterReset.first;

      final studentsAfterReset = await database.getStudentsByCourse(
        cleanCourse.id,
      );
      expect(studentsAfterReset.length, 12);
      expect(
        studentsAfterReset.any((s) => s.studentCode == '0182199999'),
        isFalse,
        reason: 'El estudiante intruso debe haber sido eliminado en cascada',
      );

      final sessionsAfterReset = await database.getSessionsByCourse(
        cleanCourse.id,
      );
      expect(sessionsAfterReset.length, 4);
      expect(
        sessionsAfterReset.any((s) => s.id == 'intrusive-session-uuid'),
        isFalse,
        reason: 'La sesión intrusa debe haber sido eliminada en cascada',
      );

      for (final session in sessionsAfterReset) {
        expect(session.closedAt, isNotNull);
      }

      final enrollment = await database.getStudentEnrollmentByCourse(
        cleanCourse.id,
      );
      expect(enrollment, isNotNull);
      expect(enrollment!.studentCode, DemoSeedService.primaryStudentCode);
    });

    // -------------------------------------------------------------------------
    // Escenario 9: Simulación en vivo de la 5ta sesión de sustentación
    // -------------------------------------------------------------------------
    test('9. Simulación en vivo de la 5ta sesión de sustentación: abre una 5ta sesión con AttendanceSessionController sobre el curso sembrado, inyecta el beacon BLE del Bit 00 ("0182120016"), marca por Lista Invertida al Bit 01 ("0182110072"), cierra y firma el acta, comprobando que el curso pasa a tener 5 sesiones cerradas y 5 actas firmadas', () async {
      final bleService = _FakeBleAttendanceService();
      final controller = AttendanceSessionController(
        database: database,
        bleService: bleService,
      );

      // Verificación previa de 4 sesiones
      final sessionsBefore = await database.getSessionsByCourse(course.id);
      expect(sessionsBefore.length, 4);

      // 1. Apertura de la 5ta sesión por el docente con PIN verbal '33'
      const pin = 33;
      final activeState = await controller.startTeacherSession(
        course: course,
        customPin: pin,
      );
      expect(activeState.isOpen, isTrue);
      expect(activeState.pin, pin);
      expect(activeState.sessionPin, '33');
      expect(activeState.totalEnrolled, 12);
      expect(activeState.presentBitIndices, isEmpty);

      // 2. Inyección de anuncio BLE para Bit 00 (Yoner Isaza - '0182120016')
      final student0 = await database.getStudentByCode(
        courseId: course.id,
        studentCode: DemoSeedService.primaryStudentCode,
      );
      expect(student0, isNotNull);
      expect(student0!.bitIndex, 0);

      final defenseTime = DateTime.utc(2026, 11, 8, 16, 0, 0);
      final timeTick = BlePacketCodec.computeTimeTick(defenseTime);
      final beaconBit00 = BlePacketCodec.buildStudentBeaconBytes(
        courseId: course.id,
        bitIndex: 0,
        sessionPin: pin,
        secretHex: student0.personalSecret,
        timeTick: timeTick,
      );

      final outcome0 = await controller.processIncomingStudentPacket(
        packet16: beaconBit00,
        rssi: -52,
        nowOverride: defenseTime,
      );
      expect(outcome0.isAccepted, isTrue);
      expect(outcome0.bitIndex, 0);
      expect(outcome0.student?.studentCode, '0182120016');
      expect(outcome0.verifyCode, startsWith('UG-'));
      expect(
        BlePacketCodec.isStudentBitSet(controller.state!.bitmap8, 0),
        isTrue,
      );

      // 3. Marcación por Lista Invertida para Bit 01 (Álvaro Garrido - '0182110072')
      final student1 = await database.getStudentByCode(
        courseId: course.id,
        studentCode: DemoSeedService.secondaryStudentCode,
      );
      expect(student1, isNotNull);
      expect(student1!.bitIndex, 1);

      await controller.toggleManualAttendance(
        studentId: student1.id,
        isPresent: true,
        observation: 'Asistencia manual verificada en sustentación pública',
      );
      expect(
        BlePacketCodec.isStudentBitSet(controller.state!.bitmap8, 1),
        isTrue,
      );

      // Comprobación de que exactamente los bits 0 y 1 están encendidos en el Bitmap
      expect(
        BlePacketCodec.extractPresentBitIndices(controller.state!.bitmap8),
        <int>[0, 1],
      );

      // 4. Cierre y firma del acta de la 5ta sesión con HMAC-SHA256
      final closedAt5 = DateTime.utc(2026, 11, 8, 16, 45, 0);
      final signedActa5 = await controller.closeAndSignSession(
        closedAtOverride: closedAt5,
      );

      expect(signedActa5.actaHmacSignature, hasLength(64));
      expect(signedActa5.verifySignature(course.courseSecret), isTrue);
      expect(signedActa5.presentBleCount, 1);
      expect(signedActa5.presentManualCount, 1);
      expect(signedActa5.absentCount, 10);
      expect(signedActa5.totalEnrolled, 12);
      expect(
        signedActa5.presentBleCount +
            signedActa5.presentManualCount +
            signedActa5.absentCount,
        12,
      );

      // 5. Verificación final en SQLite: el curso pasa a tener 5 sesiones cerradas y 5 actas firmadas
      final sessionsAfter = await database.getSessionsByCourse(course.id);
      expect(sessionsAfter.length, 5);

      final closedSessions = sessionsAfter
          .where((s) => s.closedAt != null)
          .toList(growable: false);
      expect(closedSessions.length, 5);

      var validActasCount = 0;
      for (final session in sessionsAfter) {
        final sig = await database.getSessionActaSignature(session.id);
        if (sig != null &&
            sig.length == 64 &&
            RegExp(r'^[0-9a-f]{64}$').hasMatch(sig)) {
          validActasCount++;
        }
      }
      expect(
        validActasCount,
        5,
        reason:
            'El curso debe contar con exactamente 5 actas firmadas en SQLite',
      );

      await controller.dispose();
      await bleService.dispose();
    });
  });
}
