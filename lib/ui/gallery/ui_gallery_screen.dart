import 'package:flutter/material.dart';

import '../ui.dart';

/// Muestrario de los componentes del sistema de diseño.
///
/// No forma parte del flujo de la app: sirve para revisar el diseño en claro
/// y oscuro, y como ejemplo de uso para quien construye una pantalla.
class UiGalleryScreen extends StatefulWidget {
  const UiGalleryScreen({super.key});

  @override
  State<UiGalleryScreen> createState() => _UiGalleryScreenState();
}

class _UiGalleryScreenState extends State<UiGalleryScreen> {
  String _filter = 'todos';
  String _pin = '4';

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    return UiPage(
      header: UiBrandHeader(
        trailing: UiRoundIconButton(icon: Icons.tune_rounded, tooltip: 'Ajustes', onPressed: () {}),
      ),
      bottom: UiButton(label: 'Cerrar y firmar la sesión', onPressed: () {}),
      body: ListView(
        padding: const EdgeInsets.only(bottom: UiSpace.xxl),
        children: [
          const UiPageHeading(overline: 'Miércoles 11 de noviembre', title: 'Buenos días, profe'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: UiSpace.page),
            child: UiHeroCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  UiPill(
                    label: 'Sesión en curso',
                    dot: true,
                    background: c.veil,
                    foreground: c.onPrimary,
                  ),
                  const SizedBox(height: UiSpace.md),
                  const Text('Bases de Datos II', style: UiText.h2),
                  const Text('19 de 32 estudiantes ya llegaron', style: UiText.label),
                  const SizedBox(height: UiSpace.md),
                  const UiProgressBar(value: 19 / 32, semanticLabel: '19 de 32 presentes', onHero: true),
                  const SizedBox(height: UiSpace.lg),
                  UiButton(
                    label: 'Volver a la sesión',
                    variant: UiButtonVariant.onHero,
                    trailingIcon: Icons.arrow_forward_rounded,
                    compact: true,
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
          const UiSectionTitle('Tus clases'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: UiSpace.page),
            child: UiCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: UiSpace.md),
              radius: 18,
              onTap: () {},
              child: Row(
                children: [
                  const UiAvatar(name: 'Bases Datos', square: true),
                  const SizedBox(width: UiSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Bases de Datos II', style: UiText.title),
                        Text('Grupo 01 · 32 estudiantes', style: UiText.label.copyWith(color: c.muted)),
                      ],
                    ),
                  ),
                  const UiPill(label: 'Nueva', tone: UiTone.manual),
                ],
              ),
            ),
          ),
          const UiSectionTitle('Sesión en vivo'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: UiSpace.page),
            child: UiCard(
              radius: UiRadius.xl,
              child: Row(
                children: [
                  UiProgressRing.count(count: 19, total: 32),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('PIN de la clase', style: UiText.label.copyWith(color: c.muted)),
                        const SizedBox(height: UiSpace.sm),
                        const UiPinDisplay(pin: '47'),
                        const SizedBox(height: UiSpace.sm),
                        Text('Díctalo en voz alta', style: UiText.label.copyWith(color: c.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          UiFilterPills<String>(
            selected: _filter,
            onSelected: (value) => setState(() => _filter = value),
            options: const [
              UiFilterOption(value: 'todos', label: 'Todos 32'),
              UiFilterOption(value: 'faltan', label: 'Faltan 13'),
              UiFilterOption(value: 'llegaron', label: 'Llegaron 19'),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: UiSpace.page),
            child: UiListGroup(
              children: [
                const UiPersonRow(
                  name: 'Ana Lucía Pérez',
                  subtitle: 'Acaba de llegar · Bluetooth',
                  highlighted: true,
                  trailing: UiStatusChip(status: UiStatus.present, solid: true),
                ),
                const UiPersonRow(
                  name: 'Carlos Iguarán',
                  subtitle: '08:40 · Bluetooth',
                  trailing: UiStatusChip(status: UiStatus.present),
                ),
                const UiPersonRow(
                  name: 'María Epieyú',
                  subtitle: '08:39 · No trajo celular',
                  avatarTone: UiTone.manual,
                  trailing: UiStatusChip(status: UiStatus.manual),
                ),
                UiPersonRow(
                  name: 'José Pushaina',
                  subtitle: 'Aún no llega',
                  avatarTone: UiTone.neutral,
                  trailing: UiButton(
                    label: 'Marcar',
                    variant: UiButtonVariant.outline,
                    compact: true,
                    expand: false,
                    onPressed: () {},
                  ),
                ),
                const UiPersonRow(
                  name: 'Luisa Fernanda Brito',
                  subtitle: 'No asistió',
                  avatarTone: UiTone.absent,
                  trailing: UiStatusChip(status: UiStatus.absent),
                ),
              ],
            ),
          ),
          const UiSectionTitle('Datos de la clase'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: UiSpace.page),
            child: Row(
              children: [
                Expanded(child: UiStatTile(value: '12', label: 'sesiones')),
                SizedBox(width: 10),
                Expanded(child: UiStatTile(value: '91 %', label: 'asistencia')),
                SizedBox(width: 10),
                Expanded(child: UiStatTile(value: '3', label: 'en riesgo', tone: UiTone.absent)),
              ],
            ),
          ),
          const UiSectionTitle('Avisos'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: UiSpace.page),
            child: Column(
              children: [
                UiBanner(
                  tone: UiBannerTone.warning,
                  title: 'El Bluetooth está apagado',
                  message: 'Enciéndelo para que los estudiantes puedan registrarse.',
                  actionLabel: 'Encender Bluetooth',
                  onAction: () {},
                ),
                const SizedBox(height: 10),
                const UiBanner(
                  tone: UiBannerTone.error,
                  message: 'No se pudo guardar la sesión. Inténtalo de nuevo.',
                ),
                const SizedBox(height: 10),
                const UiBanner(
                  tone: UiBannerTone.info,
                  message: 'Deja esta pantalla abierta mientras dure la clase.',
                ),
              ],
            ),
          ),
          const UiSectionTitle('Estudiante: marcar asistencia'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: UiSpace.page),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Align(alignment: Alignment.centerLeft, child: UiStepBar(current: 2, total: 3)),
                const SizedBox(height: UiSpace.lg),
                UiPinEntry(value: _pin),
                const SizedBox(height: UiSpace.lg),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: UiSpace.sm),
                  child: UiPinKeypad(
                    onDigit: (d) => setState(() => _pin = _pin.length >= 2 ? d : _pin + d),
                    onBackspace: () => setState(
                      () => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1),
                    ),
                  ),
                ),
                const SizedBox(height: UiSpace.xl),
                UiCard(
                  tone: UiTone.tint,
                  radius: UiRadius.xxl,
                  child: Column(
                    children: [
                      // Wrap y no Row: con letra grande las pastillas bajan de línea.
                      SizedBox(
                        width: double.infinity,
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          spacing: UiSpace.sm,
                          runSpacing: UiSpace.sm,
                          children: [
                            UiPill(label: 'PIN 47', background: c.surface, foreground: c.ink),
                            const UiPill(label: 'Buscando al profesor', dot: true, tone: UiTone.primary),
                          ],
                        ),
                      ),
                      const SizedBox(height: UiSpace.xxl),
                      const UiTwoPhones(signal: 2),
                      const SizedBox(height: UiSpace.lg),
                      const Text('Señal media: acércate un poco más', style: UiText.label),
                    ],
                  ),
                ),
                const SizedBox(height: UiSpace.md),
                UiHeroCard(
                  motifSize: 220,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(color: c.onPrimary, shape: BoxShape.circle),
                        child: Icon(Icons.check_rounded, size: 34, color: c.primary),
                      ),
                      const SizedBox(height: 72),
                      const Text('Asistencia registrada', style: UiText.bodyStrong),
                      const Text('¡Presente!', style: UiText.display),
                    ],
                  ),
                ),
                const SizedBox(height: UiSpace.md),
                const UiListGroup(
                  children: [
                    UiInfoRow(label: 'Clase', value: 'Bases de Datos II'),
                    UiInfoRow(label: 'Fecha y hora', value: 'Mié 11 nov · 8:41 a. m.'),
                    UiInfoRow(label: 'Confirmó', value: 'El celular del profesor'),
                  ],
                ),
                const SizedBox(height: UiSpace.md),
                const UiHistoryDots(
                  attended: [true, true, true, true, true, true, false, true, true, true, true, true],
                ),
                const SizedBox(height: UiSpace.md),
                Row(
                  children: [
                    Expanded(
                      child: UiButton(
                        label: 'Estudiantes',
                        icon: Icons.person_outline_rounded,
                        variant: UiButtonVariant.tonal,
                        onPressed: () {},
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: UiButton(
                        label: 'Enviar Excel',
                        icon: Icons.ios_share_rounded,
                        variant: UiButtonVariant.tonal,
                        onPressed: () {},
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                UiButton(
                  label: 'Unirme a una clase',
                  icon: Icons.qr_code_scanner_rounded,
                  variant: UiButtonVariant.outline,
                  onPressed: () {},
                ),
              ],
            ),
          ),
          const SizedBox(
            height: 360,
            child: UiEmptyState(
              icon: Icons.school_outlined,
              title: 'Aún no tienes clases',
              message: 'Crea tu primera clase para empezar a tomar asistencia.',
              actionLabel: 'Crear mi primera clase',
            ),
          ),
        ],
      ),
    );
  }
}
