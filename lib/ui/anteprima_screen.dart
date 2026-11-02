import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../db.dart';
import '../digishare.dart';
import '../registratore.dart';
import '../theme.dart';
import 'home_screen.dart';
import 'nota_screen.dart';

/// Appena finita la registrazione: si riascolta, si sistema il titolo e si decide.
/// Trascrizione e IA partono solo da Invia. Chi esce senza scegliere ritrova la nota in elenco come «Da inviare».
class AnteprimaScreen extends StatefulWidget {
  const AnteprimaScreen({super.key, required this.id});
  final int id;
  @override
  State<AnteprimaScreen> createState() => _AnteprimaScreenState();
}

class _AnteprimaScreenState extends State<AnteprimaScreen> {
  final _player = AudioPlayer();
  final _titolo = TextEditingController();
  Nota? _n;
  bool _audio = false;
  bool _caricoAudio = true;
  bool _deciso = false;

  @override
  void initState() {
    super.initState();
    _carica();
  }

  Future<void> _carica() async {
    final n = await db.nota(widget.id);
    if (n == null) {
      if (mounted) Navigator.pop(context);
      return;
    }
    if (!mounted) return;
    // Titolo e pulsanti si vedono subito: un audio che non si apre non deve lasciare fermi su questa schermata.
    _titolo.text = n.titolo;
    setState(() => _n = n);
    final parti = await db.parti(n.id);
    if (parti.isEmpty || !await File(parti.first.percorso).exists()) {
      if (mounted) setState(() => _caricoAudio = false);
      return;
    }
    try {
      await _player.setFilePath(parti.first.percorso);
      if (mounted) setState(() => _audio = true);
    } catch (e) {
      if (mounted) avviso(context, 'Non riesco ad aprire l\'audio: $e');
    }
    if (mounted) setState(() => _caricoAudio = false);
  }

  @override
  void dispose() {
    if (!_deciso) _salvaTitolo();
    _player.dispose();
    _titolo.dispose();
    super.dispose();
  }

  Future<void> _salvaTitolo() async {
    final n = _n;
    final t = _titolo.text.trim();
    if (n == null || t.isEmpty || t == n.titolo) return;
    await db.aggiornaNota(n.id, {'titolo': t});
    cloud.notaCambiata();
  }

  Future<void> _invia() async {
    _deciso = true;
    await _player.stop();
    await _salvaTitolo();
    final rete = await cloud.reteConsentita();
    await cloud.confermaInvio(widget.id);
    if (!mounted) return;
    if (!cloud.collegato) {
      avviso(context, 'Parte quando colleghi DiGiShare in Impostazioni.');
    } else if (!rete) {
      avviso(context, 'Parte appena c\'è il Wi-Fi.');
    }
    Navigator.pushReplacement(context, MaterialPageRoute<void>(builder: (_) => NotaScreen(id: widget.id)));
  }

  Future<void> _elimina() async {
    final ok = await conferma(context, 'Eliminare la registrazione?', 'L\'audio si cancella dal telefono e non si recupera. A DiGiShare non arriva niente.', si: 'Elimina');
    if (!ok) return;
    _deciso = true;
    await _player.stop();
    await eliminaNota(_n!);
    cloud.notaCambiata();
    if (mounted) Navigator.pop(context);
  }

  Widget _lettore() => StreamBuilder<PlayerState>(
        stream: _player.playerStateStream,
        builder: (_, st) => StreamBuilder<Duration>(
          stream: _player.positionStream,
          builder: (_, __) {
            final finito = st.data?.processingState == ProcessingState.completed;
            final suona = (st.data?.playing ?? false) && !finito;
            final tot = (_player.duration?.inMilliseconds ?? _n!.durataMs).clamp(1, 1 << 40);
            final pos = _player.position.inMilliseconds.clamp(0, tot);
            return Row(children: [
              IconButton(
                icon: Icon(suona ? Icons.pause : Icons.play_arrow),
                iconSize: 32,
                tooltip: suona ? 'Pausa' : 'Ascolta',
                onPressed: () async {
                  if (suona) return _player.pause();
                  if (finito) await _player.seek(Duration.zero);
                  await _player.play();
                },
              ),
              Expanded(
                child: SliderTheme(
                  data: const SliderThemeData(trackHeight: 5, activeTrackColor: kRosa, thumbColor: kInk, inactiveTrackColor: kFilo2, overlayShape: RoundSliderOverlayShape(overlayRadius: 14)),
                  child: Slider(value: pos.toDouble(), max: tot.toDouble(), onChanged: (v) => _player.seek(Duration(milliseconds: v.round()))),
                ),
              ),
              Text('${durata(pos)} / ${durata(tot)}', style: const TextStyle(fontSize: 13, fontFeatures: [ui.FontFeature.tabularFigures()])),
              const SizedBox(width: 4),
            ]);
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final n = _n;
    return Scaffold(
      appBar: const Barra(titolo: 'Anteprima'),
      body: n == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(
                    child: ListView(children: [
                      const Etichetta('Titolo'),
                      const SizedBox(height: 8),
                      TextField(controller: _titolo, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'Titolo della nota')),
                      const SizedBox(height: 18),
                      const Etichetta('Riascolta'),
                      const SizedBox(height: 8),
                      _audio ? _lettore() : Text(_caricoAudio ? 'Sto aprendo l\'audio…' : 'Audio non disponibile sul telefono.', style: const TextStyle(fontSize: 15)),
                      const SizedBox(height: 18),
                      const Text('Finché non premi Invia, la registrazione resta solo sul telefono.', style: TextStyle(fontSize: 15)),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: Secondario(testo: 'Elimina', icona: Icons.delete_outline, alto: 54, onTap: _elimina)),
                    const SizedBox(width: 8),
                    Expanded(child: Principale(testo: 'Invia', icona: Icons.send, alto: 54, onTap: _invia)),
                  ]),
                ]),
              ),
            ),
    );
  }
}
