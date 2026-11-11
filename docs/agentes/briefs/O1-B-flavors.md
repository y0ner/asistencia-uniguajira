# Brief O1-B · Dos apps desde un mismo código (Docente y Estudiante)

- **Rama:** `feat/flavors` · **Worktree:** `../worktrees/feat-flavors`
- **Lee primero:** `AGENTS.md` (reglas obligatorias).
- **Objetivo:** generar dos APK instalables a la vez en el mismo celular: **"Asistencia Docente"** y **"Asistencia Estudiante"**. Cada una abre directo en su rol y solo incluye sus pantallas.

## Contexto

Hoy `lib/main.dart` (1295 líneas) abre `RoleSelectorScreen`: un selector de rol, un panel de demostración para la sustentación (`_DefenseDemoCard`, que usa `DemoSeedService`) y un diálogo de diagnóstico de hardware (`_AndroidHardwareDiagnosticDialog` / `_DesktopHardwareDiagnosticDialog`). Las entradas reales son `CoursesDashboardScreen` (docente) y `StudentCoursesScreen` (estudiante).

## Archivos permitidos

- `android/app/build.gradle.kts`
- `android/app/src/main/AndroidManifest.xml` (solo `android:label`)
- `android/app/src/docente/**` y `android/app/src/estudiante/**` (**nuevos**: `res/values/strings.xml` con el nombre de la app)
- `lib/main.dart`, `lib/main_docente.dart` (**nuevo**), `lib/main_estudiante.dart` (**nuevo**)
- `lib/app/app_flavor.dart` y `lib/app/asistencia_app.dart` (**nuevos**)
- `lib/features/shared/hardware_diagnostic_dialog.dart` (**nuevo**: el diálogo de diagnóstico, movido desde `main.dart`)
- `lib/features/teacher/courses_dashboard_screen.dart` y `lib/features/student/student_courses_screen.dart` (**solo** para agregar en la barra superior un ícono que abra el diagnóstico)
- `run.sh`
- `test/app_flavor_test.dart` (**nuevo**)

## Qué hacer

1. **Gradle:** en `build.gradle.kts`, `flavorDimensions += "rol"` y `productFlavors`:
   - `docente`: `applicationIdSuffix = ".docente"`, `resValue("string", "app_name", "Asistencia Docente")`.
   - `estudiante`: `applicationIdSuffix = ".estudiante"`, `resValue("string", "app_name", "Asistencia Estudiante")`.

   En el manifiesto: `android:label="@string/app_name"`. (Si usas `resValue`, no hacen falta los `strings.xml` por *flavor*; usa una sola de las dos opciones.)
2. **Punto de entrada por rol:**
   - `lib/app/app_flavor.dart`: `enum AppFlavor { docente, estudiante }` con `title` y la pantalla de inicio.
   - `lib/app/asistencia_app.dart`: el `MaterialApp` (tema, títulos) que recibe el `AppFlavor`.
   - `lib/main_docente.dart` → `runApp(AsistenciaApp(flavor: AppFlavor.docente))`, cuya pantalla de inicio es `CoursesDashboardScreen`.
   - `lib/main_estudiante.dart` → igual, con `StudentCoursesScreen`.
   - `lib/main.dart` queda como entrada de desarrollo y **delega en `main_docente.dart`** (sin selector de rol).
3. **Quitar de producción:** `RoleSelectorScreen`, `_RoleOptionCard`, `_DefenseDemoCard`, `_DefenseDemoResultDialog` y el resto de la UI de demostración de `main.dart`. **No borres** `DemoSeedService` ni `test/defense_demo_e2e_test.dart`: siguen sirviendo para las pruebas.
4. **Diagnóstico:** mueve el diálogo de diagnóstico de hardware a `lib/features/shared/hardware_diagnostic_dialog.dart` y ábrelo desde un ícono (`Icons.bluetooth_searching`) en la barra superior de ambas pantallas de inicio. Quita de su lista `Permission.locationWhenInUse` en Android 12 o superior (la app no usa GPS; solo se pide en Android 11 o inferior).
5. **`run.sh`:** agrega `./run.sh docente`, `./run.sh estudiante`, `./run.sh apk-docente` y `./run.sh apk-estudiante`, con `--flavor <x> -t lib/main_<x>.dart`.

## Criterios de aceptación

- [ ] `flutter build apk --debug --flavor docente -t lib/main_docente.dart` y la del estudiante generan dos APK con `applicationId` distintos. (El agente jefe lo ejecuta; tú deja el comando en el PR.)
- [ ] `grep -rn "RoleSelectorScreen\|_DefenseDemoCard" lib` no devuelve nada.
- [ ] `test/app_flavor_test.dart` verifica que cada *flavor* abre su pantalla de inicio (`pumpWidget` + `find.byType`).
- [ ] `flutter analyze --no-pub` sin problemas.

## Qué se probará en los 2 celulares (lo hace el humano)

Instalar ambas APK en el mismo celular: deben aparecer dos íconos con nombres distintos, y cada una abre directo en su rol.
