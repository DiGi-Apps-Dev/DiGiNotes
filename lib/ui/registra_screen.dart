import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../registratore.dart';
import '../theme.dart';
import 'anteprima_screen.dart';

/// Apre il foglio di scelta, o parte subito se il tipo è impostato in Impostazioni.
Future<void> nuovaRegistrazione(BuildContext context, {VoidCallback? importa, int? cartella}) async {
  if (registratore.attivo) {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const RegistraScreen()));
    return;
  }
  final pref = await SharedPreferences.getInstance();
  if (!context.mounted) return;
  final fisso = pref.getString('tipo_fisso');
  String? tipo = fisso;
  if (tipo == null) {
    tipo = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (c) => _Scelta(importa: importa == null ? null : () {
        Navigator.pop(c);
        importa();
      }),
    );
  }
  if (tipo == null || !context.mounted) return;
  await _parti(context, tipo, cartella: cartella);
}

Future<void> _parti(BuildContext context, String tipo, {int? cartella}) async {
  final notif = await FlutterForegroundTask.requestNotificationPermission();
  if (!context.mounted) return;
  if (!await registratore.haPermesso()) {
    if (context.mounted) avviso(context, 'Senza il permesso del microfono non posso registrare. Attivalo nelle impostazioni di Android.');
    return;
  }
  try {
    await registratore.inizia(tipo: tipo, cartella: cartella);
  } catch (e) {
    if (context.mounted) avviso(context, 'Registrazione non partita: $e');
    return;
  }
  if (!context.mounted) return;
  if (notif != NotificationPermission.granted) avviso(context, 'Senza il permesso per le notifiche non vedrai l\'avviso fisso, ma registro lo stesso.');
  await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const RegistraScreen()));
}

class _Scelta extends StatefulWidget {
  const _Scelta({this.importa});
  final VoidCallback? importa;
  @override
  State<_Scelta> createState() => _SceltaState();
}

class _SceltaState extends State<_Scelta> {
  String _tipo = 'appuntamento';
  bool _filtro = true;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _filtro = p.getString('filtro_rumore') != 'spento');
    });
  }

  Future<void> _scegliFiltro(bool acceso) async {
    setState(() => _filtro = acceso);
    final p = await SharedPreferences.getInstance();
    await p.setString('filtro_rumore', acceso ? 'forte' : 'spento');
  }

  Widget _riq(String v, String t, String d) {
    final on = _tipo == v;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _tipo = v),
      child: Container(
        padding: const EdgeInsets.all(12),
        width: double.infinity,
        decoration: BoxDecoration(gradient: on ? kMarchio : null, color: on ? null : kG2, borderRadius: BorderRadius.circular(8), border: on ? null : Border.all(color: kFilo2)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: on ? Colors.white : kInk)),
          const SizedBox(height: 2),
          Text(d, style: TextStyle(fontSize: 14, color: on ? Colors.white : kInk)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Etichetta('Nuova registrazione'),
            const SizedBox(height: 10),
            _riq('appuntamento', 'Appuntamento', 'Lungo. Riassunto con decisioni e cose da fare.'),
            const SizedBox(height: 8),
            _riq('idea', 'Nota vocale', 'Un\'idea al volo. Solo trascrizione, senza riassunto.'),
            const SizedBox(height: 12),
            Row(children: [
              const Expanded(child: Text('Filtro rumore', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
              Switch(value: _filtro, onChanged: _scegliFiltro),
            ]),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(gradient: kTenue, borderRadius: BorderRadius.circular(8), border: Border.all(color: kRosa)),
              child: const Text('Avvisa i presenti che stai registrando: la legge chiede il loro assenso.', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 10),
            Principale(testo: 'Registra', icona: Icons.mic, alto: 54, onTap: () => Navigator.pop(context, _tipo)),
            if (widget.importa != null) ...[
              const SizedBox(height: 8),
              Secondario(testo: 'Importa un audio', icona: Icons.upload, onTap: widget.importa),
            ],
          ]),
        ),
      );
}

class RegistraScreen extends StatefulWidget {
  const RegistraScreen({super.key});
  @override
  State<RegistraScreen> createState() => _RegistraScreenState();
}

class _RegistraScreenState extends State<RegistraScreen> {
  bool _chiudo = false;

  Future<void> _foto() async {
    final XFile? x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 2200);
    if (x == null) return;
    final dir = await Registratore.cartellaAudio();
    final dest = p.join(dir.path, 'foto-${DateTime.now().millisecondsSinceEpoch}.jpg');
    await File(x.path).copy(dest);
    await registratore.segna('foto', percorso: dest);
  }

  Future<void> _nota() async {
    final t = await chiediTesto(context, 'Scrivi una nota', etichetta: 'Cosa vuoi ricordare', righe: 3);
    if (t != null) await registratore.segna('testo', testo: t);
  }

  Future<void> _segna() async {
    await registratore.segna('segna');
    if (mounted) avviso(context, 'Momento segnato a ${durata(registratore.ms)}');
  }

  Future<void> _fine() async {
    if (_chiudo) return;
    setState(() => _chiudo = true);
    final id = await registratore.ferma();
    if (!mounted) return;
    if (id == null) {
      avviso(context, 'Non c\'è audio da salvare.');
      Navigator.pop(context);
      return;
    }
    // Niente parte da solo: prima si riascolta, poi l'utente decide se inviare o eliminare.
    Navigator.pushReplacement(context, MaterialPageRoute<void>(builder: (_) => AnteprimaScreen(id: id)));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: registratore,
        builder: (_, __) {
          final r = registratore;
          return PopScope(
            canPop: true,
            child: Scaffold(
              appBar: Barra(titolo: r.tipo == 'appuntamento' ? 'Appuntamento' : 'Nota vocale', azioni: [
                Container(
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.white)),
                  child: Text(r.inPausa ? 'PAUSA' : 'REC', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ]),
              body: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (r.muto)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(gradient: kMarchio, borderRadius: BorderRadius.circular(8)),
                        child: const Text('Il microfono è muto: non sto sentendo. Da qui manca l\'audio.', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                    const SizedBox(height: 8),
                    Text(durata(r.ms, lunga: true), textAlign: TextAlign.center, style: const TextStyle(fontSize: 54, fontWeight: FontWeight.w600, height: 1.05, fontFeatures: [ui.FontFeature.tabularFigures()])),
                    SizedBox(height: 86, child: CustomPaint(painter: _Onda(List.of(r.livelli)))),
                    Row(children: [
                      Expanded(child: Secondario(testo: 'Segna', icona: Icons.flag_outlined, onTap: _segna)),
                      const SizedBox(width: 8),
                      Expanded(child: Secondario(testo: 'Foto', icona: Icons.photo_camera_outlined, onTap: _foto)),
                    ]),
                    const SizedBox(height: 8),
                    Secondario(testo: 'Scrivi una nota', icona: Icons.title, onTap: _nota),
                    const SizedBox(height: 14),
                    const Etichetta('Momenti segnati'),
                    const SizedBox(height: 8),
                    Expanded(
                      child: r.segni.isEmpty
                          ? const Text('Niente per ora. Puoi spegnere lo schermo: continuo a registrare.', style: TextStyle(fontSize: 15))
                          : ListView(children: [
                              Elenco(figli: [
                                for (final s in r.segni.reversed)
                                  ListTile(
                                    dense: true,
                                    leading: Icon(s.tipo == 'foto' ? Icons.photo_camera_outlined : (s.tipo == 'testo' ? Icons.title : Icons.flag_outlined)),
                                    title: Text(s.testo.isEmpty ? (s.tipo == 'foto' ? 'Foto' : 'Momento segnato') : s.testo, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                    subtitle: Text(durata(s.ms), style: const TextStyle(fontSize: 13.5)),
                                  ),
                              ]),
                            ]),
                    ),
                    Row(children: [
                      Expanded(
                        child: Secondario(
                          testo: r.inPausa ? 'Riprendi' : 'Pausa',
                          icona: r.inPausa ? Icons.play_arrow : Icons.pause,
                          alto: 54,
                          onTap: r.inPausa ? r.riprendi : r.pausa,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Principale(testo: 'Fine', icona: Icons.stop, alto: 54, onTap: _chiudo ? null : _fine)),
                    ]),
                  ]),
                ),
              ),
            ),
          );
        },
      );
}

class _Onda extends CustomPainter {
  _Onda(this.v);
  final List<double> v;
  @override
  void paint(Canvas c, Size s) {
    final pen = Paint()
      ..shader = kMarchio.createShader(Offset.zero & s)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const passo = 7.0;
    final quante = (s.width / passo).floor();
    final dati = v.length > quante ? v.sublist(v.length - quante) : v;
    final inizio = s.width / 2 - dati.length * passo / 2;
    for (var i = 0; i < dati.length; i++) {
      final x = inizio + i * passo;
      final h = dati[i] * s.height * .9;
      c.drawLine(Offset(x, s.height / 2 - h / 2), Offset(x, s.height / 2 + h / 2), pen);
    }
  }

  @override
  bool shouldRepaint(_Onda o) => true;
}
