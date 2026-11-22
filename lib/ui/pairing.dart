import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/lan_service.dart';

class PairingPanel extends StatefulWidget {
  final LanService lan;
  const PairingPanel({super.key, required this.lan});
  @override
  State<PairingPanel> createState() => _PairingPanelState();
}

class _PairingPanelState extends State<PairingPanel> {
  final code = TextEditingController();
  String? qr, error;
  bool busy = false;
  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> action(Future<void> Function() f) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await f();
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'No se pudo conectar. Comprueba que ambos equipos estén en la misma red y genera un nuevo QR.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> scan() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScanPage()),
    );
    if (result != null) {
      code.text = result;
      await action(() => widget.lan.pair(result));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.lan,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        Text(
          'Tus dispositivos',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Abre Hilva en ambos equipos y conéctalos a la misma red. Genera el QR en el PC y escanéalo desde el celular. Sin cuentas.',
        ),
        const SizedBox(height: 12),
        Text(
          widget.lan.status,
          style: TextStyle(color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () => action(() async {
                      final value = await widget.lan.pairingCode();
                      if (mounted) setState(() => qr = value);
                    }),
              icon: const Icon(Icons.qr_code),
              label: const Text('Mostrar QR'),
            ),
            if (Platform.isAndroid)
              OutlinedButton.icon(
                onPressed: busy ? null : scan,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Escanear QR'),
              ),
            if (widget.lan.paired)
              OutlinedButton(
                onPressed: busy ? null : () => action(widget.lan.sync),
                child: const Text('Sincronizar ahora'),
              ),
            if (widget.lan.paired)
              TextButton(
                onPressed: busy ? null : () => action(widget.lan.forget),
                child: const Text('Desvincular'),
              ),
          ],
        ),
        if (qr != null) ...[
          const SizedBox(height: 16),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: QrImageView(
              data: qr!,
              size: 230,
              backgroundColor: Colors.white,
            ),
          ),
          const Text(
            'Válido 5 minutos. El código permite vincular un dispositivo.',
          ),
          TextButton.icon(
            onPressed: () => Clipboard.setData(ClipboardData(text: qr!)),
            icon: const Icon(Icons.copy),
            label: const Text('Copiar código'),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: code,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'O pega el código del otro equipo',
          ),
        ),
        TextButton(
          onPressed: busy
              ? null
              : () => action(() => widget.lan.pair(code.text.trim())),
          child: const Text('Vincular con código'),
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 8),
        Text(
          'Sincronización automática cada 5 minutos con Hilva abierta; en Windows también desde la bandeja. Puedes usar Sincronizar ahora cuando quieras. Al volver a abrirla se sincroniza si ya pasaron 5 minutos. Si cambia la dirección de red, vuelve a vincular. Máximo 45 MB de adjuntos por intercambio.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  bool done = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Escanear QR de Hilva')),
    body: MobileScanner(
      onDetect: (capture) {
        final value = capture.barcodes.firstOrNull?.rawValue;
        if (!done && value != null) {
          done = true;
          Navigator.pop(context, value);
        }
      },
    ),
  );
}
