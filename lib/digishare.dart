import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'db.dart';
import 'registratore.dart';

class ErroreDiGiShare implements Exception {
  ErroreDiGiShare(this.messaggio);
  final String messaggio;
  @override
  String toString() => messaggio;
}

/// Parla con DiGiShare come fa il suo pannello: accesso con password e Authenticator, caricamento tus a pezzi da 50 MB,
/// link. Non serve toccare DiGiShare per caricare; trascrizione e riassunto degli audio si aggiungono lì.
class ClientDiGiShare {
  ClientDiGiShare({required this.base, http.Client? client, this.cookie = ''}) : _c = client ?? http.Client();
  final String base;
  final http.Client _c;
  String cookie;
  String? csrf;
  static const pezzo = 50 * 1024 * 1024;

  Uri _u(String percorso) => Uri.parse('$base$percorso');
  Map<String, String> get _testa => {'Origin': base, if (cookie.isNotEmpty) 'Cookie': cookie, if (csrf != null) 'x-csrf-token': csrf!};

  void _prendiCookie(http.BaseResponse r) {
    final grezzo = r.headers['set-cookie'];
    if (grezzo == null) return;
    final mappa = <String, String>{};
    for (final c in cookie.split('; ')) {
      final i = c.indexOf('=');
      if (i > 0) mappa[c.substring(0, i)] = c.substring(i + 1);
    }
    // http unisce più Set-Cookie con la virgola; le date «Expires» ne contengono una, quindi si taglia prima di un nome=.
    for (final c in grezzo.split(RegExp(r',(?=\s*[A-Za-z0-9_.\-]+=)'))) {
      final coppia = c.split(';').first.trim();
      final i = coppia.indexOf('=');
      if (i > 0) mappa[coppia.substring(0, i)] = coppia.substring(i + 1);
    }
    cookie = mappa.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  Never _errore(http.Response r, String predefinito) {
    try {
      final e = (jsonDecode(r.body) as Map)['error'];
      if (e is String && e.isNotEmpty) throw ErroreDiGiShare(e);
    } on FormatException {
      // risposta non in JSON: si usa il messaggio predefinito
    }
    throw ErroreDiGiShare('$predefinito (codice ${r.statusCode})');
  }

  Future<void> accedi({required String utente, required String password, String codice = '', bool ricorda = true}) async {
    final r = await _c.post(_u('/api/auth/login'), headers: {..._testa, 'Content-Type': 'application/json'}, body: jsonEncode({'username': utente, 'password': password, 'code': codice, 'remember': ricorda}));
    if (r.statusCode != 200) _errore(r, 'Accesso non riuscito');
    _prendiCookie(r);
    csrf = (jsonDecode(r.body) as Map)['csrf'] as String?;
  }

  /// Verifica la sessione salvata e prende il token per le modifiche.
  Future<bool> sessioneValida() async {
    if (cookie.isEmpty) return false;
    final r = await _c.get(_u('/api/auth/me'), headers: _testa);
    if (r.statusCode != 200) return false;
    _prendiCookie(r);
    csrf = (jsonDecode(r.body) as Map)['csrf'] as String?;
    return true;
  }

  static String _meta(Map<String, String> v) => v.entries.map((e) => '${e.key} ${base64.encode(utf8.encode(e.value))}').join(',');

  /// Carica o riprende. Restituisce l'indirizzo tus; [salva] lo riceve appena creato, così un riavvio riprende da lì.
  /// [genere] dice a DiGiShare cosa farne: `appuntamento` testo e riassunto, `idea` solo testo.
  Future<String> carica(File file, {required String nome, String tipo = 'audio/ogg', String genere = 'appuntamento', String titolo = '', String? riprendi, FutureOr<void> Function(String)? salva, void Function(int inviati, int totale)? avanzamento}) async {
    final totale = await file.length();
    var indirizzo = riprendi;
    var inviati = 0;
    if (indirizzo != null) {
      final h = await _c.head(Uri.parse(indirizzo), headers: {..._testa, 'Tus-Resumable': '1.0.0'});
      if (h.statusCode == 200) {
        inviati = int.tryParse(h.headers['upload-offset'] ?? '') ?? 0;
      } else {
        indirizzo = null;
      }
    }
    if (indirizzo == null) {
      final r = await _c.post(_u('/api/caricamenti'), headers: {
        ..._testa,
        'Tus-Resumable': '1.0.0',
        'Upload-Length': '$totale',
        'Upload-Metadata': _meta({'filename': nome, 'filetype': tipo, 'genere': genere, 'titolo': titolo, 'ultimamodifica': '${(await file.lastModified()).millisecondsSinceEpoch}', 'categoria': ''}),
      });
      if (r.statusCode != 201) _errore(r, 'DiGiShare non ha accettato il caricamento');
      final dove = r.headers['location'];
      if (dove == null) throw ErroreDiGiShare('Risposta senza indirizzo del caricamento');
      indirizzo = Uri.parse(base).resolve(dove).toString();
      await salva?.call(indirizzo);
    }
    final lettura = await file.open();
    try {
      while (inviati < totale) {
        await lettura.setPosition(inviati);
        final bytes = await lettura.read(pezzo);
        final r = await _c.patch(Uri.parse(indirizzo), headers: {..._testa, 'Tus-Resumable': '1.0.0', 'Upload-Offset': '$inviati', 'Content-Type': 'application/offset+octet-stream'}, body: bytes);
        if (r.statusCode != 204) _errore(r, 'Caricamento interrotto');
        inviati = int.tryParse(r.headers['upload-offset'] ?? '') ?? inviati + bytes.length;
        avanzamento?.call(inviati, totale);
      }
    } finally {
      await lettura.close();
    }
    return indirizzo;
  }

  /// Lo stato di una nota in DiGiShare: `{file, nota}`, o null se lì non c'è più.
  Future<Map<String, dynamic>?> leggiNota(String id) async {
    final r = await _c.get(_u('/api/note/$id'), headers: _testa);
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) _errore(r, 'Non riesco a leggere la nota da DiGiShare');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// Le stesse correzioni del sito: `frase`, `rinomina`, `sostituisci`.
  Future<void> correggiNota(String id, Map<String, Object?> modifica) async {
    final r = await _c.patch(_u('/api/note/$id'), headers: {..._testa, 'Content-Type': 'application/json'}, body: jsonEncode(modifica));
    if (r.statusCode != 200) _errore(r, 'Correzione non salvata in DiGiShare');
  }

  /// Cosa c'è su DiGiShare: gli id dei file in elenco e quelli nel suo cestino.
  Future<({Set<String> attivi, Set<String> cestino})> statoFile() async {
    Future<Set<String>> ids(String via) async {
      final r = await _c.get(_u(via), headers: _testa);
      if (r.statusCode != 200) _errore(r, 'Non riesco a leggere i file di DiGiShare');
      return {for (final f in ((jsonDecode(r.body) as Map)['file'] as List)) (f as Map)['id'] as String};
    }

    return (attivi: await ids('/api/file'), cestino: await ids('/api/cestino'));
  }

  Future<void> mettiNelCestino(String id) async {
    final r = await _c.delete(_u('/api/file/$id'), headers: _testa);
    if (r.statusCode != 200 && r.statusCode != 404) _errore(r, 'Non riesco a spostare la nota nel cestino di DiGiShare');
  }

  Future<void> togliDalCestino(String id) async {
    final r = await _c.post(_u('/api/file/$id/ripristina'), headers: {..._testa, 'Content-Type': 'application/json'}, body: '{}');
    if (r.statusCode != 200 && r.statusCode != 404) _errore(r, 'Non riesco a ripristinare la nota su DiGiShare');
  }

  Future<void> rifaiNota(String id) async {
    final r = await _c.post(_u('/api/note/$id/rifai'), headers: _testa);
    if (r.statusCode != 200) _errore(r, 'DiGiShare non ha rifatto la nota');
  }

  /// Glossario, voci, memoria e lingua: li usa il NAS per ogni nota. Un NAS che non li conosce ancora risponde 404 e si va avanti.
  Future<void> mandaContesto(Map<String, Object?> contesto) async {
    final r = await _c.put(_u('/api/note/contesto'), headers: {..._testa, 'Content-Type': 'application/json'}, body: jsonEncode(contesto));
    if (r.statusCode != 200 && r.statusCode != 404) _errore(r, 'Glossario e voci non salvati in DiGiShare');
  }

  /// L'audio di una nota: DiGiShare manda la copia pulita appena c'è.
  Future<void> scaricaAudio(String id, File destinazione) async {
    final rq = http.Request('GET', _u('/api/file/$id/audio'))..headers.addAll(_testa);
    final r = await _c.send(rq);
    if (r.statusCode != 200) throw ErroreDiGiShare('Audio non scaricato (codice ${r.statusCode})');
    await r.stream.pipe(destinazione.openWrite());
  }

  /// [scadenza] è in giorni (1, 7, 30, 0 = mai), come in DiGiShare. Con [email] il link è personale: DiGiShare lo spedisce.
  Future<String> creaLink(String nomeFile, {int scadenza = 7, bool scarica = false, List<String> email = const []}) async {
    final elenco = await _c.get(_u('/api/file'), headers: _testa);
    if (elenco.statusCode != 200) _errore(elenco, 'Non riesco a leggere i file di DiGiShare');
    final file = ((jsonDecode(elenco.body) as Map)['file'] as List).cast<Map>().where((f) => f['nome'] == nomeFile).toList();
    if (file.isEmpty) throw ErroreDiGiShare('Questa nota non è ancora in DiGiShare.');
    final r = await _c.post(_u('/api/file/${file.first['id']}/link'), headers: {..._testa, 'Content-Type': 'application/json'}, body: jsonEncode({'chi': email.isEmpty ? 'chiunque' : 'email', 'email': email, 'inviaEmail': email.isNotEmpty, 'scadenza': scadenza, 'scarica': scarica}));
    if (r.statusCode != 200) _errore(r, 'Link non creato');
    final link = (jsonDecode(r.body) as Map)['link'] as List;
    return (link.first as Map)['url'] as String;
  }
}

/// Collegamento salvato e coda dei caricamenti. La password non si conserva: resta solo la sessione,
/// nella memoria cifrata di Android.
class Cloud extends ChangeNotifier {
  static const _s = FlutterSecureStorage();
  String? base;
  String? utente;
  ClientDiGiShare? _client;
  bool lavora = false;
  int? notaInCorso;
  double avanzamento = 0;
  String? ultimoErrore;
  StreamSubscription<List<ConnectivityResult>>? _rete;
  Timer? _giro;
  bool _aggiorna = false;

  /// Cresce quando da DiGiShare arriva qualcosa: le schermate aperte si ricaricano.
  final noteCambiate = ValueNotifier<int>(0);

  bool get collegato => _client != null;
  ClientDiGiShare? get client => _client;

  static String nomeFile(Nota n, int indice) => 'DiGiNotes-${n.id}-${n.creata.millisecondsSinceEpoch}${indice > 0 ? '-$indice' : ''}.ogg';

  Future<void> avvia() async {
    base = await _s.read(key: 'ds_base');
    utente = await _s.read(key: 'ds_utente');
    final cookie = await _s.read(key: 'ds_cookie');
    if (base != null && cookie != null) {
      final c = ClientDiGiShare(base: base!, cookie: cookie);
      try {
        if (await c.sessioneValida()) _client = c;
      } catch (_) {
        // senza rete: la sessione si ricontrolla al prossimo giro
        _client = c;
      }
    }
    _rete = Connectivity().onConnectivityChanged.listen((_) => inviaTutto());
    _giro = Timer.periodic(const Duration(minutes: 1), (_) => aggiornaNote());
    notifyListeners();
    unawaited(aggiornaNote());
    unawaited(inviaTutto());
  }

  Future<void> collega({required String indirizzo, required String utente, required String password, String codice = ''}) async {
    var b = indirizzo.trim();
    if (!b.startsWith('http')) b = 'https://$b';
    b = b.replaceAll(RegExp(r'/+$'), '');
    final c = ClientDiGiShare(base: b);
    await c.accedi(utente: utente, password: password, codice: codice);
    await _s.write(key: 'ds_base', value: b);
    await _s.write(key: 'ds_utente', value: utente);
    await _s.write(key: 'ds_cookie', value: c.cookie);
    base = b;
    this.utente = utente;
    _client = c;
    ultimoErrore = null;
    notifyListeners();
    unawaited(inviaTutto());
  }

  Future<void> scollega() async {
    await _s.delete(key: 'ds_cookie');
    _client = null;
    notifyListeners();
  }

  /// L'utente ha detto Invia: solo da qui in poi la nota entra fra quelle da caricare.
  Future<void> confermaInvio(int id) async {
    await db.aggiornaNota(id, {'stato': Stato.registrata});
    notaCambiata();
    unawaited(inviaTutto());
  }

  void notaCambiata() {
    noteCambiate.value++;
    notifyListeners();
  }

  Future<bool> reteConsentita() => _reteConsentita();

  Future<bool> _reteConsentita() async {
    final pref = await SharedPreferences.getInstance();
    final soloWifi = pref.getBool('solo_wifi') ?? true;
    final r = await Connectivity().checkConnectivity();
    if (r.contains(ConnectivityResult.none)) return false;
    return !soloWifi || r.contains(ConnectivityResult.wifi) || r.contains(ConnectivityResult.ethernet);
  }

  /// Una nota alla volta, in ordine di data. Un errore ferma il giro: si riprova col prossimo cambio di rete o avvio.
  Future<void> inviaTutto() async {
    final c = _client;
    if (c == null || lavora) return;
    if (!await _reteConsentita()) return;
    lavora = true;
    ultimoErrore = null;
    notifyListeners();
    try {
      // Si rilegge l'elenco: una nota confermata mentre un'altra sta salendo parte subito dopo.
      for (var elenco = await db.daInviare(); elenco.isNotEmpty; elenco = await db.daInviare()) {
        for (final n in elenco) {
          await inviaNota(n);
        }
      }
    } catch (e) {
      ultimoErrore = '$e';
    } finally {
      lavora = false;
      notaInCorso = null;
      notifyListeners();
    }
  }

  Future<void> inviaNota(Nota n) async {
    final c = _client;
    if (c == null) throw ErroreDiGiShare('Collega prima DiGiShare in Impostazioni.');
    await db.aggiornaNota(n.id, {'stato': Stato.caricamento});
    notaInCorso = n.id;
    avanzamento = 0;
    notifyListeners();
    if (!await c.sessioneValida()) {
      await db.aggiornaNota(n.id, {'stato': Stato.registrata});
      _client = null;
      throw ErroreDiGiShare('Sessione di DiGiShare scaduta: ricollegati in Impostazioni.');
    }
    await _mandaContesto(c);
    try {
      final pp = await db.parti(n.id);
      for (var i = 0; i < pp.length; i++) {
        final x = pp[i];
        if (x.inviata) continue;
        final file = File(x.percorso);
        if (!await file.exists()) continue;
        await c.carica(
          file,
          nome: nomeFile(n, i),
          tipo: _tipoDi(x.percorso),
          genere: n.appuntamento ? 'appuntamento' : 'idea',
          // Il titolo scritto dall'utente vale anche in DiGiShare; quello automatico lo sostituisce l'IA.
          titolo: Registratore.titoloAutomatico(n.titolo, n.tipo, n.creata) ? '' : n.titolo,
          riprendi: x.tusUrl,
          salva: (u) => db.aggiornaParte(x.id, {'tus_url': u}),
          avanzamento: (a, t) {
            avanzamento = t == 0 ? 1 : a / t;
            notifyListeners();
          },
        );
        await db.aggiornaParte(x.id, {'inviata': 1});
      }
    } catch (_) {
      await db.aggiornaNota(n.id, {'stato': Stato.registrata});
      rethrow;
    }
    await db.aggiornaNota(n.id, {'stato': Stato.caricata});
    notifyListeners();
  }

  static String idDi(String tusUrl) => Uri.parse(tusUrl).pathSegments.last;

  /// Mette insieme i pezzi di una nota: gli orari tornano quelli del telefono, cioè senza la parte tagliata
  /// e con i pezzi uno dopo l'altro. [risposte] è nello stesso ordine di [parti].
  static ({List<Map<String, Object?>> segmenti, List<Sezione> sezioni}) componi(List<Parte> parti, List<Map<String, dynamic>> risposte) {
    final segmenti = <Map<String, Object?>>[];
    final righe = <String, List<(String, int)>>{};
    var scarto = 0;
    for (var i = 0; i < parti.length; i++) {
      final x = parti[i];
      final nota = risposte[i]['nota'] as Map<String, dynamic>;
      final interaMs = (((risposte[i]['file'] as Map)['durata'] as num? ?? 0) * 1000).round();
      final fine = x.fineMs ?? interaMs;
      int? sposta(num secondi) {
        final ms = (secondi * 1000).round();
        // Una nota sola tiene anche le frasi tagliate via: restano nascoste e tornano se si toglie il taglio.
        if (parti.length > 1 && (ms < x.inizioMs || (fine > 0 && ms > fine))) return null;
        return ms - x.inizioMs + scarto;
      }

      for (final s in (nota['segmenti'] as List).cast<Map<String, dynamic>>()) {
        final inizio = sposta(s['inizio'] as num);
        if (inizio == null) continue;
        segmenti.add({'inizio_ms': inizio, 'fine_ms': sposta(s['fine'] as num), 'chi': s['chi'], 'testo': s['testo'], 'traduzione': s['traduzione']});
      }
      for (final z in (nota['riassunto'] as List).cast<Map<String, dynamic>>()) {
        for (final r in (z['righe'] as List).cast<Map<String, dynamic>>()) {
          final ms = sposta(r['secondi'] as num) ?? scarto;
          (righe[z['titolo'] as String] ??= []).add((r['testo'] as String, ms));
        }
      }
      scarto += fine - x.inizioMs;
    }
    final sezioni = [for (final e in righe.entries) Sezione(e.key, [for (final r in e.value) r.$1], [for (final r in e.value) r.$2])];
    return (segmenti: segmenti, sezioni: sezioni);
  }

  /// Cosa va fatto per tenere allineato il cestino. [ora] è lo stato su DiGiShare, [prima] quello dell'ultimo controllo:
  /// se è cambiato l'ha cambiato DiGiShare, e il telefono segue; altrimenti, se il telefono è diverso, segue DiGiShare.
  /// Una nota sparita da DiGiShare resta nel cestino del telefono: l'audio non si cancella da solo.
  static String azioneCestino({required int ora, required int? prima, required bool nelCestino}) {
    if (prima != null && ora != prima) {
      if (ora == 0) return nelCestino ? 'ripristina-qui' : '';
      return nelCestino ? '' : 'cestina-qui';
    }
    if (ora == 2) return nelCestino ? '' : 'cestina-qui';
    if (ora == 0 && nelCestino) return 'cestina-la';
    if (ora == 1 && !nelCestino) return prima == null ? 'cestina-qui' : 'ripristina-la';
    return '';
  }

  Future<bool> allineaCestino(ClientDiGiShare c) async {
    final stato = await c.statoFile();
    var cambiate = false;
    for (final n in await db.noteDaAllineare()) {
      final ids = [for (final x in await db.parti(n.id)) if (x.tusUrl != null) idDi(x.tusUrl!)];
      final ora = ids.any(stato.cestino.contains) ? 1 : (ids.any(stato.attivi.contains) ? 0 : 2);
      var dopo = ora;
      switch (azioneCestino(ora: ora, prima: n.remoto, nelCestino: n.cestinata != null)) {
        case 'cestina-qui':
          await db.cestina(n.id);
          cambiate = true;
        case 'ripristina-qui':
          await db.ripristina(n.id);
          cambiate = true;
        case 'cestina-la':
          for (final id in ids) {
            await c.mettiNelCestino(id);
          }
          dopo = 1;
        case 'ripristina-la':
          for (final id in ids) {
            await c.togliDalCestino(id);
          }
          dopo = 0;
      }
      if (dopo != n.remoto) await db.aggiornaNota(n.id, {'remoto': dopo});
    }
    return cambiate;
  }

  /// Prende da DiGiShare quello che è pronto: prima testo e riassunto, poi l'audio pulito. Un errore si riprova al giro dopo.
  Future<void> aggiornaNote() async {
    final c = _client;
    if (c == null || _aggiorna) return;
    _aggiorna = true;
    try {
      if (c.csrf == null) await c.sessioneValida();
      var cambiate = false;
      for (final n in await db.inAttesaDiDiGiShare()) {
        final pp = await db.parti(n.id);
        if (pp.isEmpty || pp.any((x) => x.tusUrl == null)) continue;
        final risposte = <Map<String, dynamic>>[];
        for (final x in pp) {
          final r = await c.leggiNota(idDi(x.tusUrl!));
          final stato = (r?['nota'] as Map?)?['stato'];
          if (stato == 'errore') ultimoErrore = '«${n.titolo}»: ${(r!['nota'] as Map)['errore']}';
          if (stato != 'pronta') break;
          risposte.add(r!);
        }
        if (risposte.length != pp.length) continue;
        final fatto = componi(pp, risposte);
        final automatico = Registratore.titoloAutomatico(n.titolo, n.tipo, n.creata);
        await db.salvaRisultato(n.id, fatto.segmenti, fatto.sezioni, titolo: automatico ? (risposte.first['file'] as Map)['titolo'] as String? : null);
        cambiate = true;
      }
      if (await _reteConsentita()) {
        for (final x in await db.partiDaPulire()) {
          final r = await c.leggiNota(idDi(x.tusUrl!));
          final pulita = (r?['nota'] as Map?)?['pulita'];
          if (r == null || pulita == -1) {
            await db.aggiornaParte(x.id, {'pulita': 2});
          } else if (pulita == 1) {
            final nuovo = File('${p.withoutExtension(x.percorso)}-pulito.ogg');
            final temp = File('${nuovo.path}.temp');
            await c.scaricaAudio(idDi(x.tusUrl!), temp);
            await temp.rename(nuovo.path);
            await db.sostituisciAudio(x.percorso, nuovo.path);
            await File(x.percorso).delete().catchError((_) => File(x.percorso));
            cambiate = true;
          }
        }
      }
      if (await allineaCestino(c)) cambiate = true;
      if (cambiate) {
        noteCambiate.value++;
        notifyListeners();
      }
    } catch (_) {
      // senza rete o col server spento: si riprova al giro dopo
    } finally {
      _aggiorna = false;
    }
  }

  Future<void> _mandaContesto(ClientDiGiShare c) async {
    final pref = await SharedPreferences.getInstance();
    await c.mandaContesto({
      'glossario': [for (final r in await db.lista('glossario')) r['termine']],
      'voci': [for (final r in await db.lista('voce')) r['nome']],
      'memoria': [for (final r in await db.lista('memoria')) r['testo']],
      'lingua': pref.getString('lingua') ?? 'Italiano',
    });
  }

  /// Le parti di una nota in DiGiShare, con la sessione controllata. Null se manca il collegamento o una parte non è lì.
  Future<(ClientDiGiShare, List<Parte>)?> _partiInDiGiShare(Nota n) async {
    final c = _client;
    final pp = await db.parti(n.id);
    if (c == null || pp.isEmpty || pp.any((x) => x.tusUrl == null)) return null;
    if (!await c.sessioneValida()) throw ErroreDiGiShare('Sessione di DiGiShare scaduta: ricollegati in Impostazioni.');
    return (c, pp);
  }

  /// La correzione fatta sul telefono va anche in DiGiShare, in ogni pezzo della nota. False: la nota lì non c'è.
  Future<bool> correggi(Nota n, Map<String, Object?> modifica) async {
    final dove = await _partiInDiGiShare(n);
    if (dove == null) return false;
    final (c, pp) = dove;
    for (final x in pp) {
      await c.correggiNota(idDi(x.tusUrl!), modifica);
    }
    return true;
  }

  /// Una frase si indica col suo posto in DiGiShare, che ha anche quelle tagliate via: si trova dall'orario, pezzo per pezzo.
  Future<bool> correggiFrase(Nota n, Segmento s, String testo) async {
    final dove = await _partiInDiGiShare(n);
    if (dove == null) return false;
    final (c, pp) = dove;
    var scarto = 0;
    for (final x in pp) {
      final id = idDi(x.tusUrl!);
      final r = await c.leggiNota(id);
      final remoti = (r?['nota'] as Map?)?['segmenti'] as List? ?? const [];
      final i = remoti.indexWhere((f) => (((f as Map)['inizio'] as num) * 1000).round() - x.inizioMs + scarto == s.inizioMs);
      if (i >= 0) {
        await c.correggiNota(id, {'frase': {'i': i, 'testo': testo}});
        return true;
      }
      final interaMs = ((((r?['file'] as Map?)?['durata'] as num?) ?? 0) * 1000).round();
      scarto += (x.fineMs ?? interaMs) - x.inizioMs;
    }
    throw ErroreDiGiShare('Frase non trovata in DiGiShare.');
  }

  /// Rifà testo e riassunto da capo in DiGiShare. Quando sono pronti arrivano qui da soli e sostituiscono quelli di prima.
  Future<void> rifai(Nota n) async {
    final dove = await _partiInDiGiShare(n);
    if (dove == null) throw ErroreDiGiShare('Questa nota non è in DiGiShare.');
    final (c, pp) = dove;
    await _mandaContesto(c);
    for (final x in pp) {
      await c.rifaiNota(idDi(x.tusUrl!));
    }
    await db.aggiornaNota(n.id, {'stato': Stato.caricata});
    noteCambiate.value++;
    notifyListeners();
  }

  static String _tipoDi(String percorso) => switch (p.extension(percorso).toLowerCase()) {
        '.mp3' => 'audio/mpeg',
        '.m4a' || '.aac' => 'audio/mp4',
        '.wav' => 'audio/wav',
        '.opus' || '.ogg' => 'audio/ogg',
        _ => 'audio/ogg',
      };

  @override
  void dispose() {
    _rete?.cancel();
    _giro?.cancel();
    super.dispose();
  }
}

final cloud = Cloud();
