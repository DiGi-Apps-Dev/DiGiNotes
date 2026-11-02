import 'dart:convert';

import 'package:flutter/material.dart';

import '../db.dart';
import '../registratore.dart';
import '../theme.dart';
import 'nota_screen.dart';

/// Chiedi. Sul telefono trova le frasi giuste e dice da dove vengono; la risposta scritta dall'IA arriverà da DiGiShare.
class ChiediVista extends StatefulWidget {
  const ChiediVista({super.key, this.nota, this.incorporata = false});
  final int? nota;
  final bool incorporata;
  @override
  State<ChiediVista> createState() => _ChiediVistaState();
}

class _Msg {
  _Msg(this.mia, this.testo, {this.fonti = const []});
  final bool mia;
  final String testo;
  final List<Risultato> fonti;
}

class _ChiediVistaState extends State<ChiediVista> {
  final _c = TextEditingController();
  final _sc = ScrollController();
  final _msg = <_Msg>[];
  late bool _tutte = widget.nota == null;
  List<Map<String, Object?>> _skill = [];

  int? get _nota => _tutte ? null : widget.nota;

  @override
  void initState() {
    super.initState();
    _storico();
    _caricaSkill();
  }

  Future<void> _caricaSkill() async {
    final r = await db.lista('skill');
    if (mounted) setState(() => _skill = r);
  }

  /// Una skill è una domanda salvata: si rilancia con un tocco, si toglie tenendola premuta.
  Future<void> _nuovaSkill() async {
    final t = await chiediTesto(context, 'Nuova skill', etichetta: 'La domanda da salvare', iniziale: _c.text.trim(), righe: 3);
    if (t == null) return;
    await db.aggiungiLista('skill', 'testo', t);
    _caricaSkill();
  }

  Future<void> _togliSkill(Map<String, Object?> x) async {
    final ok = await conferma(context, 'Togli skill', '«${x['testo']}» sparisce dalle skill.', si: 'Togli');
    if (!ok) return;
    await db.eliminaLista('skill', x['id'] as int);
    _caricaSkill();
  }

  Future<void> _storico() async {
    final righe = await db.storicoChat(nota: widget.nota);
    final m = <_Msg>[];
    for (final r in righe) {
      m.add(_Msg(true, r['domanda'] as String));
      final fonti = <Risultato>[];
      for (final id in (jsonDecode(r['fonti'] as String) as List).cast<int>()) {
        final n = await db.nota(id);
        if (n != null) fonti.add(Risultato(n, null, null));
      }
      m.add(_Msg(false, r['risposta'] as String, fonti: fonti));
    }
    if (mounted) setState(() => _msg.addAll(m));
  }

  void _giu() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_sc.hasClients) _sc.jumpTo(_sc.position.maxScrollExtent);
      });

  Future<void> _registra(String d, String r, List<Risultato> fonti) async {
    await db.salvaChat(widget.nota, d, r, fonti.map((f) => f.nota.id).toSet().toList());
    if (!mounted) return;
    setState(() {
      _msg.add(_Msg(true, d));
      _msg.add(_Msg(false, r, fonti: fonti));
    });
    _giu();
  }

  Future<void> _chiedi() async {
    final d = _c.text.trim();
    if (d.isEmpty) return;
    _c.clear();
    final f = await db.frasiPertinenti(d, nota: _nota);
    final r = f.isEmpty
        ? 'Non ho trovato frasi su questo nelle note con testo. Le risposte scritte dall\'IA arrivano quando DiGiShare è pronta.'
        : 'Ho trovato ${f.length == 1 ? 'questa frase' : 'queste ${f.length} frasi'} nelle tue note:';
    await _registra(d, r, f);
  }

  Future<void> _azione(String d, String sezione) async {
    final f = await db.dalleSezioni(sezione, nota: _nota);
    await _registra(d, f.isEmpty ? 'Nessun riassunto ha ancora una sezione «$sezione».' : 'Dai riassunti:', f);
  }

  Widget _bolla(_Msg m) => Align(
        alignment: m.mia ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .84),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(gradient: m.mia ? kMarchio : null, color: m.mia ? null : kG2, borderRadius: BorderRadius.circular(8), border: m.mia ? null : Border.all(color: kFilo2)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.testo, style: TextStyle(fontSize: 15, color: m.mia ? Colors.white : kInk)),
            for (final f in m.fonti)
              InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => NotaScreen(id: f.nota.id, saltaA: f.ms, scheda: f.ms == null ? 0 : 1))),
                child: Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (f.frase != null) Text('«${f.frase}»', style: const TextStyle(fontSize: 14.5)),
                    Text('${f.nota.titolo}${f.ms == null ? '' : ' · ${durata(f.ms!)}'}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
                  ]),
                ),
              ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (widget.nota != null) ...[
            Row(children: [
              Chip2('Questa nota', acceso: !_tutte, onTap: () => setState(() => _tutte = false)),
              const SizedBox(width: 6),
              Chip2('Tutte le note', acceso: _tutte, onTap: () => setState(() => _tutte = true)),
            ]),
            const SizedBox(height: 6),
          ],
          SizedBox(
            height: 36,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              Chip2('Cose da fare', onTap: () => _azione('Cose da fare', 'Cose da fare')),
              const SizedBox(width: 6),
              Chip2('Decisioni', onTap: () => _azione('Decisioni', 'Decisioni')),
              const SizedBox(width: 6),
              Chip2('Dati chiave', onTap: () => _azione('Dati chiave', 'Dati chiave')),
              for (final x in _skill) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onLongPress: () => _togliSkill(x),
                  child: Chip2((x['testo'] as String).length > 26 ? '${(x['testo'] as String).substring(0, 26)}…' : x['testo'] as String, icona: Icons.bolt, onTap: () {
                    _c.text = x['testo'] as String;
                    _chiedi();
                  }),
                ),
              ],
              const SizedBox(width: 6),
              Chip2('+ Skill', onTap: _nuovaSkill),
              const SizedBox(width: 6),
              Chip2('Svuota', icona: Icons.delete_outline, onTap: () async {
                await db.svuotaChat(nota: widget.nota);
                if (mounted) setState(_msg.clear);
              }),
            ]),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _msg.isEmpty
                ? const Text('Chiedi qualcosa sulle tue registrazioni. Per esempio: che franchigia ho concordato?', style: TextStyle(fontSize: 15))
                : ListView(controller: _sc, children: [for (final m in _msg) _bolla(m)]),
          ),
          TextField(
            controller: _c,
            minLines: 1,
            maxLines: 3,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _chiedi(),
            decoration: InputDecoration(
              hintText: 'Scrivi una domanda',
              suffixIcon: IconButton(icon: const Icon(Icons.send), tooltip: 'Invia', onPressed: _chiedi),
            ),
          ),
        ]),
      );
}
