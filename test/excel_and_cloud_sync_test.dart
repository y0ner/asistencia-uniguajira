import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:asistencia_uniguajira/core/constants/app_constants.dart';
import 'package:asistencia_uniguajira/core/crypto/ble_packet_codec.dart';
import 'package:asistencia_uniguajira/core/models/attendance_record_model.dart';
import 'package:asistencia_uniguajira/core/models/course_model.dart';
import 'package:asistencia_uniguajira/core/models/session_model.dart';
import 'package:asistencia_uniguajira/core/models/student_model.dart';
import 'package:asistencia_uniguajira/data/local/app_database.dart';
import 'package:asistencia_uniguajira/data/services/attendance_session_controller.dart';
import 'package:asistencia_uniguajira/data/services/ble_attendance_service.dart';
import 'package:asistencia_uniguajira/data/services/cloud_sync_service.dart';
import 'package:asistencia_uniguajira/data/services/excel_report_service.dart';
import 'package:crypto/crypto.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const String _testCourseSecret =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const String _testTeacherEmail = 'docente@uniguajira.edu.co';

class _FakeBleAttendanceService extends BleAttendanceService {
  @override
  Future<void> startScan({Duration? timeout}) async {}

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> startAdvertisingPacket(Uint8List packet16) async {}

  @override
  Future<void> stopAdvertising() async {}
}

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

double _extractCellDouble(Data? cell) {
  final text = _extractCellString(cell);
  return double.tryParse(text) ?? 0.0;
}

CourseModel _buildCourse({
  String id = 'course-sist-401',
  String code = 'SIST-401',
  String name = 'Arquitectura de Software',
  String groupCode = '01',
  String semester = '2026-2',
}) {
  return CourseModel(
    id: id,
    code: code,
    name: name,
    groupCode: groupCode,
    semester: semester,
    courseSecret: _testCourseSecret,
    createdAt: '2026-11-06T08:00:00.000Z',
  );
}

StudentModel _buildStudent({
  required String id,
  required String courseId,
  required String studentCode,
  required String fullName,
  required int bitIndex,
  required String personalSecret,
  String? email,
}) {
  return StudentModel(
    id: id,
    courseId: courseId,
    studentCode: studentCode,
    fullName: fullName,
    email: email ?? '$studentCode@uniguajira.edu.co',
    bitIndex: bitIndex,
    personalSecret: personalSecret,
    enrolledAt: '2026-11-06T08:05:00.000Z',
  );
}

void main() {
  sqfliteFfiInit();

  group('ExcelReportService y CloudSyncService (Etapa 4B)', () {
    late AppDatabase database;
    late _FakeBleAttendanceService bleService;
    late AttendanceSessionController controller;
    late ExcelReportService excelService;
    late CloudSyncService cloudSyncService;
    late CourseModel course;
    late StudentModel student0;
    late StudentModel student1;
    late StudentModel student2;
    late StudentModel student3;

    setUp(() async {
      database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      bleService = _FakeBleAttendanceService();
      controller = AttendanceSessionController(
        database: database,
        bleService: bleService,
      );
      excelService = ExcelReportService(
        database: database,
        teacherEmail: _testTeacherEmail,
      );
      cloudSyncService = CloudSyncService(
        database: database,
        excelReportService: excelService,
      );

      course = _buildCourse();
      await database.insertCourse(course);

      student0 = _buildStudent(
        id: 'student-id-0',
        courseId: course.id,
        studentCode: '0182120016',
        fullName: 'ALVARO LUIS GARRIDO MEDINA',
        bitIndex: 0,
        personalSecret:
            '1111111111111111111111111111111111111111111111111111111111111111',
      );
      student1 = _buildStudent(
        id: 'student-id-1',
        courseId: course.id,
        studentCode: '0182110072',
        fullName: 'MARIA CAMILA IPUANA',
        bitIndex: 1,
        personalSecret:
            '2222222222222222222222222222222222222222222222222222222222222222',
      );
      student2 = _buildStudent(
        id: 'student-id-2',
        courseId: course.id,
        studentCode: '0182120033',
        fullName: 'JUAN CARLOS PEREZ GOMEZ',
        bitIndex: 2,
        personalSecret:
            '3333333333333333333333333333333333333333333333333333333333333333',
      );
      student3 = _buildStudent(
        id: 'student-id-3',
        courseId: course.id,
        studentCode: '0182120044',
        fullName: 'DANIELA VALENTINA OROZCO',
        bitIndex: 3,
        personalSecret:
            '4444444444444444444444444444444444444444444444444444444444444444',
      );

      for (final StudentModel student in <StudentModel>[
        student0,
        student1,
        student2,
        student3,
      ]) {
        await database.insertStudent(student);
      }
    });

    tearDown(() async {
      await controller.dispose();
      await bleService.dispose();
      await database.close();
    });

    test(
      'Flujo completo de datos: 2 sesiones con BLE, manual invertida y actas firmadas',
      () async {
        final fixedNow1 = DateTime.utc(2026, 11, 6, 9, 0, 0);
        final tick1 = BlePacketCodec.computeTimeTick(fixedNow1);

        // --- SESIÓN 1 ---
        await controller.startTeacherSession(course: course, customPin: 21);

        // Estudiante 0 detectado vía BLE
        final packet0 = BlePacketCodec.buildStudentBeaconBytes(
          courseId: course.id,
          bitIndex: student0.bitIndex,
          sessionPin: 21,
          secretHex: student0.personalSecret,
          timeTick: tick1,
        );
        final detection0 = await controller.processIncomingStudentPacket(
          packet16: packet0,
          rssi: -64,
          nowOverride: fixedNow1,
        );
        expect(detection0.isAccepted, isTrue);

        // Estudiante 1 marcado manualmente en lista invertida
        await controller.toggleManualAttendance(
          studentId: student1.id,
          isPresent: true,
          observation: 'Llegada justificada por lluvia',
        );

        // Estudiante 2 y 3 quedan AUSENTES en Sesión 1
        final acta1 = await controller.closeAndSignSession(
          closedAtOverride: DateTime.utc(2026, 11, 6, 9, 45, 0),
        );
        expect(acta1.presentBleCount, 1);
        expect(acta1.presentManualCount, 1);
        expect(acta1.absentCount, 2);
        expect(acta1.verifySignature(course.courseSecret), isTrue);

        // Comprobación en base de datos SQLite (session_actas)
        final storedActa1Signature = await database.getSessionActaSignature(
          acta1.sessionId,
        );
        expect(storedActa1Signature, acta1.actaHmacSignature);
        expect(storedActa1Signature, isNotEmpty);

        // --- SESIÓN 2 ---
        final fixedNow2 = DateTime.utc(2026, 11, 7, 9, 0, 0);
        final tick2 = BlePacketCodec.computeTimeTick(fixedNow2);

        await controller.startTeacherSession(course: course, customPin: 84);

        // Estudiante 0 detectado vía BLE
        final packet0Session2 = BlePacketCodec.buildStudentBeaconBytes(
          courseId: course.id,
          bitIndex: student0.bitIndex,
          sessionPin: 84,
          secretHex: student0.personalSecret,
          timeTick: tick2,
        );
        final detection0Session2 = await controller.processIncomingStudentPacket(
          packet16: packet0Session2,
          rssi: -58,
          nowOverride: fixedNow2,
        );
        expect(detection0Session2.isAccepted, isTrue);

        // Estudiante 2 detectado vía BLE
        final packet2Session2 = BlePacketCodec.buildStudentBeaconBytes(
          courseId: course.id,
          bitIndex: student2.bitIndex,
          sessionPin: 84,
          secretHex: student2.personalSecret,
          timeTick: tick2,
        );
        final detection2Session2 = await controller.processIncomingStudentPacket(
          packet16: packet2Session2,
          rssi: -60,
          nowOverride: fixedNow2,
        );
        expect(detection2Session2.isAccepted, isTrue);

        // Estudiante 3 marcado en lista invertida
        await controller.toggleManualAttendance(
          studentId: student3.id,
          isPresent: true,
          observation: 'Asistencia confirmada verbalmente',
        );

        // Estudiante 1 queda AUSENTE en Sesión 2
        final acta2 = await controller.closeAndSignSession(
          closedAtOverride: DateTime.utc(2026, 11, 7, 9, 50, 0),
        );
        expect(acta2.presentBleCount, 2);
        expect(acta2.presentManualCount, 1);
        expect(acta2.absentCount, 1);
        expect(acta2.verifySignature(course.courseSecret), isTrue);

        final storedActa2Signature = await database.getSessionActaSignature(
          acta2.sessionId,
        );
        expect(storedActa2Signature, acta2.actaHmacSignature);

        // --- GENERACIÓN Y DECODIFICACIÓN DEL LIBRO EXCEL (.xlsx) ---
        final Uint8List workbookBytes =
            await excelService.generateCourseAttendanceWorkbook(course.id);
        expect(workbookBytes, isNotEmpty);

        final Excel excel = Excel.decodeBytes(workbookBytes);

        // Exactamente 4 hojas reglamentarias
        const expectedSheets = <String>[
          'Resumen',
          'Detalle',
          'Sesiones',
          'Metadatos',
        ];
        expect(excel.tables.keys.toSet(), expectedSheets.toSet());
        expect(excel.tables.keys.length, 4);

        // =====================================================================
        // HOJA 1: RESUMEN
        // =====================================================================
        final Sheet summarySheet = excel.tables['Resumen']!;
        expect(summarySheet.rows, isNotEmpty);

        // Encabezados
        final List<String> summaryHeaders = summarySheet.rows[0]
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

        // Verificación de filas de estudiantes (4 estudiantes matriculados)
        expect(summarySheet.rows.length, 5); // 1 encabezado + 4 filas

        // Fila estudiante 0: '0182120016'
        final rowStud0 = summarySheet.rows[1];
        expect(rowStud0[1]?.value, isA<TextCellValue>());
        expect(_extractCellString(rowStud0[1]), '0182120016');
        expect(_extractCellString(rowStud0[2]), 'ALVARO LUIS GARRIDO MEDINA');
        expect(_extractCellString(rowStud0[4]), '2'); // 2 sesiones cerradas
        expect(_extractCellString(rowStud0[5]), '2'); // 2 asistencias BLE
        expect(_extractCellString(rowStud0[6]), '0'); // 0 manual
        expect(_extractCellString(rowStud0[7]), '2'); // total asistencias
        expect(_extractCellString(rowStud0[8]), '0'); // inasistencias
        expect(_extractCellDouble(rowStud0[9]), 100.0); // % asistencia
        expect(
          _extractCellString(rowStud0[10]),
          AttendanceAlertStatus.normal,
        );

        // Fila estudiante 1: '0182110072' (con cero a la izquierda preservado)
        final rowStud1 = summarySheet.rows[2];
        expect(rowStud1[1]?.value, isA<TextCellValue>());
        expect(_extractCellString(rowStud1[1]), '0182110072');
        expect(_extractCellString(rowStud1[2]), 'MARIA CAMILA IPUANA');
        expect(_extractCellString(rowStud1[4]), '2');
        expect(_extractCellString(rowStud1[5]), '0'); // 0 BLE
        expect(_extractCellString(rowStud1[6]), '1'); // 1 manual
        expect(_extractCellString(rowStud1[7]), '1'); // total asistencias
        expect(_extractCellString(rowStud1[8]), '1'); // 1 inasistencia (50%)
        expect(_extractCellDouble(rowStud1[9]), 50.0);
        expect(
          _extractCellString(rowStud1[10]),
          AttendanceAlertStatus.failureByAbsences,
        );

        // Fila estudiante 2: '0182120033'
        final rowStud2 = summarySheet.rows[3];
        expect(_extractCellString(rowStud2[1]), '0182120033');
        expect(_extractCellString(rowStud2[4]), '2');
        expect(_extractCellString(rowStud2[5]), '1'); // 1 BLE
        expect(_extractCellString(rowStud2[6]), '0');
        expect(_extractCellString(rowStud2[7]), '1');
        expect(_extractCellString(rowStud2[8]), '1');
        expect(_extractCellDouble(rowStud2[9]), 50.0);
        expect(
          _extractCellString(rowStud2[10]),
          AttendanceAlertStatus.failureByAbsences,
        );

        // Fila estudiante 3: '0182120044'
        final rowStud3 = summarySheet.rows[4];
        expect(_extractCellString(rowStud3[1]), '0182120044');
        expect(_extractCellString(rowStud3[4]), '2');
        expect(_extractCellString(rowStud3[5]), '0');
        expect(_extractCellString(rowStud3[6]), '1'); // 1 manual
        expect(_extractCellString(rowStud3[7]), '1');
        expect(_extractCellString(rowStud3[8]), '1');
        expect(_extractCellDouble(rowStud3[9]), 50.0);
        expect(
          _extractCellString(rowStud3[10]),
          AttendanceAlertStatus.failureByAbsences,
        );

        // =====================================================================
        // HOJA 2: DETALLE
        // =====================================================================
        final Sheet detailSheet = excel.tables['Detalle']!;
        expect(detailSheet.rows, isNotEmpty);

        final List<String> detailHeaders = detailSheet.rows[0]
            .map(_extractCellString)
            .toList(growable: false);
        expect(detailHeaders, <String>[
          'SesionID',
          'FechaApertura',
          'FechaCierre',
          'BitIndex',
          'CodigoEstudiantil',
          'NombreCompleto',
          'EstadoAsistencia',
          'MetodoRegistro',
          'RssiDbm',
          'TimeTick',
          'Observacion',
        ]);

        // 4 estudiantes x 2 sesiones cerradas = 8 filas de datos + 1 encabezado = 9 filas
        expect(detailSheet.rows.length, 9);

        // En Sesión 1:
        // Estudiante 0: PRESENT, BLE_HMAC
        final s1Stud0 = detailSheet.rows[1];
        expect(_extractCellString(s1Stud0[0]), acta1.sessionId);
        expect(_extractCellString(s1Stud0[4]), '0182120016');
        expect(_extractCellString(s1Stud0[6]), 'PRESENT');
        expect(
          _extractCellString(s1Stud0[7]),
          AppConstants.attendanceMethodBleHmac,
        );

        // Estudiante 1: PRESENT, MANUAL_INVERTED con observación
        final s1Stud1 = detailSheet.rows[2];
        expect(_extractCellString(s1Stud1[0]), acta1.sessionId);
        expect(_extractCellString(s1Stud1[4]), '0182110072');
        expect(_extractCellString(s1Stud1[6]), 'PRESENT');
        expect(
          _extractCellString(s1Stud1[7]),
          AppConstants.attendanceMethodManualInverted,
        );
        expect(
          _extractCellString(s1Stud1[10]),
          'Llegada justificada por lluvia',
        );

        // Estudiante 2: ABSENT
        final s1Stud2 = detailSheet.rows[3];
        expect(_extractCellString(s1Stud2[0]), acta1.sessionId);
        expect(_extractCellString(s1Stud2[4]), '0182120033');
        expect(_extractCellString(s1Stud2[6]), 'ABSENT');
        expect(_extractCellString(s1Stud2[7]), '');

        // Estudiante 3: ABSENT
        final s1Stud3 = detailSheet.rows[4];
        expect(_extractCellString(s1Stud3[0]), acta1.sessionId);
        expect(_extractCellString(s1Stud3[4]), '0182120044');
        expect(_extractCellString(s1Stud3[6]), 'ABSENT');
        expect(_extractCellString(s1Stud3[7]), '');

        // En Sesión 2:
        // Estudiante 0: PRESENT, BLE_HMAC
        final s2Stud0 = detailSheet.rows[5];
        expect(_extractCellString(s2Stud0[0]), acta2.sessionId);
        expect(_extractCellString(s2Stud0[4]), '0182120016');
        expect(_extractCellString(s2Stud0[6]), 'PRESENT');
        expect(
          _extractCellString(s2Stud0[7]),
          AppConstants.attendanceMethodBleHmac,
        );

        // Estudiante 1: ABSENT
        final s2Stud1 = detailSheet.rows[6];
        expect(_extractCellString(s2Stud1[0]), acta2.sessionId);
        expect(_extractCellString(s2Stud1[4]), '0182110072');
        expect(_extractCellString(s2Stud1[6]), 'ABSENT');
        expect(_extractCellString(s2Stud1[7]), '');

        // Estudiante 2: PRESENT, BLE_HMAC
        final s2Stud2 = detailSheet.rows[7];
        expect(_extractCellString(s2Stud2[0]), acta2.sessionId);
        expect(_extractCellString(s2Stud2[4]), '0182120033');
        expect(_extractCellString(s2Stud2[6]), 'PRESENT');
        expect(
          _extractCellString(s2Stud2[7]),
          AppConstants.attendanceMethodBleHmac,
        );

        // Estudiante 3: PRESENT, MANUAL_INVERTED con observación
        final s2Stud3 = detailSheet.rows[8];
        expect(_extractCellString(s2Stud3[0]), acta2.sessionId);
        expect(_extractCellString(s2Stud3[4]), '0182120044');
        expect(_extractCellString(s2Stud3[6]), 'PRESENT');
        expect(
          _extractCellString(s2Stud3[7]),
          AppConstants.attendanceMethodManualInverted,
        );
        expect(
          _extractCellString(s2Stud3[10]),
          'Asistencia confirmada verbalmente',
        );

        // =====================================================================
        // HOJA 3: SESIONES
        // =====================================================================
        final Sheet sessionsSheet = excel.tables['Sesiones']!;
        expect(sessionsSheet.rows, isNotEmpty);

        final List<String> sessionHeaders = sessionsSheet.rows[0]
            .map(_extractCellString)
            .toList(growable: false);
        expect(sessionHeaders, <String>[
          'SesionID',
          'CursoID',
          'FechaApertura',
          'FechaCierre',
          'EstadoSesion',
          'PinVerbal',
          'BitmapHexFinal',
          'TotalPresentesBLE',
          'TotalManualInvertida',
          'TotalAusentes',
          'HashActaHmacSha256',
        ]);

        expect(sessionsSheet.rows.length, 3); // Encabezado + 2 sesiones

        // Fila Sesión 1
        final rowSes1 = sessionsSheet.rows[1];
        expect(_extractCellString(rowSes1[0]), acta1.sessionId);
        expect(_extractCellString(rowSes1[1]), course.id);
        expect(_extractCellString(rowSes1[4]), 'CERRADA');
        expect(_extractCellString(rowSes1[5]), '21');
        expect(_extractCellString(rowSes1[6]), acta1.bitmapHex);
        expect(_extractCellString(rowSes1[7]), '1'); // TotalPresentesBLE
        expect(_extractCellString(rowSes1[8]), '1'); // TotalManualInvertida
        expect(_extractCellString(rowSes1[9]), '2'); // TotalAusentes
        expect(_extractCellString(rowSes1[10]), acta1.actaHmacSignature);

        // Fila Sesión 2
        final rowSes2 = sessionsSheet.rows[2];
        expect(_extractCellString(rowSes2[0]), acta2.sessionId);
        expect(_extractCellString(rowSes2[1]), course.id);
        expect(_extractCellString(rowSes2[4]), 'CERRADA');
        expect(_extractCellString(rowSes2[5]), '84');
        expect(_extractCellString(rowSes2[6]), acta2.bitmapHex);
        expect(_extractCellString(rowSes2[7]), '2'); // TotalPresentesBLE
        expect(_extractCellString(rowSes2[8]), '1'); // TotalManualInvertida
        expect(_extractCellString(rowSes2[9]), '1'); // TotalAusentes
        expect(_extractCellString(rowSes2[10]), acta2.actaHmacSignature);

        // =====================================================================
        // HOJA 4: METADATOS
        // =====================================================================
        final Sheet metadataSheet = excel.tables['Metadatos']!;
        expect(metadataSheet.rows, isNotEmpty);

        final metaRows = metadataSheet.rows;
        expect(_extractCellString(metaRows[0][0]), 'Clave');
        expect(_extractCellString(metaRows[0][1]), 'Valor');

        final Map<String, String> metaMap = <String, String>{
          for (final List<Data?> r in metaRows.skip(1))
            _extractCellString(r[0]): _extractCellString(r[1]),
        };

        expect(metaMap['Institucion'], 'Universidad de La Guajira');
        expect(
          metaMap['Sistema'],
          'Asistencia Multimodal Uniguajira (BLE + Mapa de Bits 8B)',
        );
        expect(metaMap['CursoID'], course.id);
        expect(metaMap['CodigoCurso'], 'SIST-401');
        expect(metaMap['NombreCurso'], 'Arquitectura de Software');
        expect(metaMap['Grupo'], '01');
        expect(metaMap['Semestre'], '2026-2');
        expect(metaMap['DocenteEmail'], _testTeacherEmail);
        expect(metaMap['TotalEstudiantesMatriculados'], '4');
        expect(
          metaMap['CupoMaximoBitmap'],
          AppConstants.bitmapBitCount.toString(),
        );
        expect(metaMap['TotalSesionesCerradas'], '2');
        expect(metaMap['TotalActasFirmadas'], '2');
        expect(metaMap['FechaGeneracionISO8601'], isNotEmpty);

        // Huella criptográfica HMAC-SHA256 del reporte
        final reportSignature = metaMap['HuellaIntegridadReporteHmacSha256'];
        expect(reportSignature, isNotNull);
        expect(reportSignature, hasLength(64));
        expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(reportSignature!), isTrue);

        // Comprobación matemática exacta del HMAC del reporte
        final expectedHmacSignatures = <String>[
          acta1.actaHmacSignature,
          acta2.actaHmacSignature,
        ]..sort();
        final manualHmac = Hmac(
          sha256,
          utf8.encode(course.courseSecret.toLowerCase()),
        ).convert(utf8.encode(expectedHmacSignatures.join())).toString();
        expect(reportSignature, manualHmac);
      },
    );

    test(
      'Evaluación exhaustiva de estados de alerta académica (NORMAL, ALERTA_INASISTENCIA, PERDIDA_POR_FALLAS)',
      () async {
        // Creamos un curso con 5 sesiones cerradas para evaluar los 3 rangos:
        // Estudiante A: 0 fallas (0% inasistencia) -> NORMAL (< 20%)
        // Estudiante B: 1 falla (20% inasistencia) -> ALERTA_INASISTENCIA (20% <= inasistencia < 30%)
        // Estudiante C: 2 fallas (40% inasistencia) -> PERDIDA_POR_FALLAS (inasistencia >= 30%)
        final course5 = _buildCourse(
          id: 'course-5-sesiones',
          code: 'CALC-101',
          name: 'Cálculo Diferencial',
        );
        await database.insertCourse(course5);

        final stA = _buildStudent(
          id: 'st-a',
          courseId: course5.id,
          studentCode: '0182100001',
          fullName: 'ESTUDIANTE A NORMAL',
          bitIndex: 0,
          personalSecret:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        );
        final stB = _buildStudent(
          id: 'st-b',
          courseId: course5.id,
          studentCode: '0182100002',
          fullName: 'ESTUDIANTE B ALERTA',
          bitIndex: 1,
          personalSecret:
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        );
        final stC = _buildStudent(
          id: 'st-c',
          courseId: course5.id,
          studentCode: '0182100003',
          fullName: 'ESTUDIANTE C PERDIDA',
          bitIndex: 2,
          personalSecret:
              'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
        );

        for (final StudentModel s in <StudentModel>[stA, stB, stC]) {
          await database.insertStudent(s);
        }

        // Insertamos 5 sesiones cerradas con registros directos para velocidad
        for (var i = 1; i <= 5; i++) {
          final sessionId = 'session-calc-$i';
          final startedAt = '2026-11-0${i}T07:00:00.000Z';
          final closedAt = '2026-11-0${i}T09:00:00.000Z';
          final session = SessionModel(
            id: sessionId,
            courseId: course5.id,
            startedAt: startedAt,
            closedAt: closedAt,
            roomPin: (10 + i).toString(),
            bitmapHex: '0700000000000000',
          );
          await database.upsertSession(session);

          // Asistencias:
          // stA asiste a todas (5 de 5)
          await database.upsertAttendanceRecord(
            AttendanceRecordModel(
              id: 'rec-a-$i',
              sessionId: sessionId,
              studentId: stA.id,
              bitIndex: stA.bitIndex,
              method: AppConstants.attendanceMethodBleHmac,
              recordedAt: startedAt,
              timeTick: 1000 + i,
            ),
          );

          // stB asiste a las sesiones 1, 2, 3, 4 (4 de 5, falta en la 5 -> 20% inasistencia)
          if (i != 5) {
            await database.upsertAttendanceRecord(
              AttendanceRecordModel(
                id: 'rec-b-$i',
                sessionId: sessionId,
                studentId: stB.id,
                bitIndex: stB.bitIndex,
                method: AppConstants.attendanceMethodBleHmac,
                recordedAt: startedAt,
                timeTick: 1000 + i,
              ),
            );
          }

          // stC asiste a las sesiones 1, 2, 3 (3 de 5, falta en 4 y 5 -> 40% inasistencia)
          if (i <= 3) {
            await database.upsertAttendanceRecord(
              AttendanceRecordModel(
                id: 'rec-c-$i',
                sessionId: sessionId,
                studentId: stC.id,
                bitIndex: stC.bitIndex,
                method: AppConstants.attendanceMethodManualInverted,
                recordedAt: startedAt,
                timeTick: 1000 + i,
              ),
            );
          }

          // Acta firmada de la sesión
          final actaSignature = Hmac(
            sha256,
            utf8.encode(course5.courseSecret.toLowerCase()),
          ).convert(utf8.encode('acta-$sessionId')).toString();
          await database.closeSessionWithActa(
            sessionId: sessionId,
            closedAt: closedAt,
            bitmapHex: '0700000000000000',
            actaJson: jsonEncode(<String, Object?>{
              'sessionId': sessionId,
              'courseId': course5.id,
              'closedAtIso': closedAt,
              'presentBleCount': i <= 3 ? 2 : 1,
              'presentManualCount': i <= 3 ? 1 : 0,
              'absentCount': i == 5 ? 2 : (i == 4 ? 1 : 0),
              'actaHmacSignature': actaSignature,
            }),
            actaHmacSignature: actaSignature,
            actHash: sha256.convert(utf8.encode('hash-$sessionId')).toString(),
          );
        }

        final summary = await excelService.buildCourseSummary(course5.id);
        expect(summary.totalClosedSessions, 5);
        expect(summary.students.length, 3);

        final metricA = summary.students[0];
        expect(metricA.studentCode, '0182100001');
        expect(metricA.totalSessions, 5);
        expect(metricA.totalAttendances, 5);
        expect(metricA.totalAbsences, 0);
        expect(metricA.attendancePercentage, 100.0);
        expect(metricA.absencePercentage, 0.0);
        expect(metricA.alertStatus, AttendanceAlertStatus.normal);
        expect(metricA.isNormal, isTrue);

        final metricB = summary.students[1];
        expect(metricB.studentCode, '0182100002');
        expect(metricB.totalSessions, 5);
        expect(metricB.totalAttendances, 4);
        expect(metricB.totalAbsences, 1);
        expect(metricB.attendancePercentage, 80.0);
        expect(metricB.absencePercentage, 20.0);
        expect(metricB.alertStatus, AttendanceAlertStatus.attendanceAlert);
        expect(metricB.requiresAttention, isTrue);

        final metricC = summary.students[2];
        expect(metricC.studentCode, '0182100003');
        expect(metricC.totalSessions, 5);
        expect(metricC.totalAttendances, 3);
        expect(metricC.totalAbsences, 2);
        expect(metricC.attendancePercentage, 60.0);
        expect(metricC.absencePercentage, 40.0);
        expect(metricC.alertStatus, AttendanceAlertStatus.failureByAbsences);
        expect(metricC.failedByAbsences, isTrue);

        // Verificamos que se reflejen en la hoja Excel generada
        final workbookBytes = excelService.generateWorkbookFromSummary(summary);
        final excel = Excel.decodeBytes(workbookBytes);
        final sheet = excel.tables['Resumen']!;
        expect(_extractCellString(sheet.rows[1][10]), AttendanceAlertStatus.normal);
        expect(
          _extractCellString(sheet.rows[2][10]),
          AttendanceAlertStatus.attendanceAlert,
        );
        expect(
          _extractCellString(sheet.rows[3][10]),
          AttendanceAlertStatus.failureByAbsences,
        );
      },
    );

    test('exportFileNameFor limpia caracteres no válidos en nombres de archivo', () {
      final raro = CourseModel(
        id: 'x',
        code: 'SIST/401 ',
        name: 'Curso',
        groupCode: '  ',
        semester: '2026-2',
        courseSecret: 'secreto',
        createdAt: '2026-11-10T00:00:00Z',
      );
      expect(
        ExcelReportService.exportFileNameFor(raro),
        'Asistencia_Uniguajira_SIST_401_SIN_DATO.xlsx',
      );
      expect(
        ExcelReportService.exportFileNameFor(course),
        'Asistencia_Uniguajira_SIST-401_01.xlsx',
      );
    });

    test('exportWorkbookToFile guarda archivo físico en disco y valida su estructura', () async {
      final tempDir = Directory.systemTemp.createTempSync('uniguajira_excel_');
      try {
        final filePath = await excelService.exportWorkbookToFile(
          courseId: course.id,
          directoryPath: tempDir.path,
        );

        final file = File(filePath);
        expect(file.existsSync(), isTrue);
        expect(file.path.endsWith('Asistencia_Uniguajira_SIST-401_01.xlsx'), isTrue);

        final bytes = await file.readAsBytes();
        expect(bytes.length, greaterThan(0));

        final decodedExcel = Excel.decodeBytes(bytes);
        expect(decodedExcel.tables.keys.length, 4);
        expect(decodedExcel.tables.containsKey('Resumen'), isTrue);
        expect(decodedExcel.tables.containsKey('Detalle'), isTrue);
        expect(decodedExcel.tables.containsKey('Sesiones'), isTrue);
        expect(decodedExcel.tables.containsKey('Metadatos'), isTrue);
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });

    // =========================================================================
    // VALIDACIONES Y SINCRONIZACIÓN INSTITUCIONAL (CloudSyncService)
    // =========================================================================
    group('CloudSyncService — Validación de cuentas institucionales', () {
      test(
        'Acepta cuentas válidas con el dominio institucional exacto @uniguajira.edu.co',
        () {
          expect(
            cloudSyncService.isValidInstitutionalEmail('docente@uniguajira.edu.co'),
            isTrue,
          );
          expect(
            cloudSyncService.isValidInstitutionalEmail(
              'profesor.guajira@uniguajira.edu.co',
            ),
            isTrue,
          );
          expect(
            cloudSyncService.isValidInstitutionalEmail(
              'DOCENTE.INVESTIGADOR@UNIGUAJIRA.EDU.CO',
            ),
            isTrue,
          );
          expect(
            cloudSyncService.isValidInstitutionalEmail(
              'alvaro_garrido.123+prueba@uniguajira.edu.co',
            ),
            isTrue,
          );
        },
      );

      test(
        'Rechaza correos externos, dominios incorrectos o formatos mal estructurados',
        () {
          // Correos comerciales y dominios no institucionales
          expect(
            cloudSyncService.isValidInstitutionalEmail('usuario@gmail.com'),
            isFalse,
          );
          expect(
            cloudSyncService.isValidInstitutionalEmail('docente@uniguajira.com'),
            isFalse,
          );
          expect(
            cloudSyncService.isValidInstitutionalEmail('docente@hotmail.com'),
            isFalse,
          );
          expect(
            cloudSyncService.isValidInstitutionalEmail('docente@uniguajira.edu'),
            isFalse,
          );
          expect(
            cloudSyncService.isValidInstitutionalEmail('docente@uniguajira.org'),
            isFalse,
          );

          // Cadenas vacías o mal formateadas
          expect(cloudSyncService.isValidInstitutionalEmail(''), isFalse);
          expect(cloudSyncService.isValidInstitutionalEmail('   '), isFalse);
          expect(
            cloudSyncService.isValidInstitutionalEmail('docente'),
            isFalse,
          );
          expect(
            cloudSyncService.isValidInstitutionalEmail('@uniguajira.edu.co'),
            isFalse,
          );
          expect(
            cloudSyncService.isValidInstitutionalEmail('docente@'),
            isFalse,
          );
          expect(
            cloudSyncService.isValidInstitutionalEmail(
              'docente@uniguajira@uniguajira.edu.co',
            ),
            isFalse,
          );
          expect(
            cloudSyncService.isValidInstitutionalEmail(
              '.docente@uniguajira.edu.co',
            ),
            isFalse,
          );
          expect(
            cloudSyncService.isValidInstitutionalEmail(
              'docente.@uniguajira.edu.co',
            ),
            isFalse,
          );
          expect(
            cloudSyncService.isValidInstitutionalEmail(
              'doc..ente@uniguajira.edu.co',
            ),
            isFalse,
          );
          expect(
            cloudSyncService.isValidInstitutionalEmail(
              'docente esp@uniguajira.edu.co',
            ),
            isFalse,
          );
        },
      );
    });

    group('CloudSyncService — Construcción de Payload y Sincronización', () {
      test(
        'buildGoogleSheetsPayload construye el paquete con 4 hojas, bytes y huella criptográfica',
        () async {
          final CloudSyncPayload payload =
              await cloudSyncService.buildGoogleSheetsPayload(course.id);

          expect(payload.courseId, course.id);
          expect(payload.courseCode, 'SIST-401');
          expect(payload.courseName, 'Arquitectura de Software');
          expect(payload.reportHmacSha256, hasLength(64));
          expect(payload.generatedAtIso, isNotEmpty);
          expect(payload.workbookBytes, isNotNull);
          expect(payload.workbookBytes!.length, greaterThan(0));

          // Verificación de las 4 hojas reglamentarias
          expect(payload.sheetNames, <String>[
            'Resumen',
            'Detalle',
            'Sesiones',
            'Metadatos',
          ]);
          expect(payload.sheetsRowCount, greaterThan(payload.dataRowCount));
          expect(payload.dataRowCount, greaterThan(0));

          // Verificación de encabezados y filas
          final resumenHeaders = payload.headersFor('Resumen');
          expect(resumenHeaders, contains('CodigoEstudiantil'));
          expect(resumenHeaders, contains('EstadoAlerta'));

          final resumenRows = payload.rowsFor('Resumen');
          expect(resumenRows.length, 4); // 4 estudiantes matriculados

          // Serialización a JSON
          final jsonWithoutBytes = payload.toJson(includeWorkbookBytes: false);
          expect(jsonWithoutBytes.containsKey('workbookBase64'), isFalse);
          expect(jsonWithoutBytes['courseId'], course.id);
          expect(jsonWithoutBytes['sheets'], isA<Map<String, Object?>>());

          final jsonWithBytes = payload.toJson(includeWorkbookBytes: true);
          expect(jsonWithBytes.containsKey('workbookBase64'), isTrue);
          expect(jsonWithBytes['workbookBase64'], isNotEmpty);

          final jsonString = payload.toJsonString();
          expect(jsonString, contains('SIST-401'));
        },
      );

      test(
        'syncCourseToInstitutionalCloud rechaza correos no institucionales con ArgumentError',
        () async {
          await expectLater(
            cloudSyncService.syncCourseToInstitutionalCloud(
              courseId: course.id,
              institutionalEmail: 'docente@gmail.com',
            ),
            throwsArgumentError,
          );

          await expectLater(
            cloudSyncService.syncCourseToInstitutionalCloud(
              courseId: course.id,
              institutionalEmail: 'invalido@uniguajira.com',
            ),
            throwsArgumentError,
          );
        },
      );

      test(
        'syncCourseToInstitutionalCloud en modo offline (sin transportOverride) retorna OFFLINE_READY con paquete y libro',
        () async {
          final CloudSyncResult result =
              await cloudSyncService.syncCourseToInstitutionalCloud(
                courseId: course.id,
                institutionalEmail: 'docente.sistemas@uniguajira.edu.co',
              );

          expect(result.status, CloudSyncStatus.offlineReady);
          expect(result.isOfflineReady, isTrue);
          expect(result.isSuccess, isTrue);
          expect(result.isSynced, isFalse);
          expect(result.hasFailed, isFalse);
          expect(result.transportUsed, isFalse);
          expect(result.transportSucceeded, isFalse);
          expect(result.errorMessage, isNull);
          expect(
            result.institutionalEmail,
            'docente.sistemas@uniguajira.edu.co',
          );
          expect(result.reportSignatureHmac, hasLength(64));
          expect(result.xlsxBytes.length, greaterThan(0));
          expect(result.sheetsRowCount, greaterThan(0));
          expect(result.dataRowCount, greaterThan(0));
          expect(result.payload, isNotNull);

          // Serialización de CloudSyncResult a JSON
          final json = result.toJson();
          expect(json['status'], CloudSyncStatus.offlineReady);
          expect(json['institutionalEmail'], 'docente.sistemas@uniguajira.edu.co');
          expect(json['xlsxBase64'], isNotEmpty);
        },
      );

      test(
        'syncCourseToInstitutionalCloud con transportOverride simulado exitoso retorna SYNCED',
        () async {
          CloudSyncPayload? capturedPayload;
          final CloudSyncResult result =
              await cloudSyncService.syncCourseToInstitutionalCloud(
                courseId: course.id,
                institutionalEmail: 'docente.investigador@uniguajira.edu.co',
                transportOverride: (CloudSyncPayload payload) async {
                  capturedPayload = payload;
                  return true;
                },
              );

          expect(result.status, CloudSyncStatus.synced);
          expect(result.isSynced, isTrue);
          expect(result.isSuccess, isTrue);
          expect(result.isOfflineReady, isFalse);
          expect(result.hasFailed, isFalse);
          expect(result.transportUsed, isTrue);
          expect(result.transportSucceeded, isTrue);
          expect(result.errorMessage, isNull);
          expect(capturedPayload, isNotNull);
          expect(capturedPayload?.courseId, course.id);
          expect(capturedPayload?.workbookBytes, isNotNull);
        },
      );

      test(
        'syncCourseToInstitutionalCloud con transportOverride que retorna false reporta SYNC_FAILED',
        () async {
          final CloudSyncResult result =
              await cloudSyncService.syncCourseToInstitutionalCloud(
                courseId: course.id,
                institutionalEmail: 'docente.titular@uniguajira.edu.co',
                transportOverride: (CloudSyncPayload payload) async {
                  return false;
                },
              );

          expect(result.status, CloudSyncStatus.failed);
          expect(result.hasFailed, isTrue);
          expect(result.isSuccess, isFalse);
          expect(result.isSynced, isFalse);
          expect(result.transportUsed, isTrue);
          expect(result.transportSucceeded, isFalse);
          expect(
            result.errorMessage,
            'El transporte no confirmó la sincronización.',
          );
        },
      );

      test(
        'syncCourseToInstitutionalCloud captura excepciones de red en el transporte y reporta SYNC_FAILED',
        () async {
          final CloudSyncResult result =
              await cloudSyncService.syncCourseToInstitutionalCloud(
                courseId: course.id,
                institutionalEmail: 'docente.catedra@uniguajira.edu.co',
                transportOverride: (CloudSyncPayload payload) async {
                  throw const SocketException('Error de conexión con Google Sheets');
                },
              );

          expect(result.status, CloudSyncStatus.failed);
          expect(result.hasFailed, isTrue);
          expect(result.isSuccess, isFalse);
          expect(result.transportUsed, isTrue);
          expect(result.transportSucceeded, isFalse);
          expect(result.errorMessage, contains('Error de conexión'));
        },
      );
    });
  });
}
