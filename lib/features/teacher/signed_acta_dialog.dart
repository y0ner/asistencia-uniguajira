import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_constants.dart';
import '../../data/services/attendance_session_controller.dart';

/// Diálogo modal con el Acta Criptográfica de Sesión Firmada (HMAC-SHA256).
///
/// Permite visualizar el resumen oficial, el mapa de bits consolidado,
/// la firma criptográfica inmutable, la lista detallada de estudiantes
/// y copiar el JSON completo al portapapeles para auditoría externa.
class SignedActaDialog extends StatelessWidget {
  const SignedActaDialog({
    super.key,
    required this.acta,
    this.courseSecretHex,
  });

  /// Acta firmada que se va a visualizar.
  final SignedSessionActa acta;

  /// Clave secreta opcional para verificar la firma HMAC in situ.
  final String? courseSecretHex;

  /// Muestra el modal con el acta firmada.
  static Future<void> show(
    BuildContext context, {
    required SignedSessionActa acta,
    String? courseSecretHex,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => SignedActaDialog(
        acta: acta,
        courseSecretHex: courseSecretHex,
      ),
    );
  }

  /// Parsea un JSON de acta previamente guardado en SQLite y muestra el modal.
  static Future<void> showFromJson(
    BuildContext context, {
    required String actaJson,
    String? courseSecretHex,
  }) {
    final Map<String, dynamic> map =
        jsonDecode(actaJson) as Map<String, dynamic>;
    final List<dynamic> rawRecords =
        (map['records'] as List<dynamic>?) ?? <dynamic>[];

    final records = rawRecords.map((dynamic item) {
      final r = item as Map<String, dynamic>;
      return SessionActaRecord(
        bitIndex: r['bitIndex'] as int,
        studentCode: r['studentCode'] as String,
        fullName: r['fullName'] as String,
        status: r['status'] as String,
        method: r['method'] as String?,
        verifyCode: r['verifyCode'] as String?,
        rssi: (r['rssi'] as num?)?.toInt(),
      );
    }).toList(growable: false);

    final parsedActa = SignedSessionActa(
      sessionId: map['sessionId'] as String,
      courseId: map['courseId'] as String,
      courseCode: map['courseCode'] as String,
      courseName: map['courseName'] as String,
      sessionPin: map['sessionPin'] as String,
      startedAtIso: map['startedAtIso'] as String,
      closedAtIso: map['closedAtIso'] as String,
      totalEnrolled: map['totalEnrolled'] as int,
      presentBleCount: map['presentBleCount'] as int,
      presentManualCount: map['presentManualCount'] as int,
      absentCount: map['absentCount'] as int,
      bitmapHex: map['bitmapHex'] as String,
      records: records,
      actaHmacSignature: map['actaHmacSignature'] as String? ?? '',
    );

    return show(
      context,
      acta: parsedActa,
      courseSecretHex: courseSecretHex,
    );
  }

  void _copyToClipboard(BuildContext context) {
    final prettyJson = const JsonEncoder.withIndent('  ').convert(acta.toJson());
    Clipboard.setData(ClipboardData(text: prettyJson));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Acta criptográfica copiada al portapapeles en formato JSON.'),
        backgroundColor: Color(0xFF0033A0),
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalPresent = acta.presentBleCount + acta.presentManualCount;
    final double attendancePercent = acta.totalEnrolled == 0
        ? 0.0
        : (totalPresent / acta.totalEnrolled) * 100.0;

    final isSignatureValid = courseSecretHex != null && courseSecretHex!.isNotEmpty
        ? acta.verifySignature(courseSecretHex!)
        : null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 720),
        child: Column(
          children: <Widget>[
            // Cabecera institucional del Acta
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFF0033A0),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.verified_user_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Acta Criptográfica de Sesión',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${acta.courseName} (${acta.courseCode})',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'PIN: ${acta.sessionPin}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Cuerpo del Acta
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  // Resumen de Métricas
                  _buildMetricsRow(theme, totalPresent, attendancePercent),
                  const SizedBox(height: 16),

                  // Caja de Seguridad y Firma Criptográfica
                  _buildCryptoCard(theme, isSignatureValid),
                  const SizedBox(height: 16),

                  // Título de la lista de asistencia
                  Row(
                    children: <Widget>[
                      const Icon(Icons.people_alt_outlined, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Roster Oficial de la Sesión (${acta.records.length})',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Lista de estudiantes del acta
                  ...acta.records.map((SessionActaRecord record) {
                    return _buildStudentRecordTile(theme, record);
                  }),
                ],
              ),
            ),

            // Barra inferior con acciones
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(20)),
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Row(
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: () => _copyToClipboard(context),
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copiar JSON'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0033A0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: const Text('Aceptar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsRow(
    ThemeData theme,
    int totalPresent,
    double attendancePercent,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              _buildMetricItem(
                label: 'Presentes BLE',
                value: '${acta.presentBleCount}',
                color: Colors.green.shade700,
                icon: Icons.bluetooth_connected,
              ),
              _buildMetricItem(
                label: 'Manual',
                value: '${acta.presentManualCount}',
                color: Colors.orange.shade800,
                icon: Icons.touch_app,
              ),
              _buildMetricItem(
                label: 'Ausentes',
                value: '${acta.absentCount}',
                color: Colors.red.shade700,
                icon: Icons.person_off,
              ),
              _buildMetricItem(
                label: 'Asistencia',
                value: '${attendancePercent.toStringAsFixed(0)}%',
                color: const Color(0xFF0033A0),
                icon: Icons.pie_chart,
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                'Total Matriculados: ${acta.totalEnrolled}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Presentes: $totalPresent / ${acta.totalEnrolled}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: totalPresent > 0 ? Colors.green.shade800 : null,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Column(
      children: <Widget>[
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }

  Widget _buildCryptoCard(ThemeData theme, bool? isSignatureValid) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.lock_outline,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              const Text(
                'Sello Digital y Firma Inmutable',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const Spacer(),
              if (isSignatureValid != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isSignatureValid
                        ? Colors.green.shade100
                        : Colors.red.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        isSignatureValid ? Icons.check_circle : Icons.error,
                        size: 12,
                        color: isSignatureValid
                            ? Colors.green.shade800
                            : Colors.red.shade800,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isSignatureValid ? 'VÁLIDA' : 'INVÁLIDA',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isSignatureValid
                              ? Colors.green.shade800
                              : Colors.red.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              const Text(
                'Bitmap Final: ',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
              Expanded(
                child: Text(
                  '0x${acta.bitmapHex}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Firma HMAC-SHA256:',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: SelectableText(
              acta.actaHmacSignature,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentRecordTile(
    ThemeData theme,
    SessionActaRecord record,
  ) {
    final isPresent = record.isPresent;
    final isBle = record.method == AppConstants.attendanceMethodBleHmac;
    final bitStr = record.bitIndex.toString().padLeft(2, '0');

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isPresent
              ? Colors.green.shade200
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      color: isPresent ? Colors.green.shade50.withValues(alpha: 0.5) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: isPresent
                    ? Colors.green.shade600
                    : Colors.grey.shade400,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '#$bitStr',
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    record.fullName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Cód: ${record.studentCode}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (isPresent)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isBle
                          ? Colors.green.shade100
                          : Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isBle ? 'BLE' : 'MANUAL',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isBle
                            ? Colors.green.shade800
                            : Colors.orange.shade900,
                      ),
                    ),
                  ),
                  if (record.verifyCode != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        record.verifyCode!,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'AUSENTE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
