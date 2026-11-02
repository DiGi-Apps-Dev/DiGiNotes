import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db.dart';
import '../digishare.dart';
import '../registratore.dart';
import '../theme.dart';

class ImpostazioniVista extends StatefulWidget {
  const ImpostazioniVista({super.key});
  @override
  State<ImpostazioniVista> createState() => _ImpostazioniVistaState();
}

class _ImpostazioniVistaState extends State<ImpostazioniVista> {
  SharedPreferences? _p;
  int _glo = 0, _voci = 0, _mem = 0;
  Map<String, int> _st = {};

  @override
  void initState() {
    super.initState();
    _carica();
  }

  Future<void> _carica() async {
    final p = await SharedPreferences.getInstance();
    final g = await db.contaLista('glossario');
    final v = await db.contaLista('voce');
    final m = await db.contaLista('memoria');
    final st = await db.statistiche();
    if (mounted) {
      setState(() {
        _p = p;
        _glo = g;
        _voci = v;
        _mem = m;
        _st = st;
      });
    }
  }

  Widget _op(String t, Widget destra, {VoidCallback? onTap, String? sotto}) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t, style: const TextStyle(fontSize: 15)),
                if (sotto != null) Text(sotto, style: const TextStyle(fontSize: 13.5)),
              ]),
            ),
            const SizedBox(width: 10),
            destra,
          ]),
        ),
      );

  Widget _sw(String chiave, bool pred, String t, {String? sotto, Future<bool> Function(bool)? prima}) {
    final v = _p!.getBool(chiave) ?? pred;
    return _op(t, Switch(value: v, onChanged: (n) async {
      if (prima != null && !await prima(n)) return;
      await _p!.setBool(chiave, n);
      setState(() {});
      if (chiave == 'solo_wifi') cloud.inviaTutto();
    }), sotto: sotto);
  }

  Future<bool> _impronta(bool attiva) async {
    if (!attiva) return true;
    final la = LocalAuthentication();
    try {
      if (!await la.isDeviceSupported()) {
        if (mounted) avviso(context, 'Questo telefono non ha il blocco schermo attivo.');
        return false;
      }
      return await la.authenticate(localizedReason: 'Conferma per attivare lo sblocco di DiGiNotes');
    } catch (e) {
      if (mounted) avviso(context, 'Sblocco non attivato: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (p == null) return const SizedBox.shrink();
    final fisso = p.getString('tipo_fisso');
    return ListenableBuilder(
      listenable: cloud,
      builder: (_, __) => ListView(padding: const EdgeInsets.all(12), children: [
        const Etichetta('Registrazione'),
        const SizedBox(height: 8),
        Elenco(figli: [
          _op('Tipo al premere Registra', Chip2(fisso == null ? 'Chiedi ogni volta' : (fisso == 'idea' ? 'Nota vocale' : 'Appuntamento')), onTap: () async {
            final nuovo = fisso == null ? 'appuntamento' : (fisso == 'appuntamento' ? 'idea' : null);
            if (nuovo == null) {
              await p.remove('tipo_fisso');
            } else {
              await p.setString('tipo_fisso', nuovo);
            }
            setState(() {});
          }),
          _op('Lingua del riassunto', Chip2(p.getString('lingua') ?? 'Italiano'), onTap: () async {
            const l = ['Italiano', 'Stessa della registrazione', 'Tedesco', 'Francese', 'Inglese'];
            await p.setString('lingua', l[(l.indexOf(p.getString('lingua') ?? 'Italiano') + 1) % l.length]);
            setState(() {});
          }),
        ]),
        const SizedBox(height: 16),
        const Etichetta('Cloud'),
        const SizedBox(height: 8),
        Elenco(figli: [
          _op('DiGiShare', Chip2(cloud.collegato ? 'Collegato' : 'Collega'), sotto: cloud.collegato ? cloud.base : 'Non collegato', onTap: () async {
            await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const CollegaScreen()));
            _carica();
          }),
          _sw('solo_wifi', true, 'Carica solo con Wi-Fi'),
          if (cloud.ultimoErrore != null) _op('Ultimo errore', const SizedBox.shrink(), sotto: cloud.ultimoErrore),
        ]),
        const SizedBox(height: 16),
        const Etichetta('Parole e voci'),
        const SizedBox(height: 8),
        Elenco(figli: [
          _lista('Glossario', _glo, 'glossario', 'termine', 'Parole che l\'IA deve scrivere giuste: nomi, sigle, termini del lavoro.', 'Nuovo termine'),
          _lista('Voci note', _voci, 'voce', 'nome', 'Le persone che compaiono spesso nelle registrazioni.', 'Nome della persona'),
          _lista('Memoria', _mem, 'memoria', 'testo', 'Cose da ricordare in ogni riassunto: persone, preferenze, abitudini.', 'Cosa ricordare'),
        ]),
        const SizedBox(height: 16),
        const Etichetta('Sicurezza'),
        const SizedBox(height: 8),
        Elenco(figli: [
          _sw('sblocco', false, 'Sblocco con impronta', sotto: 'Chiede impronta o volto all\'apertura', prima: _impronta),
        ]),
        const SizedBox(height: 16),
        const Etichetta('Statistiche'),
        const SizedBox(height: 8),
        Elenco(figli: [
          _op('Note registrate', Text('${_st['note'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w700))),
          _op('Tempo totale', Text(durataBreve(_st['ms'] ?? 0), style: const TextStyle(fontWeight: FontWeight.w700))),
          _op('Giorni con almeno una nota', Text('${_st['giorni'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 16),
        const Etichetta('Informazioni'),
        const SizedBox(height: 8),
        const Text('DiGiNotes 0.1. Audio, testi e note restano sul telefono; vanno in DiGiShare solo se lo attivi qui sopra.', style: TextStyle(fontSize: 14.5)),
      ]),
    );
  }

  Widget _lista(String t, int n, String tab, String col, String spiega, String campo) => _op(t, Chip2('$n'), onTap: () async {
        await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ListaScreen(titolo: t, tabella: tab, colonna: col, spiegazione: spiega, campo: campo)));
        _carica();
      });
}

class ListaScreen extends StatefulWidget {
  const ListaScreen({super.key, required this.titolo, required this.tabella, required this.colonna, required this.spiegazione, required this.campo});
  final String titolo, tabella, colonna, spiegazione, campo;
  @override
  State<ListaScreen> createState() => _ListaScreenState();
}

class _ListaScreenState extends State<ListaScreen> {
  List<Map<String, Object?>> _r = [];

  @override
  void initState() {
    super.initState();
    _carica();
  }

  Future<void> _carica() async {
    final r = await db.lista(widget.tabella);
    if (mounted) setState(() => _r = r);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: Barra(titolo: widget.titolo, azioni: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Aggiungi',
            onPressed: () async {
              final t = await chiediTesto(context, widget.campo, righe: widget.tabella == 'memoria' ? 3 : 1, si: 'Aggiungi');
              if (t == null) return;
              await db.aggiungiLista(widget.tabella, widget.colonna, t);
              _carica();
            },
          ),
        ]),
        body: ListView(padding: const EdgeInsets.all(14), children: [
          Text(widget.spiegazione, style: const TextStyle(fontSize: 15)),
          const SizedBox(height: 12),
          if (_r.isEmpty)
            const Text('Ancora niente. Aggiungi con il + in alto.', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))
          else
            Elenco(figli: [
              for (final x in _r)
                ListTile(
                  title: Text(x[widget.colonna] as String, style: const TextStyle(fontSize: 15)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Togli',
                    onPressed: () async {
                      await db.eliminaLista(widget.tabella, x['id'] as int);
                      _carica();
                    },
                  ),
                ),
            ]),
        ]),
      );
}

class CollegaScreen extends StatefulWidget {
  const CollegaScreen({super.key});
  @override
  State<CollegaScreen> createState() => _CollegaScreenState();
}

class _CollegaScreenState extends State<CollegaScreen> {
  late final _ind = TextEditingController(text: cloud.base ?? '');
  late final _ute = TextEditingController(text: cloud.utente ?? 'admin');
  final _pwd = TextEditingController();
  final _cod = TextEditingController();
  bool _lavoro = false;
  String? _err;

  Future<void> _entra() async {
    setState(() {
      _lavoro = true;
      _err = null;
    });
    try {
      await cloud.collega(indirizzo: _ind.text, utente: _ute.text.trim(), password: _pwd.text, codice: _cod.text.trim());
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _lavoro = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const Barra(titolo: 'Collega DiGiShare'),
        body: ListView(padding: const EdgeInsets.all(14), children: [
          if (cloud.collegato) ...[
            Text('Collegato a ${cloud.base}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Secondario(testo: 'Scollega', onTap: () async {
              await cloud.scollega();
              if (context.mounted) Navigator.pop(context);
            }),
          ] else ...[
            const Text('L\'indirizzo del tuo server DiGiShare, con HTTPS, e lo stesso accesso. La password non resta sul telefono: resta solo la sessione, cifrata.', style: TextStyle(fontSize: 15)),
            const SizedBox(height: 12),
            TextField(controller: _ind, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Indirizzo del server', hintText: 'https://il-tuo-server')),
            const SizedBox(height: 10),
            TextField(controller: _ute, decoration: const InputDecoration(labelText: 'Nome utente')),
            const SizedBox(height: 10),
            TextField(controller: _pwd, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
            const SizedBox(height: 10),
            TextField(controller: _cod, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(labelText: 'Codice Authenticator', counterText: '')),
            const SizedBox(height: 12),
            if (_err != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(gradient: kTenue, borderRadius: BorderRadius.circular(8), border: Border.all(color: kRosa)),
                child: Text(_err!, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 12),
            ],
            Principale(testo: _lavoro ? 'Collegamento…' : 'Collega', onTap: _lavoro ? null : _entra),
          ],
        ]),
      );
}
