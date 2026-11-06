import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../core/constants/app_constants.dart';
import '../../core/models/attendance_record_model.dart';
import '../../core/models/course_model.dart';
import '../../core/models/session_model.dart';
import '../../core/models/student_enrollment_model.dart';
import '../../core/models/student_model.dart';

/// Acceso local SQLite (Offline-First) del proyecto.
///
/// La instancia [instance] usa el driver nativo de `sqflite` y el directorio de
/// bases de datos de la plataforma. Las pruebas inyectan `databaseFactoryFfi`
/// junto con `inMemoryDatabasePath` para ejecutarse en Linux sin dispositivo.
class AppDatabase {
  AppDatabase({DatabaseFactory? factory, String? databasePath})
    : this._(factory, databasePath);

  AppDatabase._(this._factory, this._databasePath);

  /// Instancia compartida por la aplicación.
  static final AppDatabase instance = AppDatabase();

  static const String _coursesTable = 'courses';
  static const String _studentsTable = 'students';
  static const String _sessionsTable = 'sessions';
  static const String _attendanceRecordsTable = 'attendance_records';
  static const String _studentEnrollmentsTable = 'student_enrollments';

  final DatabaseFactory? _factory;
  final String? _databasePath;

  Database? _database;
  Future<Database>? _opening;

  /// Base de datos abierta de forma perezosa y compartida dentro de la instancia.
  Future<Database> get database {
    final existing = _database;
    if (existing != null) {
      return Future<Database>.value(existing);
    }
    return _opening ??= _open().then((Database db) {
      _database = db;
      return db;
    });
  }

  Future<Database> _open() async {
    final factory = _factory ?? databaseFactory;
    final path =
        _databasePath ??
        p.join(await factory.getDatabasesPath(), AppConstants.databaseName);
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: AppConstants.databaseVersion,
        onConfigure: _configure,
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
      ),
    );
  }

  static Future<void> _configure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  static Future<void> _createSchema(Database db, int version) async {
    final batch = db.batch();
    batch.execute(_createCoursesTable);
    batch.execute(_createStudentsTable);
    batch.execute(_createSessionsTable);
    batch.execute(_createAttendanceRecordsTable);
    batch.execute(_createStudentEnrollmentsTable);
    batch.execute(_createStudentsCourseIndex);
    batch.execute(_createAttendanceSessionIndex);
    await batch.commit(noResult: true);
  }

  static Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute(_createStudentEnrollmentsTable);
    }
  }

  // ---------------------------------------------------------------------------
  // Cursos
  // ---------------------------------------------------------------------------

  /// Inserta un curso nuevo.
  Future<void> insertCourse(CourseModel course) async {
    final db = await database;
    await db.insert(_coursesTable, course.toMap());
  }

  /// Recupera un curso por su identificador o `null` si no existe.
  Future<CourseModel?> getCourseById(String courseId) async {
    final db = await database;
    final rows = await db.query(
      _coursesTable,
      where: 'id = ?',
      whereArgs: <Object?>[courseId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return CourseModel.fromMap(rows.first);
  }

  /// Lista todos los cursos, del más reciente al más antiguo.
  Future<List<CourseModel>> getAllCourses() async {
    final db = await database;
    final rows = await db.query(_coursesTable, orderBy: 'created_at DESC');
    return rows.map(CourseModel.fromMap).toList(growable: false);
  }

  /// Lista todos los cursos para las capas de selección e importación.
  ///
  /// Se expone con el nombre corto solicitado por el motor de roster; delega
  /// en [getAllCourses] para conservar un único orden y contrato.
  Future<List<CourseModel>> getCourses() => getAllCourses();

  /// Elimina un curso y, por las claves foráneas en cascada, su roster,
  /// sus sesiones y los registros de asistencia asociados.
  Future<void> deleteCourse(String courseId) async {
    final db = await database;
    await db.delete(
      _coursesTable,
      where: 'id = ?',
      whereArgs: <Object?>[courseId],
    );
  }

  // ---------------------------------------------------------------------------
  // Estudiantes
  // ---------------------------------------------------------------------------

  /// Inserta un estudiante validando el rango y la capacidad del Bitmap.
  ///
  /// Las posiciones duplicadas y los códigos repetidos dentro del mismo curso
  /// los rechazan las restricciones `UNIQUE` del esquema SQLite.
  Future<void> insertStudent(StudentModel student) async {
    _validateBitIndex(student.bitIndex);
    final db = await database;
    await db.transaction((Transaction txn) async {
      final rows = await txn.rawQuery(
        'SELECT COUNT(*) AS total FROM $_studentsTable WHERE course_id = ?',
        <Object?>[student.courseId],
      );
      final total = Sqflite.firstIntValue(rows) ?? 0;
      if (total >= AppConstants.bitmapBitCount) {
        throw StateError(
          'El curso ${student.courseId} ya ocupó las '
          '${AppConstants.bitmapBitCount} posiciones del Bitmap.',
        );
      }
      await txn.insert(_studentsTable, student.toMap());
    });
  }

  /// Lista los estudiantes de un curso ordenados por su posición en el Bitmap.
  Future<List<StudentModel>> getStudentsByCourse(String courseId) async {
    final db = await database;
    final rows = await db.query(
      _studentsTable,
      where: 'course_id = ?',
      whereArgs: <Object?>[courseId],
      orderBy: 'bit_index ASC',
    );
    return rows.map(StudentModel.fromMap).toList(growable: false);
  }

  /// Busca un estudiante por su código dentro de un curso.
  Future<StudentModel?> getStudentByCode({
    required String courseId,
    required String studentCode,
  }) async {
    final db = await database;
    final rows = await db.query(
      _studentsTable,
      where: 'course_id = ? AND student_code = ?',
      whereArgs: <Object?>[courseId, studentCode],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return StudentModel.fromMap(rows.first);
  }

  // ---------------------------------------------------------------------------
  // Credenciales de enrolamiento del estudiante
  // ---------------------------------------------------------------------------

  /// Guarda o reemplaza la credencial del estudiante para su curso.
  ///
  /// La tabla no depende de `courses` porque el teléfono del estudiante
  /// conserva la credencial aunque no tenga el curso completo en su base local.
  Future<void> upsertStudentEnrollment(
    StudentEnrollmentModel enrollment,
  ) async {
    _validateBitIndex(enrollment.bitIndex);
    final db = await database;
    await db.insert(
      _studentEnrollmentsTable,
      enrollment.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Lista las credenciales guardadas, de la más reciente a la más antigua.
  Future<List<StudentEnrollmentModel>> getStudentEnrollments() async {
    final db = await database;
    final rows = await db.query(
      _studentEnrollmentsTable,
      orderBy: 'enrolled_at_epoch_ms DESC, student_code ASC',
    );
    return rows.map(StudentEnrollmentModel.fromMap).toList(growable: false);
  }

  /// Recupera la credencial de un curso o `null` si aún no hay enrolamiento.
  Future<StudentEnrollmentModel?> getStudentEnrollmentByCourse(
    String courseId,
  ) async {
    final db = await database;
    final rows = await db.query(
      _studentEnrollmentsTable,
      where: 'course_id = ?',
      whereArgs: <Object?>[courseId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return StudentEnrollmentModel.fromMap(rows.first);
  }

  /// Elimina una credencial por su identificador local.
  Future<void> deleteStudentEnrollment(String id) async {
    final db = await database;
    await db.delete(
      _studentEnrollmentsTable,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  // ---------------------------------------------------------------------------
  // Sesiones
  // ---------------------------------------------------------------------------

  /// Crea una sesión de clase con su PIN verbal de dos dígitos.
  Future<void> insertSession(SessionModel session) async {
    _validateRoomPin(session.roomPin);
    _validateBitmapHex(session.bitmapHex);
    final db = await database;
    await db.insert(_sessionsTable, session.toMap());
  }

  /// Recupera una sesión por su identificador o `null` si no existe.
  Future<SessionModel?> getSessionById(String sessionId) async {
    final db = await database;
    final rows = await db.query(
      _sessionsTable,
      where: 'id = ?',
      whereArgs: <Object?>[sessionId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return SessionModel.fromMap(rows.first);
  }

  /// Lista las sesiones de un curso, de la más reciente a la más antigua.
  Future<List<SessionModel>> getSessionsByCourse(String courseId) async {
    final db = await database;
    final rows = await db.query(
      _sessionsTable,
      where: 'course_id = ?',
      whereArgs: <Object?>[courseId],
      orderBy: 'started_at DESC',
    );
    return rows.map(SessionModel.fromMap).toList(growable: false);
  }

  /// Actualiza el mapa de bits de 8 bytes que emite el docente.
  Future<void> updateSessionBitmap({
    required String sessionId,
    required String bitmapHex,
  }) async {
    _validateBitmapHex(bitmapHex);
    final db = await database;
    final updated = await db.update(
      _sessionsTable,
      <String, Object?>{'bitmap_hex': bitmapHex},
      where: 'id = ?',
      whereArgs: <Object?>[sessionId],
    );
    if (updated == 0) {
      throw StateError('La sesión $sessionId no existe.');
    }
  }

  /// Cierra la sesión guardando su fecha de cierre y el hash del acta.
  Future<void> closeSession({
    required String sessionId,
    required String closedAt,
    String? actHash,
  }) async {
    final values = <String, Object?>{'closed_at': closedAt};
    if (actHash != null) {
      values['act_hash'] = actHash;
    }
    final db = await database;
    final updated = await db.update(
      _sessionsTable,
      values,
      where: 'id = ?',
      whereArgs: <Object?>[sessionId],
    );
    if (updated == 0) {
      throw StateError('La sesión $sessionId no existe.');
    }
  }

  // ---------------------------------------------------------------------------
  // Registros de asistencia
  // ---------------------------------------------------------------------------

  /// Inserta un registro de asistencia para una sesión y un estudiante.
  Future<void> insertAttendanceRecord(AttendanceRecordModel record) async {
    _validateBitIndex(record.bitIndex);
    _validateAttendanceMethod(record.method);
    final db = await database;
    await db.insert(_attendanceRecordsTable, record.toMap());
  }

  /// Lista los registros de asistencia de una sesión en orden cronológico.
  Future<List<AttendanceRecordModel>> getAttendanceRecordsBySession(
    String sessionId,
  ) async {
    final db = await database;
    final rows = await db.query(
      _attendanceRecordsTable,
      where: 'session_id = ?',
      whereArgs: <Object?>[sessionId],
      orderBy: 'recorded_at ASC',
    );
    return rows.map(AttendanceRecordModel.fromMap).toList(growable: false);
  }

  /// Cierra la conexión y libera la instancia para una nueva apertura.
  Future<void> close() async {
    final db = _database;
    _database = null;
    _opening = null;
    await db?.close();
  }

  // ---------------------------------------------------------------------------
  // Validaciones compartidas
  // ---------------------------------------------------------------------------

  static void _validateBitIndex(int bitIndex) {
    if (bitIndex < 0 || bitIndex > AppConstants.maxBitIndex) {
      throw ArgumentError.value(
        bitIndex,
        'bitIndex',
        'Debe estar entre 0 y ${AppConstants.maxBitIndex}.',
      );
    }
  }

  static void _validateRoomPin(String roomPin) {
    if (!RegExp(r'^\d{2}$').hasMatch(roomPin)) {
      throw ArgumentError.value(
        roomPin,
        'roomPin',
        'El PIN debe tener exactamente ${AppConstants.roomPinLength} dígitos.',
      );
    }
  }

  static void _validateBitmapHex(String bitmapHex) {
    final pattern = RegExp('^[0-9a-fA-F]{${AppConstants.bitmapHexLength}}\$');
    if (!pattern.hasMatch(bitmapHex)) {
      throw ArgumentError.value(
        bitmapHex,
        'bitmapHex',
        'El Bitmap debe ser hexadecimal de '
            '${AppConstants.bitmapHexLength} caracteres '
            '(${AppConstants.bitmapByteLength} bytes).',
      );
    }
  }

  static void _validateAttendanceMethod(String method) {
    if (method != AppConstants.attendanceMethodBleHmac &&
        method != AppConstants.attendanceMethodManualInverted) {
      throw ArgumentError.value(
        method,
        'method',
        'Método de registro no soportado.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Esquema SQLite
  // ---------------------------------------------------------------------------

  static const String _createCoursesTable =
      '''
    CREATE TABLE $_coursesTable (
      id TEXT PRIMARY KEY,
      code TEXT NOT NULL,
      name TEXT NOT NULL,
      group_code TEXT NOT NULL,
      semester TEXT NOT NULL,
      course_secret TEXT NOT NULL,
      spreadsheet_id TEXT,
      created_at TEXT NOT NULL
    )
  ''';

  static const String _createStudentsTable =
      '''
    CREATE TABLE $_studentsTable (
      id TEXT PRIMARY KEY,
      course_id TEXT NOT NULL,
      student_code TEXT NOT NULL,
      full_name TEXT NOT NULL,
      email TEXT,
      bit_index INTEGER NOT NULL
        CHECK (bit_index >= 0 AND bit_index < ${AppConstants.bitmapBitCount}),
      personal_secret TEXT NOT NULL,
      enrolled_at TEXT,
      UNIQUE (course_id, bit_index),
      UNIQUE (course_id, student_code),
      FOREIGN KEY (course_id) REFERENCES $_coursesTable (id) ON DELETE CASCADE
    )
  ''';

  static const String _createSessionsTable =
      '''
    CREATE TABLE $_sessionsTable (
      id TEXT PRIMARY KEY,
      course_id TEXT NOT NULL,
      started_at TEXT NOT NULL,
      closed_at TEXT,
      room_pin TEXT NOT NULL CHECK (length(room_pin) = ${AppConstants.roomPinLength}),
      bitmap_hex TEXT NOT NULL CHECK (length(bitmap_hex) = ${AppConstants.bitmapHexLength}),
      act_hash TEXT,
      synced_to_cloud INTEGER NOT NULL DEFAULT 0
        CHECK (synced_to_cloud IN (0, 1)),
      FOREIGN KEY (course_id) REFERENCES $_coursesTable (id) ON DELETE CASCADE
    )
  ''';

  static const String _createAttendanceRecordsTable =
      '''
    CREATE TABLE $_attendanceRecordsTable (
      id TEXT PRIMARY KEY,
      session_id TEXT NOT NULL,
      student_id TEXT NOT NULL,
      bit_index INTEGER NOT NULL
        CHECK (bit_index >= 0 AND bit_index < ${AppConstants.bitmapBitCount}),
      method TEXT NOT NULL
        CHECK (method IN ('${AppConstants.attendanceMethodBleHmac}',
                          '${AppConstants.attendanceMethodManualInverted}')),
      rssi_avg REAL,
      recorded_at TEXT NOT NULL,
      hmac_tag TEXT,
      UNIQUE (session_id, student_id),
      FOREIGN KEY (session_id) REFERENCES $_sessionsTable (id) ON DELETE CASCADE,
      FOREIGN KEY (student_id) REFERENCES $_studentsTable (id) ON DELETE CASCADE
    )
  ''';

  static const String _createStudentEnrollmentsTable =
      '''
    CREATE TABLE IF NOT EXISTS $_studentEnrollmentsTable (
      id TEXT PRIMARY KEY,
      course_id TEXT NOT NULL UNIQUE,
      course_code TEXT NOT NULL,
      course_name TEXT NOT NULL,
      student_id TEXT NOT NULL,
      student_code TEXT NOT NULL,
      full_name TEXT NOT NULL,
      bit_index INTEGER NOT NULL
        CHECK (bit_index >= 0 AND bit_index < ${AppConstants.bitmapBitCount}),
      device_secret TEXT NOT NULL,
      shared_secret TEXT NOT NULL,
      enrolled_at_epoch_ms INTEGER NOT NULL
    )
  ''';

  static const String _createStudentsCourseIndex =
      '''
    CREATE INDEX idx_students_course_id ON $_studentsTable (course_id)
  ''';

  static const String _createAttendanceSessionIndex =
      '''
    CREATE INDEX idx_attendance_records_session_id
      ON $_attendanceRecordsTable (session_id)
  ''';
}
