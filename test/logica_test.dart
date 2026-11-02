import 'dart:convert';
import 'dart:io';

import 'package:diginotes/db.dart';
import 'package:diginotes/digishare.dart';
import 'package:diginotes/registratore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Db x;

  setUp(() async {
    x = await Db.apri(percorso: inMemoryDatabasePath, fabbrica: databaseFactoryFfiNoIsolate);
  });
  tearDown(() => x.d.close());

  group('note', () {
    test('al primo avvio c\'è la nota di esempio, con testo e riassunto', () async {
      final n = await x.note();
      expect(n.length, 1);
      expect(n.first.esempio, isTrue);
      expect((await x.segmenti(n.first.id)).length, 5);
      expect((await x.riassunti(n.first.id)).map((r) => r.modello), ['Appuntamento']);
      expect((await x.modelli()).length, greaterThanOrEqualTo(6));
    });

    test('una registrazione in corso non è in elenco; dopo un crash si ritrova', () async {
      final id = await x.nuovaNota(titolo: 'Bar', tipo: 'appuntamento');
      await x.aggiungiParte(id, '/a.ogg');
      expect((await x.note()).any((n) => n.id == id), isFalse);
      expect(await x.recuperaInterrotte(), 1);
      final n = await x.nota(id);
      expect(n!.stato, Stato.daInviare);
      expect(n.titolo, 'Bar (interrotta)');
      expect((await x.daInviare()).map((e) => e.id), isNot(contains(id)));
    });

    test('una nota «Da inviare» non parte da sola: entra in coda solo confermata', () async {
      final id = await x.nuovaNota(titolo: 'Prova', tipo: 'appuntamento', stato: Stato.daInviare);
      await x.aggiungiParte(id, '/a.ogg');
      expect(Stato.etichetta(Stato.daInviare), 'Da inviare');
      expect(await x.daInviare(), isEmpty);
      expect(await x.inAttesaDiDiGiShare(), isEmpty);
      await x.aggiornaNota(id, {'stato': Stato.registrata});
      expect((await x.daInviare()).single.id, id);
    });

    test('unire una nota da inviare non la conferma', () async {
      final a = await x.nuovaNota(titolo: 'A', tipo: 'idea', stato: Stato.daInviare);
      final b = await x.nuovaNota(titolo: 'B', tipo: 'idea', stato: Stato.registrata);
      final unita = await x.unisci([(await x.nota(a))!, (await x.nota(b))!], 'AB');
      expect((await x.nota(unita))!.stato, Stato.daInviare);
      expect((await x.daInviare()).map((e) => e.id), isNot(contains(unita)));
    });

    test('titolo proposto: mai dall\'agenda, e quello scritto dall\'utente non è automatico', () async {
      await initializeDateFormatting('it');
      final q = DateTime(2026, 11, 2, 8, 5);
      expect(Registratore.titoloPredefinito('appuntamento', q), 'Nota 02.11 08:05');
      expect(Registratore.titoloPredefinito('idea', q), 'Nota 02.11 08:05');
      expect(Registratore.titoloAutomatico('Nota 02.11 08:05', 'idea', q), isTrue);
      expect(Registratore.titoloAutomatico('Fisioterapia', 'appuntamento', q), isFalse);
    });

    test('cestino: esce dall\'elenco, si ripristina, l\'eliminazione restituisce i file', () async {
      final id = await x.nuovaNota(titolo: 'A', tipo: 'idea', stato: Stato.registrata);
      await x.aggiungiParte(id, '/a.ogg');
      await x.aggiungiSegno(id, 10, 'foto', percorso: '/f.jpg');
      await x.cestina(id);
      expect((await x.note()).any((n) => n.id == id), isFalse);
      expect((await x.cestino()).single.id, id);
      await x.ripristina(id);
      expect((await x.cestino()), isEmpty);
      await x.cestina(id);
      expect(await x.eliminaDefinitivamente(id), ['/a.ogg', '/f.jpg']);
      expect(await x.nota(id), isNull);
      expect(await x.parti(id), isEmpty);
    });

    test('filtri per tipo e cartella; eliminare la cartella non tocca le note', () async {
      final c = await x.nuovaCartella('Clienti', 1);
      final a = await x.nuovaNota(titolo: 'A', tipo: 'idea', stato: Stato.registrata, cartella: c);
      await x.nuovaNota(titolo: 'B', tipo: 'appuntamento', stato: Stato.registrata);
      expect((await x.note(cartella: c)).single.id, a);
      expect((await x.note(tipo: 'idea')).single.id, a);
      expect((await x.cartelle()).single.conta, 1);
      await x.eliminaCartella(c);
      expect((await x.nota(a))!.cartella, isNull);
      expect(await x.cartelle(), isEmpty);
    });
  });

  group('testo', () {
    test('sostituisci senza distinguere le maiuscole; rinomina chi parla', () async {
      final id = (await x.note()).first.id;
      expect(await x.sostituisci(id, 'FRANCHIGIA', 'deducibile'), 1);
      expect((await x.segmenti(id)).any((s) => s.testo.contains('deducibile')), isTrue);
      await x.rinominaChi(id, 'Cliente', 'Rossi');
      expect((await x.segmenti(id)).where((s) => s.chi == 'Rossi').length, 2);
      expect(await x.sostituisci(id, 'parola.assente(', 'x'), 0);
    });

    test('ricerca: dentro i testi, nel riassunto, nel titolo; simboli non speciali', () async {
      expect((await x.cerca('franchigia')).single.frase, contains('franchigia'));
      expect((await x.cerca('licenza')).single.ms, 216000);
      expect((await x.cerca('1\'240')).isNotEmpty, isTrue);
      expect((await x.cerca('Esempio')).single.frase, isNull);
      expect(await x.cerca('Esempio', soloConTesto: true), isEmpty);
      expect(await x.cerca('%'), isEmpty);
      expect(await x.cerca('_'), isEmpty);
    });

    test('Chiedi: frasi pertinenti con la fonte, nessuna se la domanda non c\'entra', () async {
      final r = await x.frasiPertinenti('Che franchigia ho concordato?');
      expect(r.first.frase, contains('franchigia'));
      expect(r.first.nota.esempio, isTrue);
      expect(await x.frasiPertinenti('cavalli'), isEmpty);
      expect(await x.frasiPertinenti('che è?'), isEmpty);
    });

    test('Chiedi: le cose da fare vengono dai riassunti', () async {
      final r = await x.dalleSezioni('Cose da fare');
      expect(r.map((e) => e.frase), contains('Marco: inviare il contratto entro venerdì.'));
      expect(await x.dalleSezioni('Inesistente'), isEmpty);
    });
  });

  test('unisci: orari spostati, data della più vecchia, originali nel cestino', () async {
    final a = await x.nuovaNota(titolo: 'Prima', tipo: 'idea', stato: Stato.registrata);
    await x.aggiornaNota(a, {'durata_ms': 60000, 'creata': 1000});
    await x.aggiungiParte(a, '/a.ogg');
    await x.d.insert('segmento', {'nota': a, 'inizio_ms': 5000, 'chi': 'X', 'testo': 'uno'});
    final b = await x.nuovaNota(titolo: 'Seconda', tipo: 'idea', stato: Stato.registrata);
    await x.aggiornaNota(b, {'durata_ms': 30000, 'creata': 2000});
    await x.aggiungiParte(b, '/b.ogg');
    await x.d.insert('segmento', {'nota': b, 'inizio_ms': 1000, 'chi': 'Y', 'testo': 'due'});
    final id = await x.unisci([(await x.nota(b))!, (await x.nota(a))!], 'Unita');
    final n = (await x.nota(id))!;
    expect(n.durataMs, 90000);
    expect(n.creata.millisecondsSinceEpoch, 1000);
    expect((await x.parti(id)).map((p) => p.percorso), ['/a.ogg', '/b.ogg']);
    expect((await x.segmenti(id)).map((s) => s.inizioMs), [5000, 61000]);
    expect((await x.cestino()).length, 2);
  });

  test('taglio: non tocca il file e si salva sulla parte', () async {
    final a = await x.nuovaNota(titolo: 'T', tipo: 'idea', stato: Stato.registrata);
    await x.aggiungiParte(a, '/a.ogg');
    await x.taglia(a, 1000, 5000);
    final p = (await x.parti(a)).single;
    expect([p.inizioMs, p.fineMs, p.percorso], [1000, 5000, '/a.ogg']);
  });

  group('ritorno da DiGiShare', () {
    Map<String, dynamic> risposta(num durata, List<num> frasi, num riga) => {
          'file': {'durata': durata, 'titolo': 'Titolo IA'},
          'nota': {
            'stato': 'pronta',
            'segmenti': [for (final s in frasi) {'inizio': s, 'fine': s + 1, 'chi': 'Persona 1', 'testo': 'a $s'}],
            'riassunto': [
              {
                'titolo': 'Cose da fare',
                'righe': [{'testo': 'b $riga', 'secondi': riga}],
              },
            ],
          },
        };

    test('il taglio toglie frasi e sposta gli orari; i pezzi vanno in fila', () {
      final fatto = Cloud.componi([
        Parte({'id': 1, 'percorso': 'a', 'inizio_ms': 10000, 'fine_ms': 30000}),
        Parte({'id': 2, 'percorso': 'b', 'inizio_ms': 0}),
      ], [
        risposta(60, [5, 12, 40], 12),
        risposta(10, [2], 3),
      ]);
      expect(fatto.segmenti.map((s) => s['inizio_ms']), [2000, 22000]);
      expect(fatto.sezioni.single.righe, ['b 12', 'b 3']);
      expect(fatto.sezioni.single.ms, [2000, 23000]);
    });

    test('il risultato rende pronta la nota e sostituisce il testo; l\'audio pulito vale per chi usa lo stesso file', () async {
      final id = await x.nuovaNota(titolo: 't', tipo: 'appuntamento', stato: Stato.caricata);
      expect((await x.inAttesaDiDiGiShare()).map((n) => n.id), [id]);
      final parte = await x.aggiungiParte(id, 'vecchio.ogg');
      await x.aggiornaParte(parte, {'tus_url': 'https://x/api/caricamenti/abc'});
      await x.salvaRisultato(id, [{'inizio_ms': 0, 'chi': 'Voce', 'testo': 'ciao'}], [Sezione('Progetti', ['P'], [0])], titolo: 'Nuovo');
      final n = (await x.nota(id))!;
      expect(n.stato, Stato.pronta);
      expect(n.titolo, 'Nuovo');
      expect((await x.segmenti(id)).single.testo, 'ciao');
      expect((await x.riassunti(id)).single.sezioni.single.ms, [0]);
      expect(await x.inAttesaDiDiGiShare(), isEmpty);
      expect((await x.partiDaPulire()).single.id, parte);
      await x.sostituisciAudio('vecchio.ogg', 'pulito.ogg');
      expect((await x.parti(id)).single.percorso, 'pulito.ogg');
      expect(await x.partiDaPulire(), isEmpty);
      expect(Cloud.idDi('https://x/api/caricamenti/abc'), 'abc');
    });

    test('unire note già in DiGiShare tiene i loro indirizzi: non si ricaricano', () async {
      final a = await x.nuovaNota(titolo: 'a', tipo: 'appuntamento', stato: Stato.pronta);
      final b = await x.nuovaNota(titolo: 'b', tipo: 'appuntamento', stato: Stato.pronta);
      for (final (n, u) in [(a, 'aaa'), (b, 'bbb')]) {
        final pz = await x.aggiungiParte(n, '/$u.ogg');
        await x.aggiornaParte(pz, {'tus_url': 'https://x/api/caricamenti/$u', 'inviata': 1, 'pulita': 1});
      }
      final u = await x.unisci([(await x.nota(a))!, (await x.nota(b))!], 'unita');
      final pp = await x.parti(u);
      expect(pp.map((q) => Cloud.idDi(q.tusUrl!)), ['aaa', 'bbb']);
      expect(pp.every((q) => q.inviata && q.pulita == 1), isTrue);
    });

    test('glossario e voci vanno a DiGiShare col token; un NAS che non li conosce non ferma il caricamento', () async {
      Map<String, dynamic>? arrivato;
      var codice = 200;
      final c = ClientDiGiShare(base: 'https://x', cookie: 'c=1', client: MockClient((rq) async {
        expect(rq.method, 'PUT');
        expect(rq.url.path, '/api/note/contesto');
        arrivato = jsonDecode(rq.body) as Map<String, dynamic>;
        return http.Response('{}', codice);
      }));
      await c.mandaContesto({'glossario': ['DiGiNotes'], 'voci': ['Luca'], 'memoria': [], 'lingua': 'Italiano'});
      expect(arrivato!['voci'], ['Luca']);
      codice = 404;
      await c.mandaContesto({'glossario': []});
      codice = 500;
      expect(() => c.mandaContesto({'glossario': []}), throwsA(isA<ErroreDiGiShare>()));
    });

    test('il taglio sposta orari di testo, riassunto e momenti; togliendolo tornano', () async {
      final id = await x.nuovaNota(titolo: 't', tipo: 'appuntamento', stato: Stato.caricata);
      await x.aggiungiParte(id, '/a.ogg');
      await x.salvaRisultato(id, [{'inizio_ms': 2000, 'fine_ms': 3000, 'chi': 'Marco', 'testo': 'a'}, {'inizio_ms': 10000, 'fine_ms': 12000, 'chi': 'Marco', 'testo': 'b'}], [Sezione('Progetti', ['P'], [10000])]);
      await x.aggiungiSegno(id, 10000, 'segna');
      await x.taglia(id, 4000, null);
      expect((await x.segmenti(id)).map((s) => s.inizioMs), [-2000, 6000]);
      expect((await x.segmenti(id)).last.fineMs, 8000);
      expect((await x.riassunti(id)).single.sezioni.single.ms, [6000]);
      expect((await x.segni(id)).single.ms, 6000);
      await x.taglia(id, 0, null);
      expect((await x.segmenti(id)).map((s) => s.inizioMs), [2000, 10000]);
      expect((await x.riassunti(id)).single.sezioni.single.ms, [10000]);
      expect((await x.segni(id)).single.ms, 10000);
    });

    test('una nota sola arrivata già tagliata tiene anche le frasi tagliate', () {
      final fatto = Cloud.componi([Parte({'id': 1, 'percorso': 'a', 'inizio_ms': 10000, 'fine_ms': 30000})], [risposta(60, [5, 12], 12)]);
      expect(fatto.segmenti.map((s) => s['inizio_ms']), [-5000, 2000]);
    });

    test('cestino allineato: chi ha cambiato per ultimo decide, e niente sparisce da solo', () {
      String a(int ora, int? prima, bool qui) => Cloud.azioneCestino(ora: ora, prima: prima, nelCestino: qui);
      expect(a(0, 0, false), '');
      expect(a(0, 0, true), 'cestina-la', reason: 'cancellata sul telefono');
      expect(a(1, 0, false), 'cestina-qui', reason: 'cancellata su DiGiShare');
      expect(a(0, 1, true), 'ripristina-qui', reason: 'ripristinata su DiGiShare');
      expect(a(1, 1, false), 'ripristina-la', reason: 'ripristinata sul telefono');
      expect(a(2, 0, false), 'cestina-qui', reason: 'tolta per sempre da DiGiShare: sul telefono resta nel cestino');
      expect(a(0, null, true), 'cestina-la');
      expect(a(1, null, false), 'cestina-qui');
      expect(a(1, 1, true), '');
    });

    test('unendo le note, gli originali non toccano più i file su DiGiShare', () async {
      final a = await x.nuovaNota(titolo: 'a', tipo: 'appuntamento', stato: Stato.pronta);
      final b = await x.nuovaNota(titolo: 'b', tipo: 'appuntamento', stato: Stato.pronta);
      for (final (n, u) in [(a, 'aaa'), (b, 'bbb')]) {
        await x.aggiornaParte(await x.aggiungiParte(n, '/$u.ogg'), {'tus_url': 'https://x/api/caricamenti/$u'});
      }
      final u = await x.unisci([(await x.nota(a))!, (await x.nota(b))!], 'unita');
      expect((await x.noteDaAllineare()).map((n) => n.id), [u]);
    });

    test('una nota vocale senza riassunto resta senza riassunto', () async {
      final id = await x.nuovaNota(titolo: 't', tipo: 'idea', stato: Stato.caricata);
      await x.salvaRisultato(id, [{'inizio_ms': 0, 'chi': 'Voce', 'testo': 'hola', 'traduzione': 'ciao'}], []);
      expect(await x.riassunti(id), isEmpty);
      final s = (await x.segmenti(id)).single;
      expect(s.traduzione, 'ciao');
      await x.modificaSegmento(s.id, 'buenas');
      expect((await x.segmenti(id)).single.traduzione, isNull);
    });
  });

  group('DiGiShare', () {
    const base = 'https://ds.prova';

    test('accesso: manda i dati, tiene sessione, dispositivo e token', () async {
      late Map<String, dynamic> corpo;
      final c = ClientDiGiShare(
        base: base,
        client: MockClient((r) async {
          expect(r.url.path, '/api/auth/login');
          expect(r.headers['Origin'], base);
          corpo = jsonDecode(r.body) as Map<String, dynamic>;
          return http.Response('{"csrf":"tok"}', 200, headers: {'set-cookie': 'sess=abc; Path=/; Expires=Thu, 01 Jan 2030 00:00:00 GMT; HttpOnly,dev=xyz; Path=/'});
        }),
      );
      await c.accedi(utente: 'admin', password: 'p', codice: '123456');
      expect(corpo['username'], 'admin');
      expect(corpo['code'], '123456');
      expect(corpo['remember'], true);
      expect(c.csrf, 'tok');
      expect(c.cookie, contains('sess=abc'));
      expect(c.cookie, contains('dev=xyz'));
    });

    test('accesso sbagliato: riporta il messaggio del server', () async {
      final c = ClientDiGiShare(base: base, client: MockClient((_) async => http.Response('{"error":"Password errata."}', 401)));
      expect(c.accedi(utente: 'a', password: 'b'), throwsA(predicate((e) => '$e' == 'Password errata.')));
    });

    Future<File> fileProva(int n) async {
      final d = await Directory.systemTemp.createTemp('dg');
      addTearDown(() => d.delete(recursive: true));
      return File('${d.path}/a.ogg')..writeAsBytesSync(List.filled(n, 7));
    }

    test('caricamento tus: crea, salva l\'indirizzo subito, manda i byte col token', () async {
      final f = await fileProva(1000);
      final viste = <String>[];
      final ricevuti = <int>[];
      final c = ClientDiGiShare(
        base: base,
        cookie: 'sess=1',
        client: MockClient((r) async {
          viste.add(r.method);
          expect(r.headers['Tus-Resumable'], '1.0.0');
          expect(r.headers['Cookie'], 'sess=1');
          if (r.method == 'POST') {
            expect(r.headers['Upload-Length'], '1000');
            final meta = r.headers['Upload-Metadata']!.split(',').map((e) => e.split(' ')).firstWhere((e) => e[0] == 'filename');
            expect(utf8.decode(base64.decode(meta[1])), 'nota.ogg');
            return http.Response('', 201, headers: {'location': '/api/caricamenti/xyz'});
          }
          expect(r.headers['x-csrf-token'], 'tok');
          expect(r.headers['Upload-Offset'], '0');
          ricevuti.addAll(r.bodyBytes);
          return http.Response('', 204, headers: {'upload-offset': '1000'});
        }),
      )..csrf = 'tok';
      String? salvato;
      double? ultimo;
      final u = await c.carica(f, nome: 'nota.ogg', salva: (x) => salvato = x, avanzamento: (a, t) => ultimo = a / t);
      expect(u, '$base/api/caricamenti/xyz');
      expect(salvato, u);
      expect(viste, ['POST', 'PATCH']);
      expect(ricevuti.length, 1000);
      expect(ultimo, 1);
    });

    test('caricamento interrotto: riprende dal punto che dice il server', () async {
      final f = await fileProva(1000);
      final offs = <String?>[];
      var n = 0;
      final c = ClientDiGiShare(
        base: base,
        client: MockClient((r) async {
          if (r.method == 'HEAD') return http.Response('', 200, headers: {'upload-offset': '400'});
          n += r.bodyBytes.length;
          offs.add(r.headers['Upload-Offset']);
          return http.Response('', 204, headers: {'upload-offset': '1000'});
        }),
      );
      await c.carica(f, nome: 'a.ogg', riprendi: '$base/api/caricamenti/xyz');
      expect(offs, ['400']);
      expect(n, 600);
    });

    test('caricamento scaduto sul server: ricomincia da capo', () async {
      final f = await fileProva(10);
      final viste = <String>[];
      final c = ClientDiGiShare(
        base: base,
        client: MockClient((r) async {
          viste.add(r.method);
          if (r.method == 'HEAD') return http.Response('', 404);
          if (r.method == 'POST') return http.Response('', 201, headers: {'location': '/api/caricamenti/nuovo'});
          return http.Response('', 204, headers: {'upload-offset': '10'});
        }),
      );
      final u = await c.carica(f, nome: 'a.ogg', riprendi: '$base/api/caricamenti/vecchio');
      expect(viste, ['HEAD', 'POST', 'PATCH']);
      expect(u, endsWith('nuovo'));
    });

    test('link: trova il file per nome e restituisce l\'indirizzo', () async {
      final c = ClientDiGiShare(
        base: base,
        client: MockClient((r) async {
          if (r.method == 'GET') return http.Response(jsonEncode({'file': [{'id': 'f1', 'nome': 'a.ogg'}]}), 200);
          expect(r.url.path, '/api/file/f1/link');
          expect(jsonDecode(r.body)['chi'], 'chiunque');
          return http.Response(jsonEncode({'link': [{'url': '$base/v/abc'}]}), 200);
        }),
      );
      expect(await c.creaLink('a.ogg'), '$base/v/abc');
      expect(c.creaLink('altro.ogg'), throwsA(isA<ErroreDiGiShare>()));
    });
  });
}
