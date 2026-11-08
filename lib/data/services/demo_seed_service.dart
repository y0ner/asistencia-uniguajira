import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/crypto/ble_packet_codec.dart';
import '../../core/models/attendance_record_model.dart';
import '../../core/models/course_model.dart';
import '../../core/models/session_model.dart';
import '../../core/models/student_model.dart';
import '../local/app_database.dart';
import 'attendance_session_controller.dart';
import 'roster_import_service.dart';
import 'student_enrollment_service.dart';

/// Resultado inmutable tras la ejecución del motor sembrador de sustentación.
class DemoSeedResult {
  const DemoSeedResult({
    required this.course,
    required this.studentsSeeded,
    required this.closedSessionsSeeded,
    required this.signedActasCount,
    required this.enrolledStudentCode,
    required this.enrolledBitIndex,
    required this.wasReset,
  });

  /// Curso oficial sembrado para la sustentación.
  final CourseModel course;

  /// Cantidad de estudiantes matriculados en la nómina (esperado: 12).
  final int studentsSeeded;

  /// Cantidad de sesiones cerradas históricas (esperado: 4).
  final int closedSessionsSeeded;

  /// Cantidad de actas criptográficas con firma HMAC-SHA256 (esperado: 4).
  final int signedActasCount;

  /// Código del estudiante enrolado en la billetera local (esperado: '0182120016').
  final String enrolledStudentCode;

  /// Posición en el Bitmap del estudiante enrolado (esperado: 0).
  final int enrolledBitIndex;

  /// `true` si el escenario existente fue eliminado y reconstruido desde cero.
  final bool wasReset;

  @override
  String toString() {
    return 'DemoSeedResult(courseId: ${course.id}, studentsSeeded: $studentsSeeded, '
        'closedSessionsSeeded: $closedSessionsSeeded, signedActasCount: $signedActasCount, '
        'enrolledStudentCode: $enrolledStudentCode, enrolledBitIndex: $enrolledBitIndex, '
        'wasReset: $wasReset)';
  }
}

/// Motor sembrador del escenario determinista oficial para la sustentación de grado en 1 clic.
///
/// Configura en SQLite el curso oficial de Proyectos de Ingeniería II,
/// la nómina de 12 estudiantes en sus posiciones fijas de Bitmap (0 a 11),
/// el auto-enrolamiento del estudiante expositor (Bit 00 - Yoner Isaza) en la billetera local,
/// y 4 sesiones históricas cerradas con actas criptográficas reales firmadas con HMAC-SHA256,
/// produciendo exactamente la distribución requerida de alertas académicas:
/// - 8 estudiantes con 100% de asistencia (Estado: NORMAL).
/// - 2 estudiantes con 75% de asistencia y 25% de inasistencia (Estado: ALERTA_INASISTENCIA).
/// - 2 estudiantes con 50% de asistencia y 50% de inasistencia (Estado: PERDIDA_POR_FALLAS).
class DemoSeedService {
  DemoSeedService({
    AppDatabase? database,
    StudentEnrollmentService? enrollmentService,
    RosterImportService? rosterService,
  })  : _database = database ?? AppDatabase.instance,
        _enrollmentService = enrollmentService ??
            StudentEnrollmentService(database ?? AppDatabase.instance),
        _rosterService = rosterService ??
            RosterImportService(database: database ?? AppDatabase.instance);

  final AppDatabase _database;
  final StudentEnrollmentService _enrollmentService;
  final RosterImportService _rosterService;
  final Uuid _uuid = const Uuid();

  /// Acceso a la base de datos inyectada.
  AppDatabase get database => _database;

  /// Acceso al servicio de enrolamiento inyectado.
  StudentEnrollmentService get enrollmentService => _enrollmentService;

  /// Acceso al servicio de importación inyectado.
  RosterImportService get rosterService => _rosterService;

  // ---------------------------------------------------------------------------
  // Constantes Públicas del Escenario Oficial de Sustentación
  // ---------------------------------------------------------------------------

  /// Código institucional de la asignatura oficial de sustentación.
  static const String demoCourseCode = 'ING-SIS-1002';

  /// Nombre de la asignatura oficial de sustentación.
  static const String demoCourseName = 'PROYECTOS DE INGENIERIA II';

  /// Código del grupo oficial de sustentación.
  static const String demoCourseGroup = 'A1';

  /// Semestre académico de la demostración.
  static const String demoSemester = '2026-2';

  /// Correo institucional docente de la demostración.
  static const String demoTeacherEmail = 'mromero@uniguajira.edu.co';

  /// Código del estudiante expositor principal (Bit 00).
  static const String primaryStudentCode = '0182120016';

  /// Código del estudiante expositor secundario (Bit 01).
  static const String secondaryStudentCode = '0182110072';

  /// Secreto criptográfico de 32 bytes (64 caracteres hexadecimales) para el curso demo.
  static const String demoCourseSecret =
      '4a7f9c2d8b1e5a0f3c6e9d2b8a1f4c7e5a0d3b6f9c2e8a1d4f7b0c3e6a9d2f5b';

  // ---------------------------------------------------------------------------
  // Nómina Oficial de 12 Estudiantes (Posiciones de Bit 0 a 11)
  // ---------------------------------------------------------------------------

  static const List<Map<String, String>> officialRoster = <Map<String, String>>[
    <String, String>{
      'code': '0182120016',
      'name': 'ISAZA VIDES YONER DE JESUS',
      'email': 'yisaza@uniguajira.edu.co',
    },
    <String, String>{
      'code': '0182110072',
      'name': 'GARRIDO MEDINA ALVARO LUIS',
      'email': 'agarrido@uniguajira.edu.co',
    },
    <String, String>{
      'code': '0182120021',
      'name': 'BARROS PUSHAINA CAMILA ANDREA',
      'email': 'cbarros@uniguajira.edu.co',
    },
    <String, String>{
      'code': '0182120022',
      'name': 'EPIAYU IPUANA CARLOS ALBERTO',
      'email': 'cepiayu@uniguajira.edu.co',
    },
    <String, String>{
      'code': '0182120023',
      'name': 'FREYLE COTES DANIELA PAOLA',
      'email': 'dfreyle@uniguajira.edu.co',
    },
    <String, String>{
      'code': '0182120024',
      'name': 'GOMEZ ZUNIGA JORGE ELIECER',
      'email': 'jgomez@uniguajira.edu.co',
    },
    <String, String>{
      'code': '0182120025',
      'name': 'REDONDO IGUARAN LUIS FERNANDO',
      'email': 'lredondo@uniguajira.edu.co',
    },
    <String, String>{
      'code': '0182120026',
      'name': 'SOLANO BRITO MARIA CAMILA',
      'email': 'msolano@uniguajira.edu.co',
    },
    <String, String>{
      'code': '0182120027',
      'name': 'URIETA PIMIENTA NELSON DAVID',
      'email': 'nurieta@uniguajira.edu.co',
    },
    <String, String>{
      'code': '0182120028',
      'name': 'VALDEBLANQUEZ DAZA VALENTINA',
      'email': 'vvaldeblanquez@uniguajira.edu.co',
    },
    <String, String>{
      'code': '0182120029',
      'name': 'ZUBIRIA MAESTRE ANDRES FELIPE',
      'email': 'azubiria@uniguajira.edu.co',
    },
    <String, String>{
      'code': '0182120030',
      'name': 'PINTO ARREGOCES LAURA VANESSA',
      'email': 'lpinto@uniguajira.edu.co',
    },
  ];

  // ---------------------------------------------------------------------------
  // Método Principal: Siembra Determinista de Sustentación en 1 Clic
  // ---------------------------------------------------------------------------

  /// Siembra el escenario completo para la sustentación de grado.
  ///
  /// Si [resetExisting] es `false` y el curso ya existe, retorna inmediatamente
  /// el estado actual sin duplicar registros y asegurando que la credencial del
  /// estudiante '0182120016' esté registrada en la billetera.
  /// Si [resetExisting] es `true`, elimina el curso existente (con borrado en cascada
  /// de estudiantes, sesiones, registros y actas) y limpia la credencial de enrolamiento
  /// antes de reconstruir el escenario desde cero.
  Future<DemoSeedResult> seedDefenseDemonstrationData({
    bool resetExisting = false,
  }) async {
    // -------------------------------------------------------------------------
    // Bloque A: Control de Idempotencia y Reinicio Limpio
    // -------------------------------------------------------------------------
    final existingCourses = await _database.getAllCourses();
    final matchingCourses = existingCourses
        .where(
          (CourseModel c) =>
              c.code == demoCourseCode && c.groupCode == demoCourseGroup,
        )
        .toList(growable: false);

    if (matchingCourses.isNotEmpty && !resetExisting) {
      final existingCourse = matchingCourses.first;
      final students = await _database.getStudentsByCourse(existingCourse.id);
      final sessions = await _database.getSessionsByCourse(existingCourse.id);
      final closedSessions = sessions
          .where((SessionModel s) => s.closedAt != null)
          .toList(growable: false);

      var signedActasCount = 0;
      for (final SessionModel session in closedSessions) {
        final sig = await _database.getSessionActaSignature(session.id);
        if (sig != null && sig.trim().isNotEmpty) {
          signedActasCount++;
        }
      }

      // Asegurar que la credencial del estudiante expositor esté presente en la billetera
      final existingEnrollment =
          await _database.getStudentEnrollmentByCourse(existingCourse.id);
      if (existingEnrollment == null ||
          existingEnrollment.studentCode != primaryStudentCode) {
        final primaryStudent = students
            .where((StudentModel s) => s.studentCode == primaryStudentCode)
            .firstOrNull;
        if (primaryStudent != null) {
          final qrPayload = _rosterService.generateEnrollmentQrPayload(
            course: existingCourse,
            student: primaryStudent,
          );
          await _enrollmentService.enrollFromQrPayload(qrPayload);
        }
      }

      return DemoSeedResult(
        course: existingCourse,
        studentsSeeded: students.length,
        closedSessionsSeeded: closedSessions.length,
        signedActasCount: signedActasCount,
        enrolledStudentCode: primaryStudentCode,
        enrolledBitIndex: 0,
        wasReset: false,
      );
    }

    if (resetExisting) {
      for (final CourseModel course in matchingCourses) {
        await _database.deleteCourse(course.id);
      }
      final enrollments = await _enrollmentService.getEnrolledCourses();
      for (final enrollment in enrollments) {
        final matchesMatchingCourse =
            matchingCourses.any((c) => c.id == enrollment.courseId);
        final matchesDemoCode = enrollment.courseCode == demoCourseCode &&
            enrollment.studentCode == primaryStudentCode;
        if (matchesMatchingCourse || matchesDemoCode) {
          await _enrollmentService.removeEnrollment(enrollment.id);
        }
      }
    }

    // -------------------------------------------------------------------------
    // Bloque B: Creación del Curso Oficial de Grado
    // -------------------------------------------------------------------------
    final now = DateTime.now().toUtc();
    final courseId = _uuid.v4();
    final course = CourseModel(
      id: courseId,
      code: demoCourseCode,
      name: demoCourseName,
      groupCode: demoCourseGroup,
      semester: demoSemester,
      courseSecret: demoCourseSecret,
      createdAt: now.subtract(const Duration(days: 15)).toIso8601String(),
    );
    await _database.insertCourse(course);

    // -------------------------------------------------------------------------
    // Bloque C: Siembra de la Nómina Oficial de 12 Estudiantes (Bits 0 a 11)
    // -------------------------------------------------------------------------
    final seededStudents = <StudentModel>[];
    for (var i = 0; i < officialRoster.length; i++) {
      final entry = officialRoster[i];
      final student = await _rosterService.addManualStudent(
        courseId: course.id,
        studentCode: entry['code']!,
        fullName: entry['name']!,
        email: entry['email'],
      );
      seededStudents.add(student);
    }

    // -------------------------------------------------------------------------
    // Bloque D: Auto-Enrolamiento en Billetera Estudiante para Bit 00
    // -------------------------------------------------------------------------
    final primaryStudent = seededStudents.firstWhere(
      (StudentModel s) => s.studentCode == primaryStudentCode,
    );
    final qrPayload = _rosterService.generateEnrollmentQrPayload(
      course: course,
      student: primaryStudent,
    );
    await _enrollmentService.enrollFromQrPayload(qrPayload);

    // -------------------------------------------------------------------------
    // Bloque E: Siembra de 4 Sesiones Históricas Cerradas con Actas HMAC-SHA256
    // -------------------------------------------------------------------------
    final sessionSpecs = _buildSessionSpecs();
    var signedActasCreated = 0;

    for (var sIdx = 0; sIdx < sessionSpecs.length; sIdx++) {
      final spec = sessionSpecs[sIdx];
      final sessionId = _uuid.v4();
      final startedAt = now.subtract(Duration(days: spec.daysAgo, hours: 2));
      final closedAt = now.subtract(Duration(days: spec.daysAgo));
      final startedAtIso = startedAt.toIso8601String();
      final closedAtIso = closedAt.toIso8601String();

      final session = SessionModel(
        id: sessionId,
        courseId: course.id,
        startedAt: startedAtIso,
        roomPin: spec.roomPin,
        closedAt: null,
        bitmapHex: AppConstants.emptyBitmapHex,
        syncedToCloud: 0,
      );
      await _database.insertSession(session);

      var bitmap = BlePacketCodec.createEmptyBitmap8();
      var presentBleCount = 0;
      var presentManualCount = 0;
      var absentCount = 0;
      final actaRecords = <SessionActaRecord>[];

      for (final StudentModel student in seededStudents) {
        final status = spec.attendances[student.bitIndex];
        if (status == null || status.type == _AttendanceType.absent) {
          absentCount++;
          actaRecords.add(
            SessionActaRecord(
              bitIndex: student.bitIndex,
              studentCode: student.studentCode,
              fullName: student.fullName,
              status: AppConstants.attendanceStatusAbsent,
              method: null,
              verifyCode: null,
              rssi: null,
            ),
          );
        } else if (status.type == _AttendanceType.ble) {
          bitmap = BlePacketCodec.setStudentBit(bitmap, student.bitIndex);
          presentBleCount++;

          final recordedAt = startedAt.add(
            Duration(minutes: 5 + (student.bitIndex * 2)),
          );
          final recordedAtIso = recordedAt.toIso8601String();
          final timeTick = BlePacketCodec.computeTimeTick(recordedAt);
          final verifyCode = BlePacketCodec.generateAttendanceVerifyCode(
            courseId: course.id,
            studentCode: student.studentCode,
            bitIndex: student.bitIndex,
            timeTick: timeTick,
            secretHex: student.personalSecret,
          );

          final record = AttendanceRecordModel(
            id: '${sessionId}_${student.id}',
            sessionId: sessionId,
            studentId: student.id,
            bitIndex: student.bitIndex,
            method: AppConstants.attendanceMethodBleHmac,
            rssiAvg: status.rssi!.toDouble(),
            recordedAt: recordedAtIso,
            hmacTag: verifyCode,
            timeTick: timeTick,
          );
          await _database.insertAttendanceRecord(record);

          actaRecords.add(
            SessionActaRecord(
              bitIndex: student.bitIndex,
              studentCode: student.studentCode,
              fullName: student.fullName,
              status: AppConstants.attendanceStatusPresent,
              method: AppConstants.attendanceMethodBleHmac,
              verifyCode: verifyCode,
              rssi: status.rssi,
            ),
          );
        } else if (status.type == _AttendanceType.manual) {
          bitmap = BlePacketCodec.setStudentBit(bitmap, student.bitIndex);
          presentManualCount++;

          final recordedAt = startedAt.add(
            Duration(minutes: 20 + student.bitIndex),
          );
          final recordedAtIso = recordedAt.toIso8601String();
          final timeTick = BlePacketCodec.computeTimeTick(recordedAt);

          final record = AttendanceRecordModel(
            id: '${sessionId}_${student.id}',
            sessionId: sessionId,
            studentId: student.id,
            bitIndex: student.bitIndex,
            method: AppConstants.attendanceMethodManualInverted,
            recordedAt: recordedAtIso,
            timeTick: timeTick,
            observation: 'Registro manual validado en aula',
          );
          await _database.insertAttendanceRecord(record);

          actaRecords.add(
            SessionActaRecord(
              bitIndex: student.bitIndex,
              studentCode: student.studentCode,
              fullName: student.fullName,
              status: AppConstants.attendanceStatusPresent,
              method: AppConstants.attendanceMethodManualInverted,
              verifyCode: null,
              rssi: null,
            ),
          );
        }
      }

      // Verificación de invariante contable estricto
      if (presentBleCount + presentManualCount + absentCount !=
          seededStudents.length) {
        throw StateError(
          'Invariante contable roto en la sesión ${sIdx + 1}: '
          'BLE($presentBleCount) + Manual($presentManualCount) + '
          'Ausentes($absentCount) != Total(${seededStudents.length})',
        );
      }

      final bitmapHex = _bitmapToHex(bitmap);

      final unsignedActa = SignedSessionActa(
        sessionId: sessionId,
        courseId: course.id,
        courseCode: course.code,
        courseName: course.name,
        sessionPin: spec.roomPin,
        startedAtIso: startedAtIso,
        closedAtIso: closedAtIso,
        totalEnrolled: seededStudents.length,
        presentBleCount: presentBleCount,
        presentManualCount: presentManualCount,
        absentCount: absentCount,
        bitmapHex: bitmapHex,
        records: actaRecords,
        actaHmacSignature: '',
      );

      final signature = signActaPayload(
        unsignedActa.canonicalJson,
        course.courseSecret,
      );

      final signedActa = unsignedActa.copyWith(actaHmacSignature: signature);
      final actHash = sha256
          .convert(utf8.encode(signedActa.canonicalJson))
          .toString();

      final actaJson = generateSessionActaJson(
        acta: signedActa,
        status: 'CLOSED',
      );

      await _database.closeSessionWithActa(
        sessionId: sessionId,
        closedAt: closedAtIso,
        bitmapHex: bitmapHex,
        actaJson: actaJson,
        actaHmacSignature: signature,
        actHash: actHash,
      );

      signedActasCreated++;
    }

    return DemoSeedResult(
      course: course,
      studentsSeeded: seededStudents.length,
      closedSessionsSeeded: sessionSpecs.length,
      signedActasCount: signedActasCreated,
      enrolledStudentCode: primaryStudentCode,
      enrolledBitIndex: 0,
      wasReset: resetExisting,
    );
  }

  // ---------------------------------------------------------------------------
  // Utilidades de Firma y Serialización de Actas
  // ---------------------------------------------------------------------------

  /// Firma un JSON canónico de acta utilizando HMAC-SHA256 con el secreto del curso.
  static String signActaPayload(String canonicalJson, String secretHex) {
    return Hmac(
      sha256,
      utf8.encode(secretHex.toLowerCase()),
    ).convert(utf8.encode(canonicalJson)).toString();
  }

  /// Serializa el acta firmada a un String JSON incluyendo el estado de cierre.
  static String generateSessionActaJson({
    required SignedSessionActa acta,
    String? status = 'CLOSED',
  }) {
    final map = <String, Object?>{
      ...acta.toJson(),
    };
    if (status != null) {
      map['status'] = status;
    }
    return jsonEncode(map);
  }

  // ---------------------------------------------------------------------------
  // Especificación Determinista de las 4 Sesiones
  // ---------------------------------------------------------------------------

  static List<_SessionSeedSpec> _buildSessionSpecs() {
    return const <_SessionSeedSpec>[
      // Sesión 1: Hace 10 días, PIN 21
      _SessionSeedSpec(
        daysAgo: 10,
        roomPin: '21',
        attendances: <int, _StudentSessionStatus>{
          0: _StudentSessionStatus.ble(-55),
          1: _StudentSessionStatus.manual(),
          2: _StudentSessionStatus.ble(-56),
          3: _StudentSessionStatus.manual(),
          4: _StudentSessionStatus.ble(-64),
          5: _StudentSessionStatus.ble(-59),
          6: _StudentSessionStatus.ble(-67),
          7: _StudentSessionStatus.manual(),
          8: _StudentSessionStatus.ble(-58),
          9: _StudentSessionStatus.ble(-62),
          10: _StudentSessionStatus.ble(-61),
          11: _StudentSessionStatus.ble(-64),
        },
      ),
      // Sesión 2: Hace 7 días, PIN 34
      _SessionSeedSpec(
        daysAgo: 7,
        roomPin: '34',
        attendances: <int, _StudentSessionStatus>{
          0: _StudentSessionStatus.ble(-58),
          1: _StudentSessionStatus.manual(),
          2: _StudentSessionStatus.ble(-63),
          3: _StudentSessionStatus.ble(-57),
          4: _StudentSessionStatus.manual(),
          5: _StudentSessionStatus.ble(-68),
          6: _StudentSessionStatus.ble(-58),
          7: _StudentSessionStatus.ble(-61),
          8: _StudentSessionStatus.ble(-60),
          9: _StudentSessionStatus.ble(-65),
          10: _StudentSessionStatus.ble(-59),
          11: _StudentSessionStatus.ble(-66),
        },
      ),
      // Sesión 3: Hace 4 días, PIN 56
      _SessionSeedSpec(
        daysAgo: 4,
        roomPin: '56',
        attendances: <int, _StudentSessionStatus>{
          0: _StudentSessionStatus.ble(-54),
          1: _StudentSessionStatus.ble(-62),
          2: _StudentSessionStatus.manual(),
          3: _StudentSessionStatus.ble(-65),
          4: _StudentSessionStatus.ble(-60),
          5: _StudentSessionStatus.ble(-57),
          6: _StudentSessionStatus.manual(),
          7: _StudentSessionStatus.ble(-70),
          8: _StudentSessionStatus.ble(-63),
          9: _StudentSessionStatus.ble(-59),
          10: _StudentSessionStatus.absent(),
          11: _StudentSessionStatus.absent(),
        },
      ),
      // Sesión 4: Hace 1 día, PIN 78
      _SessionSeedSpec(
        daysAgo: 1,
        roomPin: '78',
        attendances: <int, _StudentSessionStatus>{
          0: _StudentSessionStatus.ble(-60),
          1: _StudentSessionStatus.ble(-59),
          2: _StudentSessionStatus.ble(-58),
          3: _StudentSessionStatus.ble(-61),
          4: _StudentSessionStatus.ble(-66),
          5: _StudentSessionStatus.manual(),
          6: _StudentSessionStatus.ble(-62),
          7: _StudentSessionStatus.ble(-65),
          8: _StudentSessionStatus.absent(),
          9: _StudentSessionStatus.absent(),
          10: _StudentSessionStatus.absent(),
          11: _StudentSessionStatus.absent(),
        },
      ),
    ];
  }
}

class _SessionSeedSpec {
  const _SessionSeedSpec({
    required this.daysAgo,
    required this.roomPin,
    required this.attendances,
  });

  final int daysAgo;
  final String roomPin;
  final Map<int, _StudentSessionStatus> attendances;
}

enum _AttendanceType { ble, manual, absent }

class _StudentSessionStatus {
  const _StudentSessionStatus.ble(this.rssi) : type = _AttendanceType.ble;
  const _StudentSessionStatus.manual()
      : type = _AttendanceType.manual,
        rssi = null;
  const _StudentSessionStatus.absent()
      : type = _AttendanceType.absent,
        rssi = null;

  final _AttendanceType type;
  final int? rssi;
}

String _bitmapToHex(List<int> bitmap8) {
  return bitmap8
      .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}
