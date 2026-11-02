import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db.dart';
import '../digishare.dart';
import '../registratore.dart';
import '../theme.dart';
import 'chiedi_screen.dart';

/// Il dettaglio di una nota: Riassunto, Testo, Mappa, Chiedi, con il lettore sempre in basso.
/// Una Nota vocale ha solo il testo: si ascolta, si legge e si cancella.
class NotaScreen extends StatefulWidget {
  const NotaScreen({super.key, required this.id, this.saltaA, this.scheda = 0});
  final int id;
  final int? saltaA;
  final int scheda;
  @override
  State<NotaScreen> createState() => _NotaScreenState();
}

class _NotaScreenState extends State<NotaScreen> with SingleTickerProviderStateMixin {
  TabController? _tab;
  final _enh = AndroidLoudnessEnhancer();
  late final _player = AudioPlayer(audioPipeline: AudioPipeline(androidAudioEffects: [_enh]));
  Nota? _n;
  List<Parte> _parti = [];
  List<Segmento> _seg = [];
  List<Riassunto> _ria = [];
  List<Segno> _segni = [];
  int _riaScelto = 0;
  int? _attivo;
  final List<int> _durate = [];
  double _vel = 1;
  bool _forte = false;
  bool? _voto;

  @override
  void initState() {
    super.initState();
    cloud.noteCambiate.addListener(_carica);
    _carica(primaVolta: true);
    _player.positionStream.listen((_) {
      if (!mounted) return;
      final m = _posizione;
      int? a;
      for (final s in _seg) {
        if (s.inizioMs <= m) a = s.id;
      }
      if (a != _attivo) setState(() => _attivo = a);
    });
  }

  @override
  void dispose() {
    cloud.noteCambiate.removeListener(_carica);
    _player.dispose();
    _tab?.dispose();
    super.dispose();
  }

  Future<void> _carica({bool primaVolta = false}) async {
    final n = await db.nota(widget.id);
    if (n == null) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final parti = await db.parti(n.id);
    // Dopo un taglio si vede solo quello che è rimasto nell'audio.
    bool dentro(int ms) => ms >= 0 && (n.durataMs <= 0 || ms <= n.durataMs);
    final seg = (await db.segmenti(n.id)).where((s) => dentro(s.inizioMs)).toList();
    final ria = await db.riassunti(n.id);
    final segni = (await db.segni(n.id)).where((s) => dentro(s.ms)).toList();
    if (!mounted) return;
    if (n.appuntamento) _tab ??= TabController(length: 4, vsync: this, initialIndex: widget.scheda);
    setState(() {
      _n = n;
      _parti = parti;
      _seg = seg;
      _ria = ria;
      _segni = segni;
      if (_riaScelto >= ria.length) _riaScelto = 0;
    });
    if (ria.isNotEmpty) {
      final p = await SharedPreferences.getInstance();
      final v = p.getBool('voto_${ria[_riaScelto].id}');
      if (mounted) setState(() => _voto = v);
    }
    if (primaVolta) {
      await _preparaAudio();
      if (widget.saltaA != null) await _vai(widget.saltaA!);
    }
  }

  Future<void> _preparaAudio() async {
    final fonti = <AudioSource>[];
    for (final x in _parti) {
      if (!await File(x.percorso).exists()) continue;
      final f = AudioSource.file(x.percorso);
      fonti.add(x.inizioMs > 0 || x.fineMs != null
          ? ClippingAudioSource(child: f, start: Duration(milliseconds: x.inizioMs), end: x.fineMs == null ? null : Duration(milliseconds: x.fineMs!))
          : f);
    }
    if (fonti.isEmpty) return;
    try {
      await _player.setAudioSources(fonti);
      _durate
        ..clear()
        ..addAll(_player.sequence.map((s) => s.duration?.inMilliseconds ?? 0));
      // Un audio importato non conosce la sua durata finché non si apre.
      if (_n != null && _n!.durataMs == 0 && _totale > 0) {
        await db.aggiornaNota(_n!.id, {'durata_ms': _totale});
        _n = await db.nota(_n!.id);
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) avviso(context, 'Non riesco ad aprire l\'audio: $e');
    }
  }

  int get _totale => _durate.isEmpty ? (_n?.durataMs ?? 0) : _durate.fold(0, (a, b) => a + b);
  int get _posizione {
    final i = _player.currentIndex ?? 0;
    var m = _player.position.inMilliseconds;
    for (var k = 0; k < i && k < _durate.length; k++) {
      m += _durate[k];
    }
    return m;
  }

  Future<void> _vai(int ms) async {
    var resto = ms;
    for (var i = 0; i < _durate.length; i++) {
      if (resto < _durate[i] || i == _durate.length - 1) {
        await _player.seek(Duration(milliseconds: resto), index: i);
        return;
      }
      resto -= _durate[i];
    }
  }

  Future<void> _rinomina() async {
    final t = await chiediTesto(context, 'Rinomina', iniziale: _n!.titolo, etichetta: 'Titolo');
    if (t == null) return;
    await db.aggiornaNota(_n!.id, {'titolo': t});
    _carica();
  }

  Future<void> _sposta() async {
    final cc = await db.cartelle();
    if (!mounted) return;
    final scelta = await showModalBottomSheet<int>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(14), children: [
          const Etichetta('Sposta in'),
          const SizedBox(height: 8),
          ListTile(leading: const Icon(Icons.inbox_outlined), title: const Text('Nessuna cartella'), onTap: () => Navigator.pop(c, -1)),
          for (final x in cc) ListTile(leading: const Icon(Icons.folder_outlined), title: Text(x.nome), onTap: () => Navigator.pop(c, x.id)),
        ]),
      ),
    );
    if (scelta == null) return;
    await db.sposta([_n!.id], scelta == -1 ? null : scelta);
    if (mounted) avviso(context, 'Nota spostata');
    _carica();
  }

  Future<void> _taglia() async {
    final tot = _totale;
    if (tot <= 0 || _parti.length != 1) {
      avviso(context, _parti.length > 1 ? 'Una nota unita non si taglia: taglia le note prima di unirle.' : 'Questa nota non ha audio da tagliare.');
      return;
    }
    final att = _parti.first;
    final origTot = tot + att.inizioMs;
    var ini = att.inizioMs.toDouble();
    var fin = (att.fineMs ?? origTot).toDouble();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Etichetta('Taglia audio'),
              const SizedBox(height: 6),
              const Text('L\'originale resta sul telefono: il taglio si può togliere rimettendo tutto l\'intervallo.'),
              RangeSlider(
                min: 0,
                max: origTot.toDouble(),
                values: RangeValues(ini, math.min(fin, origTot.toDouble())),
                onChanged: (v) => set(() {
                  ini = v.start;
                  fin = v.end;
                }),
              ),
              Text('Da ${durata(ini.round())} a ${durata(fin.round())}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Principale(testo: 'Taglia', icona: Icons.content_cut, onTap: () => Navigator.pop(c, true)),
            ]),
          ),
        ),
      ),
    );
    if (ok != true) return;
    final senzaFine = (origTot - fin) < 500;
    await db.taglia(_n!.id, ini.round(), senzaFine ? null : fin.round());
    await db.aggiornaNota(_n!.id, {'durata_ms': fin.round() - ini.round()});
    await _carica();
    await _preparaAudio();
  }

  Future<void> _cestina() async {
    final ok = await conferma(context, 'Sposta nel cestino', '«${_n!.titolo}» va nel cestino e puoi ripristinarla.', si: 'Sposta');
    if (!ok) return;
    await db.cestina(_n!.id);
    unawaited(cloud.aggiornaNote());
    if (mounted) Navigator.pop(context);
  }

  String _testoIntero(Nota n) {
    final b = StringBuffer('${n.titolo}\n\n');
    for (final r in _ria) {
      for (final s in r.sezioni) {
        b.writeln(s.titolo.toUpperCase());
        for (final x in s.righe) {
          b.writeln('- $x');
        }
        b.writeln();
      }
    }
    if (_seg.isNotEmpty) {
      b.writeln('TESTO\n');
      for (final s in _seg) {
        b.writeln('[${durata(s.inizioMs, lunga: true)}] ${s.chi}: ${s.testo}');
        if (s.traduzione != null) b.writeln('    ${s.traduzione}');
      }
    }
    return b.toString();
  }

  Future<void> _condividi() async {
    final n = _n!;
    final testo = _testoIntero(n);
    Future<void> prova(Future<void> Function() f) async {
      try {
        await f();
      } catch (e) {
        if (mounted) avviso(context, '$e');
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Etichetta('Condividi'),
            const SizedBox(height: 10),
            Principale(
              testo: 'Crea un link con DiGiShare',
              icona: Icons.link,
              onTap: () {
                Navigator.pop(c);
                prova(_link);
              },
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Secondario(
                  testo: 'Copia il testo',
                  icona: Icons.copy,
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: testo));
                    if (c.mounted) Navigator.pop(c);
                    if (mounted) avviso(context, 'Testo copiato');
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Secondario(
                  testo: 'Invia a un\'app',
                  icona: Icons.send_outlined,
                  onTap: () {
                    Navigator.pop(c);
                    prova(() => SharePlus.instance.share(ShareParams(text: testo, subject: n.titolo)));
                  },
                ),
              ),
            ]),
            const SizedBox(height: 12),
            const Text('Word, PDF e Markdown si salvano da DiGiShare.', style: TextStyle(fontSize: 14.5)),
          ]),
        ),
      ),
    );
  }

  Future<void> _link() async {
    final c = cloud.client;
    if (c == null) throw 'Collega prima DiGiShare in Impostazioni.';
    if (_n!.stato != Stato.caricata && _n!.stato != Stato.pronta) throw 'Prima carica la nota in DiGiShare.';
    var giorni = 7;
    var scarica = false;
    final email = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('Crea un link'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Scade dopo', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, children: [
              for (final (g, t) in const [(1, '1 giorno'), (7, '7 giorni'), (30, '30 giorni'), (0, 'Mai')]) Chip2(t, acceso: giorni == g, onTap: () => set(() => giorni = g)),
            ]),
            const SizedBox(height: 10),
            Row(children: [const Expanded(child: Text('Si può scaricare')), Switch(value: scarica, onChanged: (v) => set(() => scarica = v))]),
            TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Solo per queste email (facoltativo)', hintText: 'a@x.ch, b@y.ch')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annulla', style: TextStyle(color: kInk))),
            TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Crea', style: TextStyle(color: kInk, fontWeight: FontWeight.w700))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final destinatari = email.text.split(RegExp(r'[,;\s]+')).where((e) => e.isNotEmpty).toList();
    final url = await c.creaLink(Cloud.nomeFile(_n!, 0), scadenza: giorni, scarica: scarica, email: destinatari);
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) avviso(context, 'Link copiato: $url');
  }

  /// La correzione è già sul telefono: qui si porta in DiGiShare e si dice se non ci è arrivata.
  Future<void> _suDiGiShare(Future<bool> Function() manda) async {
    final n = _n!;
    if (n.esempio || n.stato != Stato.pronta) return;
    try {
      if (!await manda() && mounted && cloud.collegato) avviso(context, 'Salvato solo sul telefono: questa nota non è in DiGiShare.');
    } catch (e) {
      if (mounted) avviso(context, 'Salvato sul telefono, non in DiGiShare: $e');
    }
  }

  /// Il file audio alle altre app di Android: quello intero, anche se la nota è tagliata; le note unite mandano tutti i pezzi.
  Future<void> _condividiAudio() async {
    try {
      final file = [for (final x in await db.parti(_n!.id)) if (File(x.percorso).existsSync()) XFile(x.percorso)];
      if (file.isEmpty) throw 'L\'audio non è più sul telefono.';
      await SharePlus.instance.share(ShareParams(files: file, subject: _n!.titolo));
    } catch (e) {
      if (mounted) avviso(context, '$e');
    }
  }

  void _menu() => showModalBottomSheet<void>(
        context: context,
        builder: (c) {
          ListTile voce(IconData i, String t, VoidCallback f) => ListTile(
                leading: Icon(i),
                title: Text(t),
                onTap: () {
                  Navigator.pop(c);
                  f();
                },
              );
          return SafeArea(
            child: ListView(shrinkWrap: true, children: [
              voce(Icons.edit_outlined, 'Rinomina', _rinomina),
              voce(Icons.drive_file_move_outlined, 'Sposta in una cartella', _sposta),
              voce(Icons.content_cut, 'Taglia audio', _taglia),
              voce(Icons.ios_share, 'Condividi', _condividi),
              if (!_n!.esempio) voce(Icons.audio_file_outlined, 'Condividi audio', _condividiAudio),
              if (_n!.stato == Stato.daInviare)
                voce(Icons.send, 'Invia', () async {
                  final rete = await cloud.reteConsentita();
                  await cloud.confermaInvio(_n!.id);
                  if (!mounted) return;
                  avviso(context, !cloud.collegato ? 'Parte quando colleghi DiGiShare in Impostazioni.' : (rete ? 'Nota in invio' : 'Parte appena c\'è il Wi-Fi.'));
                  _carica();
                }),
              if (!_n!.esempio && (_n!.stato == Stato.registrata || _n!.stato == Stato.caricamento))
                voce(Icons.cloud_upload_outlined, 'Carica in DiGiShare adesso', () async {
                  try {
                    await cloud.inviaNota(_n!);
                    if (mounted) avviso(context, 'Nota in DiGiShare');
                  } catch (e) {
                    if (mounted) avviso(context, '$e');
                  }
                  _carica();
                }),
              if (!_n!.esempio && _n!.stato == Stato.pronta && _parti.isNotEmpty && _parti.every((x) => x.tusUrl != null))
                voce(Icons.refresh, 'Rifai trascrizione', () async {
                  final ok = await conferma(context, 'Rifare la nota?', 'Trascrizione e riassunto si rifanno da capo: le correzioni al testo si perdono.', si: 'Rifai');
                  if (!ok) return;
                  try {
                    await cloud.rifai(_n!);
                    if (mounted) avviso(context, 'DiGiShare la sta rifacendo');
                  } catch (e) {
                    if (mounted) avviso(context, '$e');
                  }
                }),
              voce(Icons.delete_outline, 'Sposta nel cestino', _cestina),
            ]),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final n = _n;
    if (n == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: Barra(titolo: n.titolo, azioni: [
        IconButton(icon: const Icon(Icons.ios_share), tooltip: 'Condividi', onPressed: _condividi),
        IconButton(icon: const Icon(Icons.more_vert), tooltip: 'Altro', onPressed: _menu),
      ]),
      body: Column(children: [
        if (!n.appuntamento) Expanded(child: _testo(n)),
        if (n.appuntamento) Material(
          color: kG1,
          child: TabBar(
            controller: _tab,
            labelColor: kInk,
            unselectedLabelColor: kInk,
            indicatorColor: kRosa,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            dividerColor: kFilo2,
            tabs: const [Tab(text: 'Riassunto'), Tab(text: 'Testo'), Tab(text: 'Mappa'), Tab(text: 'Chiedi')],
          ),
        ),
        if (n.appuntamento) Expanded(
          child: TabBarView(controller: _tab, children: [
            _riassunto(n),
            _testo(n),
            _mappa(n),
            ChiediVista(nota: n.id, incorporata: true),
          ]),
        ),
        _lettore(n),
      ]),
    );
  }

  Widget _inAttesa(Nota n, String cosa) {
    final (titolo, testo) = switch (n.stato) {
      Stato.caricata => ('In sincronizzazione', '$cosa si sta preparando in DiGiShare e arriva qui da solo.'),
      Stato.caricamento => ('Invio in corso', 'Appena la nota è in DiGiShare, da lì parte il resto.'),
      Stato.daInviare => ('Da inviare', 'È solo sul telefono. $cosa si fa quando premi Invia dai tre puntini in alto.'),
      _ => ('L\'audio è al sicuro sul telefono', '$cosa si fa in DiGiShare. Collegala in Impostazioni e carica la nota.'),
    };
    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: kG1, borderRadius: BorderRadius.circular(8), border: Border.all(color: kFilo2)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titolo, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(testo),
        ]),
      ),
      if (_segni.isNotEmpty) ...[const SizedBox(height: 16), _elencoSegni()],
    ]);
  }

  Widget _elencoSegni() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Etichetta('Momenti segnati'),
        const SizedBox(height: 8),
        Elenco(figli: [
          for (final s in _segni)
            ListTile(
              dense: true,
              leading: s.tipo == 'foto' && s.percorso != null && File(s.percorso!).existsSync()
                  ? ClipRRect(borderRadius: BorderRadius.circular(5), child: Image.file(File(s.percorso!), width: 40, height: 40, fit: BoxFit.cover, cacheWidth: 120))
                  : Icon(s.tipo == 'testo' ? Icons.title : (s.tipo == 'foto' ? Icons.photo_camera_outlined : Icons.flag_outlined)),
              title: Text(s.testo.isEmpty ? (s.tipo == 'foto' ? 'Foto' : 'Momento segnato') : s.testo, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              subtitle: Text(durata(s.ms), style: const TextStyle(fontSize: 13.5)),
              onTap: () => _vai(s.ms),
            ),
        ]),
      ]);

  Widget _riassunto(Nota n) {
    if (_ria.isEmpty) return _inAttesa(n, 'Il riassunto');
    final r = _ria[_riaScelto];
    return ListView(padding: const EdgeInsets.all(14), children: [
      if (n.esempio) ...[_marcaEsempio(), const SizedBox(height: 10)],
      if (_ria.length > 1)
        SizedBox(
          height: 36,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (var i = 0; i < _ria.length; i++) Padding(padding: const EdgeInsets.only(right: 6), child: Chip2(_ria[i].modello, acceso: i == _riaScelto, onTap: () => setState(() => _riaScelto = i))),
          ]),
        ),
      for (final s in r.sezioni) ...[
        const SizedBox(height: 14),
        Etichetta(s.titolo),
        const SizedBox(height: 6),
        for (var i = 0; i < s.righe.length; i++)
          Builder(builder: (_) {
            // Dalla riga all'audio: la riga dice dove se ne parla. Se quel punto è stato tagliato, la riga resta senza orario.
            final ms = s.ms?[i];
            final vale = ms != null && ms >= 0 && (n.durataMs <= 0 || ms <= n.durataMs);
            return InkWell(
              onTap: vale ? () => _vai(ms) : null,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('•  ', style: TextStyle(fontSize: 15)),
                  Expanded(child: s.ms == null ? SelectableText(s.righe[i], style: const TextStyle(fontSize: 15)) : Text(s.righe[i], style: const TextStyle(fontSize: 15))),
                  if (vale) Text('  ${durata(ms)}', style: const TextStyle(fontSize: 13.5)),
                ]),
              ),
            );
          }),
      ],
      const SizedBox(height: 12),
      Row(children: [
        const Text('Ti è utile?', style: TextStyle(fontSize: 14.5)),
        IconButton(isSelected: _voto == true, icon: Icon(_voto == true ? Icons.thumb_up : Icons.thumb_up_outlined, size: 20), tooltip: 'Sì', onPressed: () => _vota(r, true)),
        IconButton(isSelected: _voto == false, icon: Icon(_voto == false ? Icons.thumb_down : Icons.thumb_down_outlined, size: 20), tooltip: 'No', onPressed: () => _vota(r, false)),
      ]),
      if (_segni.isNotEmpty) ...[const SizedBox(height: 6), _elencoSegni()],
    ]);
  }

  Future<void> _vota(Riassunto r, bool si) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('voto_${r.id}', si);
    if (mounted) setState(() => _voto = si);
  }

  Widget _marcaEsempio() => Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(gradient: kTenue, borderRadius: BorderRadius.circular(8), border: Border.all(color: kRosa)),
        child: const Text('Nota di esempio: serve a provare l\'app, non ha audio. Puoi cancellarla.', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
      );

  Future<void> _trovaSostituisci() async {
    final da = TextEditingController(), a = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Trova e sostituisci'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: da, autofocus: true, decoration: const InputDecoration(labelText: 'Trova')),
          const SizedBox(height: 10),
          TextField(controller: a, decoration: const InputDecoration(labelText: 'Sostituisci con')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annulla', style: TextStyle(color: kInk))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sostituisci tutto', style: TextStyle(color: kInk, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true) return;
    final x = await db.sostituisci(_n!.id, da.text, a.text);
    if (mounted) avviso(context, x == 0 ? 'Non l\'ho trovato' : 'Cambiate $x frasi');
    if (x > 0) await _suDiGiShare(() => cloud.correggi(_n!, {'sostituisci': {'da': da.text, 'a': a.text}}));
    _carica();
  }

  Future<void> _nomi() async {
    final tutti = _seg.map((s) => s.chi).toSet().toList();
    final voci = (await db.lista('voce')).map((m) => m['nome'] as String).toList();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(14), children: [
          const Etichetta('Nomi di chi parla'),
          const SizedBox(height: 8),
          for (final x in tutti)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(x),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () async {
                Navigator.pop(c);
                final nuovo = voci.isEmpty ? await chiediTesto(context, 'Chi è?', iniziale: x, etichetta: 'Nome') : await _sceltaNome(x, voci);
                if (nuovo == null) return;
                await db.rinominaChi(_n!.id, x, nuovo);
                await db.aggiungiLista('voce', 'nome', nuovo);
                await _suDiGiShare(() => cloud.correggi(_n!, {'rinomina': {'da': x, 'a': nuovo}}));
                _carica();
              },
            ),
        ]),
      ),
    );
  }

  Future<String?> _sceltaNome(String attuale, List<String> voci) => showModalBottomSheet<String>(
        context: context,
        builder: (c) => SafeArea(
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(14), children: [
            Etichetta('Chi è $attuale?'),
            const SizedBox(height: 8),
            for (final v in voci) ListTile(leading: const Icon(Icons.record_voice_over_outlined), title: Text(v), onTap: () => Navigator.pop(c, v)),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Scrivi un nome nuovo'),
              onTap: () async {
                final t = await chiediTesto(c, 'Chi è?', iniziale: attuale, etichetta: 'Nome');
                if (c.mounted) Navigator.pop(c, t);
              },
            ),
          ]),
        ),
      );

  Widget _testo(Nota n) {
    if (_seg.isEmpty) return _inAttesa(n, 'Il testo');
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Row(children: [
          Expanded(child: Secondario(testo: 'Cerca e sostituisci', alto: 38, onTap: _trovaSostituisci)),
          const SizedBox(width: 8),
          Expanded(child: Secondario(testo: 'Nomi di chi parla', alto: 38, onTap: _nomi)),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          itemCount: _seg.length,
          itemBuilder: (_, i) {
            final s = _seg[i];
            final acceso = s.id == _attivo;
            final primo = s.chi.isEmpty ? '?' : s.chi.characters.first.toUpperCase();
            return InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _vai(s.inizioMs),
              onLongPress: () async {
                final t = await chiediTesto(context, 'Modifica la frase', iniziale: s.testo, righe: 5);
                if (t == null) return;
                await db.modificaSegmento(s.id, t);
                await _suDiGiShare(() => cloud.correggiFrase(_n!, s, t));
                _carica();
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(gradient: acceso ? kMarchio : null, borderRadius: BorderRadius.circular(6)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    CircleAvatar(radius: 11, backgroundColor: s.chi.hashCode.isEven ? kRosa : kViola, child: Text(primo, style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w700))),
                    const SizedBox(width: 6),
                    Flexible(child: Text(s.chi, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                    const SizedBox(width: 6),
                    Text(durata(s.inizioMs, lunga: true), style: const TextStyle(fontSize: 13)),
                  ]),
                  const SizedBox(height: 3),
                  Text(s.testo, style: const TextStyle(fontSize: 15, height: 1.35)),
                  if (s.traduzione != null) Text(s.traduzione!, style: const TextStyle(fontSize: 15, height: 1.35, fontStyle: FontStyle.italic)),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _mappa(Nota n) {
    if (_ria.isEmpty) return _inAttesa(n, 'La mappa mentale');
    final rami = _ria[_riaScelto].sezioni;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Expanded(
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: kG1, borderRadius: BorderRadius.circular(8), border: Border.all(color: kFilo)),
            child: InteractiveViewer(minScale: .5, maxScale: 4, child: MappaMentale(titolo: n.titolo, rami: rami)),
          ),
        ),
      ]),
    );
  }

  Widget _lettore(Nota n) {
    if (_durate.isEmpty) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(14, 10, 14, 10 + MediaQuery.paddingOf(context).bottom),
        color: kG1,
        child: Text(n.esempio ? 'L\'esempio non ha audio.' : 'Audio non disponibile sul telefono.', style: const TextStyle(fontSize: 14)),
      );
    }
    return StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      builder: (_, st) => StreamBuilder<Duration>(
        stream: _player.positionStream,
        builder: (_, __) {
          final tot = _totale <= 0 ? 1 : _totale;
          final pos = _posizione.clamp(0, tot);
          final suona = st.data?.playing ?? false;
          return Container(
            padding: EdgeInsets.fromLTRB(8, 6, 8, 6 + MediaQuery.paddingOf(context).bottom),
            decoration: const BoxDecoration(color: kG1, border: Border(top: BorderSide(color: kFilo2))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                IconButton(
                  icon: Icon(suona ? Icons.pause : Icons.play_arrow),
                  iconSize: 28,
                  tooltip: suona ? 'Pausa' : 'Ascolta',
                  onPressed: () => suona ? _player.pause() : _player.play(),
                ),
                Expanded(
                  child: SliderTheme(
                    data: const SliderThemeData(trackHeight: 5, activeTrackColor: kRosa, thumbColor: kInk, inactiveTrackColor: kFilo2, overlayShape: RoundSliderOverlayShape(overlayRadius: 14)),
                    child: Slider(value: pos.toDouble(), max: tot.toDouble(), onChanged: (v) => _vai(v.round())),
                  ),
                ),
                Text('${durata(pos)} / ${durata(tot)}', style: const TextStyle(fontSize: 13, fontFeatures: [ui.FontFeature.tabularFigures()])),
                const SizedBox(width: 4),
              ]),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  Chip2('${_vel == _vel.roundToDouble() ? _vel.toInt() : _vel}×', onTap: () {
                    const v = [1.0, 1.25, 1.5, 2.0, 0.75];
                    final prossima = v[(v.indexOf(_vel) + 1) % v.length];
                    _player.setSpeed(prossima);
                    setState(() => _vel = prossima);
                  }),
                  const SizedBox(width: 6),
                  Chip2('−15 s', onTap: () => _vai(math.max(0, pos - 15000))),
                  const SizedBox(width: 6),
                  Chip2('+15 s', onTap: () => _vai(math.min(tot, pos + 15000))),
                  const SizedBox(width: 6),
                  Chip2('Voce più forte', acceso: _forte, onTap: _voceForte),
                ]),
              ),
            ]),
          );
        },
      ),
    );
  }

  Future<void> _voceForte() async {
    try {
      // In decibel: 0.8 non si sentiva. 12 raddoppia abbondantemente il volume percepito.
      await _enh.setTargetGain(_forte ? 0 : 12);
      await _enh.setEnabled(!_forte);
      setState(() => _forte = !_forte);
    } catch (e) {
      avviso(context, 'Non disponibile su questo telefono');
    }
  }
}

/// La mappa: centro col titolo, un ramo per sezione, foglie per le righe. Si disegna da sola dalle sezioni.
class MappaMentale extends StatelessWidget {
  const MappaMentale({super.key, required this.titolo, required this.rami});
  final String titolo;
  final List<Sezione> rami;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (_, v) {
        final w = v.maxWidth, h = v.maxHeight;
        final c = Offset(w / 2, h / 2);
        final nodi = <(Offset, String, int)>[];
        final linee = <(Offset, Offset)>[];
        // Un'ellisse larga quanto lo schermo; ogni foglia ha lo stesso spicchio, il ramo sta in mezzo alle sue.
        final rx = math.max(40.0, w / 2 - 58), ry = math.max(40.0, h / 2 - 26);
        final foglie = rami.fold<int>(0, (a, r) => a + math.max(1, math.min(4, r.righe.length)));
        final passo = 2 * math.pi / math.max(1, foglie);
        var ang = -math.pi / 2 - passo / 2;
        for (final r in rami) {
          final righe = r.righe.take(4).toList();
          final quante = math.max(1, righe.length);
          final medio = ang + passo * (quante + 1) / 2;
          // Il ramo non deve finire sopra il titolo al centro: almeno 44 sopra o sotto.
          final dy = math.sin(medio) * ry * .52;
          final b = c + Offset(math.cos(medio) * rx * .52, dy.abs() < 44 ? (dy < 0 ? -44 : 44) : dy);
          linee.add((c, b));
          nodi.add((b, r.titolo, 1));
          for (var k = 0; k < righe.length; k++) {
            final a2 = ang + passo * (k + 1);
            final q = c + Offset(math.cos(a2) * rx, math.sin(a2) * ry);
            linee.add((b, q));
            nodi.add((q, righe[k], 2));
          }
          ang += passo * quante;
        }
        return Container(
          color: kG1,
          width: w,
          height: h,
          child: Stack(children: [
            Positioned.fill(child: CustomPaint(painter: _Fili(linee))),
            Positioned(left: c.dx - 62, top: c.dy - 24, width: 124, height: 48, child: _Nodo(titolo, 0)),
            for (final (o, t, l) in nodi) Positioned(left: o.dx - (l == 1 ? 46 : 54), top: o.dy - (l == 1 ? 15 : 22), width: l == 1 ? 92 : 108, height: l == 1 ? 30 : 44, child: _Nodo(t, l)),
          ]),
        );
      });
}

class _Nodo extends StatelessWidget {
  const _Nodo(this.t, this.livello);
  final String t;
  final int livello;
  @override
  Widget build(BuildContext context) => Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(gradient: livello == 0 ? kMarchio : null, color: livello == 0 ? null : (livello == 1 ? kG3 : kG2), borderRadius: BorderRadius.circular(6), border: livello == 0 ? null : Border.all(color: kFilo2)),
        child: Text(t, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: livello == 2 ? 11 : 12.5, height: 1.15, fontWeight: livello == 2 ? FontWeight.w500 : FontWeight.w700, color: livello == 0 ? Colors.white : kInk)),
      );
}

class _Fili extends CustomPainter {
  _Fili(this.l);
  final List<(Offset, Offset)> l;
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = const Color(0xB3E0306A)
      ..strokeWidth = 1.2;
    for (final (a, b) in l) {
      c.drawLine(a, b, p);
    }
  }

  @override
  bool shouldRepaint(_Fili o) => o.l != l;
}
