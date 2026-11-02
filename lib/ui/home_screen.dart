import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../db.dart';
import '../digishare.dart';
import '../registratore.dart';
import '../theme.dart';
import 'chiedi_screen.dart';
import 'impostazioni_screen.dart';
import 'nota_screen.dart';
import 'registra_screen.dart';

const kIconeCartella = [Icons.folder_outlined, Icons.work_outline, Icons.person_outline, Icons.lightbulb_outline, Icons.home_outlined, Icons.star_outline, Icons.description_outlined, Icons.gavel_outlined];

/// Copia un audio dentro l'app e ne fa una nota.
Future<int> importaFile(String percorso, {String? nome}) async {
  final dir = await Registratore.cartellaAudio();
  final ext = p.extension(percorso).isEmpty ? '.m4a' : p.extension(percorso);
  final dest = p.join(dir.path, 'importato-${DateTime.now().microsecondsSinceEpoch}$ext');
  await File(percorso).copy(dest);
  final titolo = p.basenameWithoutExtension(nome ?? percorso);
  final id = await db.nuovaNota(titolo: titolo, tipo: 'appuntamento', stato: Stato.registrata);
  await db.aggiungiParte(id, dest);
  return id;
}

class Principale2 extends StatefulWidget {
  const Principale2({super.key});
  @override
  State<Principale2> createState() => _Principale2State();
}

class _Principale2State extends State<Principale2> {
  int _sel = 0;
  final _elenco = GlobalKey<_NoteVistaState>();
  final _chiave = GlobalKey<ScaffoldState>();
  StreamSubscription<List<SharedMediaFile>>? _cond;
  int? _cartella;
  String _nomeCartella = 'Tutte';

  @override
  void initState() {
    super.initState();
    cloud.noteCambiate.addListener(_ricarica);
    _cond = ReceiveSharingIntent.instance.getMediaStream().listen(_ricevuti);
    ReceiveSharingIntent.instance.getInitialMedia().then((f) {
      _ricevuti(f);
      ReceiveSharingIntent.instance.reset();
    });
  }

  @override
  void dispose() {
    cloud.noteCambiate.removeListener(_ricarica);
    _cond?.cancel();
    super.dispose();
  }

  void _ricarica() => _elenco.currentState?.carica();

  Future<void> _ricevuti(List<SharedMediaFile> f) async {
    for (final x in f) {
      if (x.path.isEmpty || !await File(x.path).exists()) continue;
      await importaFile(x.path);
    }
    if (f.isEmpty || !mounted) return;
    _elenco.currentState?.carica();
    avviso(context, 'Audio importato');
    cloud.inviaTutto();
  }

  Future<void> importa() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.audio, allowMultiple: true);
    if (r == null) return;
    for (final f in r.files) {
      if (f.path != null) await importaFile(f.path!, nome: f.name);
    }
    if (!mounted) return;
    _elenco.currentState?.carica();
    avviso(context, r.files.length == 1 ? 'Audio importato' : '${r.files.length} audio importati');
    cloud.inviaTutto();
  }

  void _scegliCartella(int? id, String nome) {
    setState(() {
      _cartella = id;
      _nomeCartella = nome;
      _sel = 0;
    });
    _elenco.currentState?.carica();
  }

  Future<void> _cerca() async {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const CercaScreen()));
    _elenco.currentState?.carica();
  }

  @override
  Widget build(BuildContext context) {
    final viste = [
      NoteVista(key: _elenco, cartella: _cartella, nomeCartella: _nomeCartella, importa: importa),
      const ChiediVista(),
      const SizedBox.shrink(),
      const SizedBox.shrink(),
      const ImpostazioniVista(),
    ];
    return Scaffold(
      key: _chiave,
      appBar: Barra(marchio: true, menu: () => _chiave.currentState?.openDrawer()),
      drawer: CartelleMenu(
        attuale: _cartella,
        onScelta: (id, nome) {
          Navigator.pop(context);
          _scegliCartella(id, nome);
        },
        ricarica: () => _elenco.currentState?.carica(),
      ),
      body: IndexedStack(index: _sel, children: viste),
      bottomNavigationBar: _nav(),
    );
  }

  Widget _nav() {
    Widget voce(int i, IconData ic, String t, {VoidCallback? azione}) {
      final on = _sel == i;
      return Expanded(
        child: InkWell(
          onTap: azione ?? () => setState(() => _sel = i),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                decoration: BoxDecoration(gradient: on ? kMarchio : null, borderRadius: BorderRadius.circular(8)),
                child: Icon(ic, size: 23, color: on ? Colors.white : kInk),
              ),
              const SizedBox(height: 2),
              Text(t, maxLines: 1, style: TextStyle(fontSize: 12, fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
            ]),
          ),
        ),
      );
    }

    return ListenableBuilder(
      listenable: registratore,
      builder: (_, __) => Container(
        decoration: const BoxDecoration(color: kG1, border: Border(top: BorderSide(color: kFilo2))),
        child: SafeArea(
          top: false,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            voce(0, Icons.folder_outlined, 'Note'),
            voce(1, Icons.chat_bubble_outline, 'Chiedi'),
            SizedBox(
              width: 76,
              height: 58,
              child: OverflowBox(
                maxHeight: 84,
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Material(
                    shape: const CircleBorder(side: BorderSide(color: kContorno, width: 3)),
                    clipBehavior: Clip.antiAlias,
                    child: Ink(
                      width: 66,
                      height: 66,
                      decoration: BoxDecoration(gradient: registratore.attivo ? kBarra : kMarchio),
                      child: InkWell(
                        onTap: () async {
                          await nuovaRegistrazione(context, importa: importa, cartella: _cartella != null && _cartella! > 0 ? _cartella : null);
                          _elenco.currentState?.carica();
                        },
                        child: Icon(registratore.attivo ? Icons.graphic_eq : Icons.mic, color: Colors.white, size: 32, semanticLabel: 'Registra'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            voce(3, Icons.search, 'Cerca', azione: _cerca),
            voce(4, Icons.settings_outlined, 'Impost.'),
          ]),
        ),
      ),
    );
  }
}

/// Cancella per sempre la nota e i suoi file.
Future<void> eliminaNota(Nota n) async {
  for (final f in await db.eliminaDefinitivamente(n.id)) {
    // Dopo un'unione lo stesso file può servire a un'altra nota: resta se qualcuno lo usa ancora.
    final usato = await db.d.query('parte', where: 'percorso=?', whereArgs: [f], limit: 1);
    if (usato.isEmpty && await File(f).exists()) await File(f).delete();
  }
}

Widget rigaNota(BuildContext context, Nota n, {VoidCallback? onTap, VoidCallback? onLong, bool scelta = false, String? sotto, Widget? destra}) {
  final colore = n.stato == Stato.pronta ? kVerde : (n.stato == Stato.caricamento ? kPuntoGiallo : kFilo2);
  return InkWell(
    onTap: onTap,
    onLongPress: onLong,
    child: Container(
      decoration: BoxDecoration(gradient: scelta ? kMarchio : null),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(gradient: n.appuntamento ? kTenue : null, color: n.appuntamento ? null : kG2, borderRadius: BorderRadius.circular(6)),
          child: Icon(scelta ? Icons.check : (n.appuntamento ? Icons.graphic_eq : Icons.mic_none), size: 23),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(n.titolo, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            Text(sotto ?? '${DateFormat('HH:mm').format(n.creata)} · ${durataBreve(n.durataMs)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)),
          ]),
        ),
        if (destra != null)
          destra
        else ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), border: Border.all(color: colore)),
            child: Text(n.esempio ? 'Esempio' : Stato.etichetta(n.stato), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ]),
    ),
  );
}

String giornoDi(DateTime d) {
  final oggi = DateTime.now();
  final a = DateTime(oggi.year, oggi.month, oggi.day), b = DateTime(d.year, d.month, d.day);
  final diff = a.difference(b).inDays;
  if (diff == 0) return 'Oggi';
  if (diff == 1) return 'Ieri';
  return DateFormat(d.year == oggi.year ? 'd MMMM' : 'd MMMM y', 'it').format(d);
}

class NoteVista extends StatefulWidget {
  const NoteVista({super.key, this.cartella, required this.nomeCartella, required this.importa});
  final int? cartella;
  final String nomeCartella;
  final VoidCallback importa;
  @override
  State<NoteVista> createState() => _NoteVistaState();
}

class _NoteVistaState extends State<NoteVista> {
  List<Nota> _n = [];
  String? _tipo;
  String _ordine = 'creata';
  bool _crescente = false;
  final _scelte = <int>{};

  @override
  void initState() {
    super.initState();
    carica();
    cloud.addListener(carica);
    registratore.addListener(_regCambio);
  }

  bool _eraAttivo = false;
  void _regCambio() {
    if (_eraAttivo && !registratore.attivo) carica();
    _eraAttivo = registratore.attivo;
  }

  @override
  void dispose() {
    cloud.removeListener(carica);
    registratore.removeListener(_regCambio);
    super.dispose();
  }

  @override
  void didUpdateWidget(NoteVista o) {
    super.didUpdateWidget(o);
    if (o.cartella != widget.cartella) carica();
  }

  Future<void> carica() async {
    final n = await db.note(cartella: widget.cartella, tipo: _tipo, ordine: _ordine, crescente: _crescente);
    if (mounted) setState(() => _n = n);
  }

  Future<void> _apri(Nota n) async {
    if (_scelte.isNotEmpty) {
      setState(() => _scelte.contains(n.id) ? _scelte.remove(n.id) : _scelte.add(n.id));
      return;
    }
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => NotaScreen(id: n.id)));
    carica();
  }

  void _ordina() => showModalBottomSheet<void>(
        context: context,
        builder: (c) {
          Widget v(String t, String o, bool cr) => ListTile(
                title: Text(t),
                trailing: _ordine == o && _crescente == cr ? const Icon(Icons.check) : null,
                onTap: () {
                  Navigator.pop(c);
                  _ordine = o;
                  _crescente = cr;
                  carica();
                },
              );
          return SafeArea(
            child: ListView(shrinkWrap: true, children: [
              v('Più recenti', 'creata', false),
              v('Più vecchie', 'creata', true),
              v('Titolo', 'titolo', true),
              v('Più lunghe', 'durata', false),
            ]),
          );
        },
      );

  Future<void> _azioneMultipla(String a) async {
    final scelte = _n.where((n) => _scelte.contains(n.id)).toList();
    switch (a) {
      case 'unisci':
        if (scelte.length < 2) {
          avviso(context, 'Scegli almeno due note');
          return;
        }
        final tot = scelte.fold<int>(0, (x, n) => x + n.durataMs);
        if (tot > 50 * 3600 * 1000) {
          avviso(context, 'Si possono unire al massimo 50 ore');
          return;
        }
        final t = await chiediTesto(context, 'Unisci ${scelte.length} note', iniziale: scelte.last.titolo, etichetta: 'Titolo della nota unita', si: 'Unisci');
        if (t == null) return;
        await db.unisci(scelte, t);
        if (mounted) avviso(context, 'Note unite. Gli originali sono nel cestino.');
      case 'sposta':
        final cc = await db.cartelle();
        if (!mounted) return;
        final r = await showModalBottomSheet<int>(
          context: context,
          builder: (c) => SafeArea(
            child: ListView(shrinkWrap: true, children: [
              ListTile(leading: const Icon(Icons.inbox_outlined), title: const Text('Nessuna cartella'), onTap: () => Navigator.pop(c, -1)),
              for (final x in cc) ListTile(leading: Icon(kIconeCartella[x.icona % kIconeCartella.length]), title: Text(x.nome), onTap: () => Navigator.pop(c, x.id)),
            ]),
          ),
        );
        if (r == null) return;
        await db.sposta(_scelte.toList(), r == -1 ? null : r);
      case 'cestina':
        final ok = await conferma(context, 'Sposta nel cestino', '${scelte.length} note vanno nel cestino e puoi ripristinarle.', si: 'Sposta');
        if (!ok) return;
        for (final n in scelte) {
          await db.cestina(n.id);
        }
        unawaited(cloud.aggiornaNote());
    }
    setState(_scelte.clear);
    carica();
  }

  @override
  Widget build(BuildContext context) {
    final righe = <Widget>[];
    String? giorno;
    final gruppo = <Widget>[];
    void chiudi() {
      if (gruppo.isEmpty) return;
      righe.add(Padding(padding: const EdgeInsets.only(top: 14, bottom: 8), child: Etichetta(giorno!)));
      righe.add(Elenco(figli: List.of(gruppo)));
      gruppo.clear();
    }

    for (final n in _n) {
      final g = _ordine == 'creata' ? giornoDi(n.creata) : (_ordine == 'titolo' ? 'Per titolo' : 'Per durata');
      if (g != giorno) {
        chiudi();
        giorno = g;
      }
      gruppo.add(rigaNota(context, n, scelta: _scelte.contains(n.id), onTap: () => _apri(n), onLong: () => setState(() => _scelte.add(n.id))));
    }
    chiudi();

    return Column(children: [
      Expanded(
        child: RefreshIndicator(
          onRefresh: () async {
            await carica();
            unawaited(cloud.inviaTutto());
          },
          child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 16), children: [
            if (widget.nomeCartella != 'Tutte') ...[Etichetta(widget.nomeCartella), const SizedBox(height: 8)],
            Row(children: [
              Expanded(
                child: Wrap(spacing: 6, children: [
                  Chip2('Tutte', acceso: _tipo == null, onTap: () {
                    _tipo = null;
                    carica();
                  }),
                  Chip2('Appuntamenti', acceso: _tipo == 'appuntamento', onTap: () {
                    _tipo = 'appuntamento';
                    carica();
                  }),
                  Chip2('Idee', acceso: _tipo == 'idea', onTap: () {
                    _tipo = 'idea';
                    carica();
                  }),
                ]),
              ),
              IconButton(icon: const Icon(Icons.sort), tooltip: 'Ordina', onPressed: _ordina),
            ]),
            ListenableBuilder(
              listenable: cloud,
              builder: (_, __) => cloud.notaInCorso == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Invio a DiGiShare: ${(cloud.avanzamento * 100).round()}%', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(value: cloud.avanzamento, color: kRosa, backgroundColor: kFilo2, minHeight: 6, borderRadius: BorderRadius.circular(3)),
                      ]),
                    ),
            ),
            ...righe,
            if (_n.isEmpty) ...[
              const SizedBox(height: 40),
              const Text('Ancora nessuna nota.', textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              Secondario(testo: 'Importa un audio', icona: Icons.upload, onTap: widget.importa),
            ],
          ]),
        ),
      ),
      if (_scelte.isNotEmpty)
        Container(
          color: kG2,
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.close), tooltip: 'Annulla scelta', onPressed: () => setState(_scelte.clear)),
            Text('${_scelte.length}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const Spacer(),
            Chip2('Unisci', icona: Icons.merge, onTap: () => _azioneMultipla('unisci')),
            const SizedBox(width: 6),
            Chip2('Sposta', icona: Icons.drive_file_move_outlined, onTap: () => _azioneMultipla('sposta')),
            const SizedBox(width: 6),
            Chip2('Cestino', icona: Icons.delete_outline, onTap: () => _azioneMultipla('cestina')),
          ]),
        ),
    ]);
  }
}

class CartelleMenu extends StatefulWidget {
  const CartelleMenu({super.key, required this.attuale, required this.onScelta, required this.ricarica});
  final int? attuale;
  final void Function(int? id, String nome) onScelta;
  final VoidCallback ricarica;
  @override
  State<CartelleMenu> createState() => _CartelleMenuState();
}

class _CartelleMenuState extends State<CartelleMenu> {
  List<Cartella> _c = [];
  Map<String, int> _n = {};

  @override
  void initState() {
    super.initState();
    _carica();
  }

  Future<void> _carica() async {
    final c = await db.cartelle();
    final n = await db.conteggi();
    if (mounted) {
      setState(() {
        _c = c;
        _n = n;
      });
    }
  }

  Future<void> _edit([Cartella? x]) async {
    final c = TextEditingController(text: x?.nome);
    var icona = x?.icona ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text(x == null ? 'Nuova cartella' : 'Modifica cartella'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Nome')),
            const SizedBox(height: 12),
            Wrap(spacing: 4, runSpacing: 4, children: [
              for (var i = 0; i < kIconeCartella.length; i++)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => set(() => icona = i),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(gradient: icona == i ? kMarchio : null, color: icona == i ? null : kG2, borderRadius: BorderRadius.circular(8)),
                    child: Icon(kIconeCartella[i], color: icona == i ? Colors.white : kInk),
                  ),
                ),
            ]),
          ]),
          actions: [
            if (x != null)
              TextButton(
                onPressed: () async {
                  final si = await conferma(d, 'Elimina cartella', 'La cartella «${x.nome}» sparisce. Le note restano, senza cartella.', si: 'Elimina');
                  if (!si) return;
                  await db.eliminaCartella(x.id);
                  if (d.mounted) Navigator.pop(d, false);
                  widget.onScelta(null, 'Tutte');
                },
                child: const Text('Elimina', style: TextStyle(color: kInk)),
              ),
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annulla', style: TextStyle(color: kInk))),
            TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Salva', style: TextStyle(color: kInk, fontWeight: FontWeight.w700))),
          ],
        ),
      ),
    );
    if (ok == true && c.text.trim().isNotEmpty) {
      if (x == null) {
        await db.nuovaCartella(c.text.trim(), icona);
      } else {
        await db.modificaCartella(x.id, c.text.trim(), icona);
      }
    }
    _carica();
  }

  Widget _voce(IconData i, String t, int n, bool on, VoidCallback f, {VoidCallback? lungo}) => Ink(
        decoration: BoxDecoration(gradient: on ? kMarchio : null),
        child: ListTile(
          dense: true,
          textColor: on ? Colors.white : kInk,
          iconColor: on ? Colors.white : kInk,
          leading: Icon(i),
          title: Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          trailing: Text('$n', style: const TextStyle(fontSize: 14)),
          onTap: f,
          onLongPress: lungo,
        ),
      );

  @override
  Widget build(BuildContext context) => Drawer(
        backgroundColor: kG0,
        shape: const RoundedRectangleBorder(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Barra(marchio: true, indietro: false),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(12), children: [
              Elenco(figli: [
                _voce(Icons.folder_copy_outlined, 'Tutte le note', _n['tutte'] ?? 0, widget.attuale == null, () => widget.onScelta(null, 'Tutte')),
                _voce(Icons.inbox_outlined, 'Non classificate', _n['senza'] ?? 0, widget.attuale == -1, () => widget.onScelta(-1, 'Non classificate')),
              ]),
              const SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Etichetta('Cartelle'), Chip2('+ Nuova', acceso: true, onTap: () => _edit())]),
              const SizedBox(height: 8),
              if (_c.isEmpty)
                const Text('Nessuna cartella. Tieni premuto una cartella per modificarla.', style: TextStyle(fontSize: 14.5))
              else
                Elenco(figli: [
                  for (final x in _c) _voce(kIconeCartella[x.icona % kIconeCartella.length], x.nome, x.conta, widget.attuale == x.id, () => widget.onScelta(x.id, x.nome), lungo: () => _edit(x)),
                ]),
              const SizedBox(height: 14),
              Elenco(figli: [
                _voce(Icons.delete_outline, 'Cestino', _n['cestino'] ?? 0, false, () async {
                  final nav = Navigator.of(context);
                  nav.pop();
                  await nav.push(MaterialPageRoute<void>(builder: (_) => const CestinoScreen()));
                  widget.ricarica();
                }),
              ]),
            ]),
          ),
        ]),
      );
}

class CestinoScreen extends StatefulWidget {
  const CestinoScreen({super.key});
  @override
  State<CestinoScreen> createState() => _CestinoScreenState();
}

class _CestinoScreenState extends State<CestinoScreen> {
  List<Nota> _n = [];

  @override
  void initState() {
    super.initState();
    _carica();
  }

  Future<void> _carica() async {
    final n = await db.cestino();
    if (mounted) setState(() => _n = n);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: Barra(titolo: 'Cestino', azioni: [
          if (_n.isNotEmpty)
            TextButton(
              onPressed: () async {
                final elenco = _n.take(5).map((n) => '• ${n.titolo}').join('\n');
                final ok = await conferma(context, 'Svuota il cestino', 'Cancello per sempre ${_n.length} note con il loro audio. Non si recuperano.\n\n$elenco${_n.length > 5 ? '\n…' : ''}', si: 'Cancella per sempre');
                if (!ok) return;
                for (final n in List.of(_n)) {
                  await eliminaNota(n);
                }
                _carica();
              },
              child: const Text('Svuota', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
        ]),
        body: _n.isEmpty
            ? const Center(child: Text('Il cestino è vuoto.', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)))
            : ListView(padding: const EdgeInsets.all(12), children: [
                const Text('Le note nel cestino non si cancellano da sole.', style: TextStyle(fontSize: 15)),
                const SizedBox(height: 10),
                Elenco(figli: [
                  for (final n in _n)
                    rigaNota(
                      context,
                      n,
                      sotto: '${giornoDi(n.creata)} · ${durataBreve(n.durataMs)}',
                      destra: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          icon: const Icon(Icons.restore),
                          tooltip: 'Ripristina',
                          onPressed: () async {
                            await db.ripristina(n.id);
                            unawaited(cloud.aggiornaNote());
                            _carica();
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_forever_outlined),
                          tooltip: 'Cancella per sempre',
                          onPressed: () async {
                            final ok = await conferma(context, 'Cancella per sempre', '«${n.titolo}» e il suo audio spariscono. Non si recuperano.', si: 'Cancella');
                            if (!ok) return;
                            await eliminaNota(n);
                            _carica();
                          },
                        ),
                      ]),
                    ),
                ]),
              ]),
      );
}

class CercaScreen extends StatefulWidget {
  const CercaScreen({super.key});
  @override
  State<CercaScreen> createState() => _CercaScreenState();
}

class _CercaScreenState extends State<CercaScreen> {
  final _c = TextEditingController();
  List<Risultato> _r = [];
  List<Cartella> _cart = [];
  int? _cartella;
  DateTime? _dal;
  String _periodo = 'Sempre';
  bool _soloTesto = false;
  Timer? _t;
  bool _cercato = false;

  @override
  void initState() {
    super.initState();
    db.cartelle().then((c) {
      if (mounted) setState(() => _cart = c);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _cerca() {
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 250), () async {
      final q = _c.text.trim();
      if (q.isEmpty) {
        setState(() {
          _r = [];
          _cercato = false;
        });
        return;
      }
      final r = await db.cerca(q, cartella: _cartella, dal: _dal, soloConTesto: _soloTesto);
      if (mounted) {
        setState(() {
          _r = r;
          _cercato = true;
        });
      }
    });
  }

  void _periodoProssimo() {
    final oggi = DateTime.now();
    setState(() {
      if (_periodo == 'Sempre') {
        _periodo = 'Quest\'anno';
        _dal = DateTime(oggi.year);
      } else if (_periodo == 'Quest\'anno') {
        _periodo = 'Questo mese';
        _dal = DateTime(oggi.year, oggi.month);
      } else {
        _periodo = 'Sempre';
        _dal = null;
      }
    });
    _cerca();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: Barra(azioni: [
          Expanded(
            flex: 0,
            child: SizedBox(
              width: MediaQuery.sizeOf(context).width - 72,
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: TextField(
                  controller: _c,
                  autofocus: true,
                  onChanged: (_) => _cerca(),
                  style: const TextStyle(color: kContorno, fontSize: 16),
                  cursorColor: kContorno,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    hintText: 'Cerca nelle note',
                    hintStyle: const TextStyle(color: kContorno),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: kContorno, width: 2)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: kContorno, width: 2)),
                  ),
                ),
              ),
            ),
          ),
        ]),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            Chip2(_periodo, acceso: _dal != null, onTap: _periodoProssimo),
            Chip2(_cartella == null ? 'Tutte le cartelle' : _cart.firstWhere((x) => x.id == _cartella, orElse: () => Cartella({'id': 0, 'nome': 'Cartella'})).nome, acceso: _cartella != null, onTap: () async {
              final r = await showModalBottomSheet<int>(
                context: context,
                builder: (c) => SafeArea(
                  child: ListView(shrinkWrap: true, children: [
                    ListTile(title: const Text('Tutte le cartelle'), onTap: () => Navigator.pop(c, -1)),
                    for (final x in _cart) ListTile(title: Text(x.nome), onTap: () => Navigator.pop(c, x.id)),
                  ]),
                ),
              );
              if (r == null) return;
              setState(() => _cartella = r == -1 ? null : r);
              _cerca();
            }),
            Chip2('Solo dentro i testi', acceso: _soloTesto, onTap: () {
              setState(() => _soloTesto = !_soloTesto);
              _cerca();
            }),
          ]),
          const SizedBox(height: 12),
          if (_cercato) Etichetta(_r.length == 1 ? '1 risultato' : '${_r.length} risultati'),
          const SizedBox(height: 8),
          if (_r.isNotEmpty)
            Elenco(figli: [
              for (final x in _r)
                rigaNota(
                  context,
                  x.nota,
                  sotto: x.frase == null ? giornoDi(x.nota.creata) : '«${x.frase}»',
                  onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => NotaScreen(id: x.nota.id, saltaA: x.ms, scheda: x.ms == null ? 0 : 1))),
                ),
            ]),
        ]),
      );
}
