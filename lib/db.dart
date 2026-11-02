import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Stati di una nota. L'audio è sempre sul telefono: si cancella solo dal cestino.
class Stato {
  static const registrazione = 'registrazione'; // ancora in corso, o interrotta da un riavvio
  static const daInviare = 'da_inviare'; // finita: sta sul telefono finché l'utente non dice Invia
  static const registrata = 'registrata'; // confermata, da caricare
  static const caricamento = 'caricamento';
  static const caricata = 'caricata'; // in DiGiShare, testo e riassunto in attesa
  static const pronta = 'pronta'; // ha testo e riassunto
  static String etichetta(String s) => switch (s) {
        registrazione => 'In corso',
        daInviare => 'Da inviare',
        registrata => 'Sul telefono',
        caricamento => 'In invio',
        caricata => 'In sincronizzazione',
        pronta => 'Pronta',
        _ => s,
      };
}

class Nota {
  Nota(this.m);
  final Map<String, Object?> m;
  int get id => m['id'] as int;
  String get titolo => m['titolo'] as String;
  String get tipo => m['tipo'] as String;
  bool get appuntamento => tipo == 'appuntamento';
  DateTime get creata => DateTime.fromMillisecondsSinceEpoch(m['creata'] as int);
  int get durataMs => m['durata_ms'] as int;
  int? get cartella => m['cartella'] as int?;
  String get stato => m['stato'] as String;
  bool get esempio => m['esempio'] == 1;
  int? get cestinata => m['cestinata'] as int?;
  String? get modello => m['modello'] as String?;

  /// Come l'ha vista l'ultimo controllo su DiGiShare: 0 c'è, 1 nel suo cestino, 2 non c'è più o non si segue. Null: mai vista.
  int? get remoto => m['remoto'] as int?;
}

class Parte {
  Parte(this.m);
  final Map<String, Object?> m;
  int get id => m['id'] as int;
  String get percorso => m['percorso'] as String;
  int get inizioMs => m['inizio_ms'] as int;
  int? get fineMs => m['fine_ms'] as int?;
  String? get tusUrl => m['tus_url'] as String?;
  bool get inviata => m['inviata'] == 1;
  int get pulita => (m['pulita'] as int?) ?? 0; // 0 da controllare, 1 copia pulita sul telefono, 2 niente copia
}

class Segmento {
  Segmento(this.m);
  final Map<String, Object?> m;
  int get id => m['id'] as int;
  int get inizioMs => m['inizio_ms'] as int;
  int? get fineMs => m['fine_ms'] as int?;
  String get chi => m['chi'] as String;
  String get testo => m['testo'] as String;
  String? get traduzione => m['traduzione'] as String?;
}

class Sezione {
  Sezione(this.titolo, this.righe, [this.ms]);
  final String titolo;
  final List<String> righe;
  final List<int>? ms; // dove se ne parla nell'audio, riga per riga
  Map<String, Object?> toJson() => {'titolo': titolo, 'righe': righe, if (ms != null) 'ms': ms};
  factory Sezione.da(Map<String, dynamic> j) => Sezione(j['titolo'] as String, (j['righe'] as List).cast<String>(), (j['ms'] as List?)?.cast<int>());
}

class Riassunto {
  Riassunto(this.m);
  final Map<String, Object?> m;
  int get id => m['id'] as int;
  String get modello => m['modello'] as String;
  List<Sezione> get sezioni => (jsonDecode(m['sezioni'] as String) as List).map((e) => Sezione.da(e as Map<String, dynamic>)).toList();
}

class Segno {
  Segno(this.m);
  final Map<String, Object?> m;
  int get id => m['id'] as int;
  int get ms => m['ms'] as int;
  String get tipo => m['tipo'] as String;
  String get testo => (m['testo'] as String?) ?? '';
  String? get percorso => m['percorso'] as String?;
}

class Cartella {
  Cartella(this.m);
  final Map<String, Object?> m;
  int get id => m['id'] as int;
  String get nome => m['nome'] as String;
  int get icona => (m['icona'] as int?) ?? 0;
  int get conta => (m['conta'] as int?) ?? 0;
}

class Modello {
  Modello(this.m);
  final Map<String, Object?> m;
  int get id => m['id'] as int;
  String get nome => m['nome'] as String;
  String get descrizione => m['descrizione'] as String;
  String get istruzioni => m['istruzioni'] as String;
  bool get proprio => m['proprio'] == 1;
  String? get foto => m['foto'] as String?;
}

class Risultato {
  Risultato(this.nota, this.frase, this.ms);
  final Nota nota;
  final String? frase;
  final int? ms;
}

class Db {
  Db(this.d);
  final Database d;

  static const _modelli = [
    ['Appuntamento', 'Decisioni e cose da fare', 'Riassumi l\'appuntamento: partecipanti, decisioni prese, cose da fare con chi e quando, dati importanti.'],
    ['Punti chiave', 'Sintesi in pochi punti', 'Riassumi in massimo otto punti brevi, in ordine di importanza.'],
    ['Colloquio cliente', 'Richieste, dati, seguito', 'Riporta richieste del cliente, dati forniti, obiezioni, impegni presi e prossimo contatto.'],
    ['Sopralluogo', 'Luogo, stato, interventi', 'Riporta luogo e data, stato constatato, problemi, interventi necessari e responsabili.'],
    ['Idea', 'Titolo e testo in ordine', 'Dai un titolo e riscrivi l\'idea in ordine, senza aggiungere niente.'],
    ['Dati e numeri', 'Cifre, date, importi', 'Elenca tutte le cifre, le date, gli importi e a cosa si riferiscono.'],
    ['Azioni e prossimi passi', 'Chi fa cosa e quando', 'Elenca solo le azioni da fare, con responsabile e scadenza se dette.'],
    ['Domande aperte', 'Cosa resta da chiarire', 'Elenca le domande rimaste senza risposta e i punti da chiarire.'],
  ];

  static Future<void> crea(Database d, int _) async {
    await d.execute('''CREATE TABLE nota(id INTEGER PRIMARY KEY AUTOINCREMENT, titolo TEXT NOT NULL, tipo TEXT NOT NULL,
      creata INTEGER NOT NULL, durata_ms INTEGER NOT NULL DEFAULT 0, cartella INTEGER, stato TEXT NOT NULL, esempio INTEGER NOT NULL DEFAULT 0,
      cestinata INTEGER, modello TEXT, remoto INTEGER)''');
    await d.execute('''CREATE TABLE parte(id INTEGER PRIMARY KEY AUTOINCREMENT, nota INTEGER NOT NULL, percorso TEXT NOT NULL, ordine INTEGER NOT NULL,
      inizio_ms INTEGER NOT NULL DEFAULT 0, fine_ms INTEGER, tus_url TEXT, inviata INTEGER NOT NULL DEFAULT 0, pulita INTEGER NOT NULL DEFAULT 0)''');
    await d.execute('''CREATE TABLE segmento(id INTEGER PRIMARY KEY AUTOINCREMENT, nota INTEGER NOT NULL, inizio_ms INTEGER NOT NULL, fine_ms INTEGER, chi TEXT NOT NULL, testo TEXT NOT NULL, traduzione TEXT)''');
    await d.execute('CREATE TABLE riassunto(id INTEGER PRIMARY KEY AUTOINCREMENT, nota INTEGER NOT NULL, modello TEXT NOT NULL, sezioni TEXT NOT NULL, creato INTEGER NOT NULL)');
    await d.execute('CREATE TABLE segno(id INTEGER PRIMARY KEY AUTOINCREMENT, nota INTEGER NOT NULL, ms INTEGER NOT NULL, tipo TEXT NOT NULL, testo TEXT, percorso TEXT)');
    await d.execute('CREATE TABLE cartella(id INTEGER PRIMARY KEY AUTOINCREMENT, nome TEXT NOT NULL, icona INTEGER NOT NULL DEFAULT 0)');
    await d.execute('CREATE TABLE modello(id INTEGER PRIMARY KEY AUTOINCREMENT, nome TEXT NOT NULL, descrizione TEXT NOT NULL, istruzioni TEXT NOT NULL, proprio INTEGER NOT NULL DEFAULT 0, foto TEXT)');
    await d.execute('CREATE TABLE glossario(id INTEGER PRIMARY KEY AUTOINCREMENT, termine TEXT NOT NULL UNIQUE)');
    await d.execute('CREATE TABLE memoria(id INTEGER PRIMARY KEY AUTOINCREMENT, testo TEXT NOT NULL)');
    await d.execute('CREATE TABLE skill(id INTEGER PRIMARY KEY AUTOINCREMENT, testo TEXT NOT NULL UNIQUE)');
    await d.execute('CREATE TABLE voce(id INTEGER PRIMARY KEY AUTOINCREMENT, nome TEXT NOT NULL UNIQUE)');
    await d.execute('CREATE TABLE chat(id INTEGER PRIMARY KEY AUTOINCREMENT, nota INTEGER, domanda TEXT NOT NULL, risposta TEXT NOT NULL, fonti TEXT NOT NULL, creata INTEGER NOT NULL)');
    await d.execute('CREATE INDEX i_seg ON segmento(nota)');
    await d.execute('CREATE INDEX i_parte ON parte(nota)');
    for (final m in _modelli) {
      await d.insert('modello', {'nome': m[0], 'descrizione': m[1], 'istruzioni': m[2]});
    }
    await _esempio(d);
  }

  /// La registrazione di esempio, serve a provare testo, riassunto,
  /// mappa e domande prima che DiGiShare faccia il lavoro vero. Si vede che è di esempio e si può cancellare.
  static Future<void> _esempio(Database d) async {
    final ora = DateTime.now().millisecondsSinceEpoch;
    final id = await d.insert('nota', {'titolo': 'Esempio: rinnovo polizza', 'tipo': 'appuntamento', 'creata': ora, 'durata_ms': 240000, 'stato': Stato.pronta, 'esempio': 1, 'modello': 'Appuntamento'});
    const righe = [
      [192000, 'Marco', 'Allora, per il rinnovo possiamo restare a milleduecentoquaranta franchi.'],
      [201000, 'Cliente', 'Va bene, ma la franchigia si può abbassare?'],
      [209000, 'Marco', 'Sì, la portiamo a trecento franchi.'],
      [216000, 'Cliente', 'Perfetto. Le mando la copia della licenza.'],
      [224000, 'Marco', 'Io le invio il contratto entro venerdì.'],
    ];
    for (final r in righe) {
      await d.insert('segmento', {'nota': id, 'inizio_ms': r[0], 'chi': r[1], 'testo': r[2]});
    }
    await d.insert('riassunto', {
      'nota': id,
      'modello': 'Appuntamento',
      'creato': ora,
      'sezioni': jsonEncode([
        Sezione('Progetti', ['Rinnovo della polizza']),
        Sezione('Punti discussi', ['Premio confermato.', 'Franchigia abbassata.']),
        Sezione('Dati e cifre', ['Premio CHF 1\'240', 'Franchigia CHF 300']),
        Sezione('Cose da fare', ['Marco: inviare il contratto entro venerdì.', 'Cliente: mandare la copia della licenza.']),
      ]),
    });
    await d.insert('segno', {'nota': id, 'ms': 209000, 'tipo': 'segna', 'testo': 'Franchigia concordata'});
  }

  static Future<Db> apri({String? percorso, DatabaseFactory? fabbrica}) async {
    final f = fabbrica ?? databaseFactory;
    final dove = percorso ?? p.join(await f.getDatabasesPath(), 'diginotes.db');
    final d = await f.openDatabase(dove, options: OpenDatabaseOptions(
      version: 4,
      onCreate: crea,
      onUpgrade: (d, da, _) async {
        if (da < 2) await d.execute('ALTER TABLE parte ADD COLUMN pulita INTEGER NOT NULL DEFAULT 0');
        if (da < 3) await d.execute('ALTER TABLE segmento ADD COLUMN traduzione TEXT');
        if (da < 4) await d.execute('ALTER TABLE nota ADD COLUMN remoto INTEGER');
      },
    ));
    return Db(d);
  }

  // --- note ---
  Future<int> nuovaNota({required String titolo, required String tipo, String stato = Stato.registrazione, int? cartella, String? modello}) =>
      d.insert('nota', {'titolo': titolo, 'tipo': tipo, 'creata': DateTime.now().millisecondsSinceEpoch, 'stato': stato, 'cartella': cartella, 'modello': modello});

  Future<void> aggiornaNota(int id, Map<String, Object?> v) => d.update('nota', v, where: 'id=?', whereArgs: [id]);

  Future<Nota?> nota(int id) async {
    final r = await d.query('nota', where: 'id=?', whereArgs: [id]);
    return r.isEmpty ? null : Nota(r.first);
  }

  /// [cartella]: null tutte, -1 senza cartella. [tipo]: null tutti.
  Future<List<Nota>> note({int? cartella, String? tipo, bool crescente = false, String ordine = 'creata'}) async {
    final dove = <String>['cestinata IS NULL', "stato <> 'registrazione'"];
    final arg = <Object?>[];
    if (cartella == -1) {
      dove.add('cartella IS NULL');
    } else if (cartella != null) {
      dove.add('cartella=?');
      arg.add(cartella);
    }
    if (tipo != null) {
      dove.add('tipo=?');
      arg.add(tipo);
    }
    final col = ordine == 'titolo' ? 'titolo COLLATE NOCASE' : (ordine == 'durata' ? 'durata_ms' : 'creata');
    final r = await d.query('nota', where: dove.join(' AND '), whereArgs: arg, orderBy: '$col ${crescente ? 'ASC' : 'DESC'}');
    return r.map(Nota.new).toList();
  }

  Future<List<Nota>> daInviare() async {
    final r = await d.query('nota', where: "cestinata IS NULL AND esempio=0 AND stato IN ('registrata','caricamento')", orderBy: 'creata');
    return r.map(Nota.new).toList();
  }

  Future<List<Nota>> inAttesaDiDiGiShare() async {
    final r = await d.query('nota', where: "cestinata IS NULL AND esempio=0 AND stato=?", whereArgs: [Stato.caricata], orderBy: 'creata');
    return r.map(Nota.new).toList();
  }

  /// Testo e riassunto arrivati da DiGiShare: sostituiscono quelli che c'erano, e la nota è pronta.
  Future<void> salvaRisultato(int nota, List<Map<String, Object?>> segmenti, List<Sezione> sezioni, {String? titolo}) => d.transaction((t) async {
        await t.delete('segmento', where: 'nota=?', whereArgs: [nota]);
        await t.delete('riassunto', where: 'nota=?', whereArgs: [nota]);
        for (final s in segmenti) {
          await t.insert('segmento', {...s, 'nota': nota});
        }
        if (sezioni.isNotEmpty) {
          await t.insert('riassunto', {'nota': nota, 'modello': 'Riassunto', 'sezioni': jsonEncode(sezioni), 'creato': DateTime.now().millisecondsSinceEpoch});
        }
        await t.update('nota', {'stato': Stato.pronta, if (titolo != null && titolo.isNotEmpty) 'titolo': titolo}, where: 'id=?', whereArgs: [nota]);
      });

  /// Le note già su DiGiShare, anche nel cestino: il cestino si tiene allineato nei due sensi.
  Future<List<Nota>> noteDaAllineare() async {
    final r = await d.rawQuery("SELECT n.* FROM nota n WHERE n.esempio=0 AND n.stato IN (?, ?) AND (n.remoto IS NULL OR n.remoto<>2) AND EXISTS (SELECT 1 FROM parte p WHERE p.nota=n.id AND p.tus_url IS NOT NULL)", [Stato.caricata, Stato.pronta]);
    return r.map(Nota.new).toList();
  }

  Future<List<Parte>> partiDaPulire() async {
    final r = await d.rawQuery("SELECT p.* FROM parte p JOIN nota n ON n.id=p.nota WHERE p.pulita=0 AND p.tus_url IS NOT NULL AND n.cestinata IS NULL AND n.stato=?", [Stato.pronta]);
    return r.map(Parte.new).toList();
  }

  /// La copia pulita prende il posto del file: anche nelle note unite che usano lo stesso audio.
  Future<void> sostituisciAudio(String vecchio, String nuovo) => d.update('parte', {'percorso': nuovo, 'pulita': 1}, where: 'percorso=?', whereArgs: [vecchio]);

  /// Una registrazione rimasta «in corso» dopo un riavvio o un crash non si perde: il file è già su disco.
  Future<int> recuperaInterrotte() => d.rawUpdate("UPDATE nota SET stato='da_inviare', titolo=titolo || ' (interrotta)' WHERE stato='registrazione'");

  Future<void> cestina(int id) => aggiornaNota(id, {'cestinata': DateTime.now().millisecondsSinceEpoch});
  Future<void> ripristina(int id) => d.rawUpdate('UPDATE nota SET cestinata=NULL WHERE id=?', [id]);

  Future<List<Nota>> cestino() async => (await d.query('nota', where: 'cestinata IS NOT NULL', orderBy: 'cestinata DESC')).map(Nota.new).toList();

  /// Toglie la nota e restituisce i file da cancellare.
  Future<List<String>> eliminaDefinitivamente(int id) async {
    final file = <String>[];
    for (final x in await parti(id)) {
      file.add(x.percorso);
    }
    for (final s in await segni(id)) {
      if (s.percorso != null) file.add(s.percorso!);
    }
    await d.transaction((t) async {
      for (final tab in ['parte', 'segmento', 'riassunto', 'segno', 'chat']) {
        await t.delete(tab, where: 'nota=?', whereArgs: [id]);
      }
      await t.delete('nota', where: 'id=?', whereArgs: [id]);
    });
    return file;
  }

  /// Unisce più note in una nuova: audio in fila, testo con gli orari spostati. Gli originali vanno nel cestino.
  Future<int> unisci(List<Nota> daUnire, String titolo) async {
    final ordinate = [...daUnire]..sort((a, b) => a.creata.compareTo(b.creata));
    return d.transaction((t) async {
      final id = await t.insert('nota', {
        'titolo': titolo,
        'tipo': ordinate.first.tipo,
        'creata': ordinate.first.creata.millisecondsSinceEpoch, // la data è quella della più vecchia
        'durata_ms': ordinate.fold<int>(0, (a, n) => a + n.durataMs),
        'cartella': ordinate.first.cartella,
        // Unire non conferma niente: se un pezzo aspetta Invia, lo aspetta anche la nota unita.
        'stato': ordinate.every((n) => n.stato == Stato.pronta) ? Stato.pronta : (ordinate.any((n) => n.stato == Stato.daInviare) ? Stato.daInviare : Stato.registrata),
      });
      var scarto = 0;
      var ordine = 0;
      for (final n in ordinate) {
        for (final x in await t.query('parte', where: 'nota=?', whereArgs: [n.id], orderBy: 'ordine')) {
          // Il pezzo già in DiGiShare resta quello: non si ricarica, e le correzioni sanno dove andare.
          await t.insert('parte', {'nota': id, 'percorso': x['percorso'], 'ordine': ordine++, 'inizio_ms': x['inizio_ms'], 'fine_ms': x['fine_ms'], 'tus_url': x['tus_url'], 'inviata': x['inviata'], 'pulita': x['pulita']});
        }
        for (final x in await t.query('segmento', where: 'nota=?', whereArgs: [n.id], orderBy: 'inizio_ms')) {
          await t.insert('segmento', {'nota': id, 'inizio_ms': (x['inizio_ms'] as int) + scarto, 'chi': x['chi'], 'testo': x['testo'], 'traduzione': x['traduzione']});
        }
        for (final x in await t.query('segno', where: 'nota=?', whereArgs: [n.id])) {
          await t.insert('segno', {'nota': id, 'ms': (x['ms'] as int) + scarto, 'tipo': x['tipo'], 'testo': x['testo'], 'percorso': x['percorso']});
        }
        scarto += n.durataMs;
        // I suoi file ora li usa la nota unita: il cestino di questa nota non deve toccarli su DiGiShare.
        await t.update('nota', {'cestinata': DateTime.now().millisecondsSinceEpoch, 'remoto': 2}, where: 'id=?', whereArgs: [n.id]);
      }
      return id;
    });
  }

  // --- parti audio ---
  Future<int> aggiungiParte(int nota, String percorso) async {
    final c = Sqflite.firstIntValue(await d.rawQuery('SELECT COUNT(*) FROM parte WHERE nota=?', [nota])) ?? 0;
    return d.insert('parte', {'nota': nota, 'percorso': percorso, 'ordine': c});
  }

  Future<List<Parte>> parti(int nota) async => (await d.query('parte', where: 'nota=?', whereArgs: [nota], orderBy: 'ordine')).map(Parte.new).toList();
  Future<void> aggiornaParte(int id, Map<String, Object?> v) => d.update('parte', v, where: 'id=?', whereArgs: [id]);

  /// Taglio che non tocca il file: l'originale resta e il taglio si può togliere.
  Future<void> taglia(int nota, int inizioMs, int? fineMs) async {
    final pp = await parti(nota);
    if (pp.isEmpty) return;
    // Gli orari restano legati all'audio: si spostano senza togliere niente, così togliendo il taglio tutto torna com'era.
    final sposta = pp.first.inizioMs - inizioMs;
    final riassunti = await this.riassunti(nota);
    await d.transaction((t) async {
      await t.update('parte', {'inizio_ms': inizioMs, 'fine_ms': fineMs}, where: 'id=?', whereArgs: [pp.first.id]);
      await t.rawUpdate('UPDATE segmento SET inizio_ms=inizio_ms+?, fine_ms=fine_ms+? WHERE nota=?', [sposta, sposta, nota]);
      await t.rawUpdate('UPDATE segno SET ms=ms+? WHERE nota=?', [sposta, nota]);
      for (final r in riassunti) {
        final nuove = [for (final s in r.sezioni) Sezione(s.titolo, s.righe, s.ms?.map((m) => m + sposta).toList())];
        await t.update('riassunto', {'sezioni': jsonEncode(nuove)}, where: 'id=?', whereArgs: [r.id]);
      }
    });
  }

  // --- testo ---
  Future<List<Segmento>> segmenti(int nota) async => (await d.query('segmento', where: 'nota=?', whereArgs: [nota], orderBy: 'inizio_ms')).map(Segmento.new).toList();
  Future<void> modificaSegmento(int id, String testo) => d.update('segmento', {'testo': testo, 'traduzione': null}, where: 'id=?', whereArgs: [id]);
  Future<void> rinominaChi(int nota, String da, String a) => d.update('segmento', {'chi': a}, where: 'nota=? AND chi=?', whereArgs: [nota, da]);

  /// Sostituisce in tutta la nota, senza distinguere maiuscole. Restituisce quante frasi ha cambiato.
  Future<int> sostituisci(int nota, String da, String a) async {
    if (da.isEmpty) return 0;
    final re = RegExp(RegExp.escape(da), caseSensitive: false);
    var n = 0;
    for (final s in await segmenti(nota)) {
      if (re.hasMatch(s.testo)) {
        await modificaSegmento(s.id, s.testo.replaceAll(re, a));
        n++;
      }
    }
    return n;
  }

  Future<List<Riassunto>> riassunti(int nota) async => (await d.query('riassunto', where: 'nota=?', whereArgs: [nota], orderBy: 'id')).map(Riassunto.new).toList();

  Future<List<Segno>> segni(int nota) async => (await d.query('segno', where: 'nota=?', whereArgs: [nota], orderBy: 'ms')).map(Segno.new).toList();
  Future<int> aggiungiSegno(int nota, int ms, String tipo, {String? testo, String? percorso}) => d.insert('segno', {'nota': nota, 'ms': ms, 'tipo': tipo, 'testo': testo, 'percorso': percorso});
  Future<void> eliminaSegno(int id) => d.delete('segno', where: 'id=?', whereArgs: [id]);

  // --- cartelle ---
  Future<List<Cartella>> cartelle() async {
    final r = await d.rawQuery('SELECT c.*, (SELECT COUNT(*) FROM nota n WHERE n.cartella=c.id AND n.cestinata IS NULL AND n.stato<>\'registrazione\') conta FROM cartella c ORDER BY nome COLLATE NOCASE');
    return r.map(Cartella.new).toList();
  }

  Future<int> nuovaCartella(String nome, int icona) => d.insert('cartella', {'nome': nome, 'icona': icona});
  Future<void> modificaCartella(int id, String nome, int icona) => d.update('cartella', {'nome': nome, 'icona': icona}, where: 'id=?', whereArgs: [id]);

  /// Le note restano, senza cartella.
  Future<void> eliminaCartella(int id) async {
    await d.rawUpdate('UPDATE nota SET cartella=NULL WHERE cartella=?', [id]);
    await d.delete('cartella', where: 'id=?', whereArgs: [id]);
  }

  Future<void> sposta(List<int> note, int? cartella) async {
    for (final id in note) {
      await d.rawUpdate('UPDATE nota SET cartella=? WHERE id=?', [cartella, id]);
    }
  }

  Future<Map<String, int>> conteggi() async {
    final tutte = Sqflite.firstIntValue(await d.rawQuery("SELECT COUNT(*) FROM nota WHERE cestinata IS NULL AND stato<>'registrazione'")) ?? 0;
    final senza = Sqflite.firstIntValue(await d.rawQuery("SELECT COUNT(*) FROM nota WHERE cestinata IS NULL AND cartella IS NULL AND stato<>'registrazione'")) ?? 0;
    final cest = Sqflite.firstIntValue(await d.rawQuery('SELECT COUNT(*) FROM nota WHERE cestinata IS NOT NULL')) ?? 0;
    return {'tutte': tutte, 'senza': senza, 'cestino': cest};
  }

  // --- modelli ---
  Future<List<Modello>> modelli() async => (await d.query('modello', orderBy: 'proprio, id')).map(Modello.new).toList();
  Future<int> salvaModello({int? id, required String nome, required String descrizione, required String istruzioni, String? foto}) async {
    final v = {'nome': nome, 'descrizione': descrizione, 'istruzioni': istruzioni, 'proprio': 1, 'foto': foto};
    if (id == null) return d.insert('modello', v);
    await d.update('modello', v, where: 'id=?', whereArgs: [id]);
    return id;
  }

  Future<void> eliminaModello(int id) => d.delete('modello', where: 'id=? AND proprio=1', whereArgs: [id]);

  // --- liste semplici: glossario, memoria, voci ---
  Future<List<Map<String, Object?>>> lista(String tab) => d.query(tab, orderBy: 'id DESC');
  Future<void> aggiungiLista(String tab, String colonna, String valore) => d.insert(tab, {colonna: valore}, conflictAlgorithm: ConflictAlgorithm.ignore);
  Future<void> eliminaLista(String tab, int id) => d.delete(tab, where: 'id=?', whereArgs: [id]);
  Future<int> contaLista(String tab) async => Sqflite.firstIntValue(await d.rawQuery('SELECT COUNT(*) FROM $tab')) ?? 0;

  /// Totali per le statistiche del profilo; i giorni servono per la mappa delle attività.
  Future<Map<String, int>> statistiche() async {
    final r = (await d.rawQuery("SELECT COUNT(*) n, COALESCE(SUM(durata_ms),0) ms, COUNT(DISTINCT date(creata/1000,'unixepoch','localtime')) g FROM nota WHERE cestinata IS NULL AND esempio=0 AND stato<>'registrazione'")).first;
    return {'note': r['n'] as int, 'ms': r['ms'] as int, 'giorni': r['g'] as int};
  }

  // --- ricerca ---
  static String _like(String s) => '%${s.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%';

  /// Cerca nei titoli e dentro testi e riassunti; per ogni nota tiene la prima frase trovata.
  Future<List<Risultato>> cerca(String q, {int? cartella, DateTime? dal, bool soloConTesto = false}) async {
    final l = _like(q);
    final dove = ['cestinata IS NULL', "stato<>'registrazione'"];
    final arg = <Object?>[];
    if (cartella != null) {
      dove.add('cartella=?');
      arg.add(cartella);
    }
    if (dal != null) {
      dove.add('creata>=?');
      arg.add(dal.millisecondsSinceEpoch);
    }
    final r = await d.query('nota', where: dove.join(' AND '), whereArgs: arg, orderBy: 'creata DESC');
    final out = <Risultato>[];
    for (final m in r) {
      final n = Nota(m);
      final seg = await d.query('segmento', where: r"nota=? AND testo LIKE ? ESCAPE '\'", whereArgs: [n.id, l], orderBy: 'inizio_ms', limit: 1);
      if (seg.isNotEmpty) {
        out.add(Risultato(n, seg.first['testo'] as String, seg.first['inizio_ms'] as int));
        continue;
      }
      final ria = await d.query('riassunto', where: r"nota=? AND sezioni LIKE ? ESCAPE '\'", whereArgs: [n.id, l], limit: 1);
      if (ria.isNotEmpty) {
        out.add(Risultato(n, 'Trovato nel riassunto', null));
        continue;
      }
      if (!soloConTesto && n.titolo.toLowerCase().contains(q.toLowerCase())) out.add(Risultato(n, null, null));
    }
    return out;
  }

  static final _vuote = {'della', 'delle', 'dello', 'degli', 'nella', 'nelle', 'sono', 'cosa', 'come', 'quando', 'dove', 'perché', 'quale', 'quali', 'quanto', 'questa', 'questo', 'devo', 'fare', 'detto', 'hanno', 'abbiamo', 'anche', 'allora'};

  /// La parte di «Chiedi» che funziona sul telefono: trova le frasi più pertinenti e dice da dove vengono.
  Future<List<Risultato>> frasiPertinenti(String domanda, {int? nota, int quante = 4}) async {
    final parole = RegExp(r"[\p{L}\p{N}']+", unicode: true).allMatches(domanda.toLowerCase()).map((m) => m.group(0)!).where((w) => w.length > 3 && !_vuote.contains(w)).toSet();
    if (parole.isEmpty) return [];
    final righe = await d.rawQuery(
      "SELECT s.* FROM segmento s JOIN nota n ON n.id=s.nota WHERE n.cestinata IS NULL${nota != null ? ' AND n.id=?' : ''}",
      nota != null ? [nota] : [],
    );
    final punti = <(int, Map<String, Object?>)>[];
    for (final r in righe) {
      final t = (r['testo'] as String).toLowerCase();
      final x = parole.where(t.contains).length;
      if (x > 0) punti.add((x, r));
    }
    punti.sort((a, b) => b.$1.compareTo(a.$1));
    final out = <Risultato>[];
    for (final (_, r) in punti.take(quante)) {
      final n = await this.nota(r['nota'] as int);
      if (n != null) out.add(Risultato(n, r['testo'] as String, r['inizio_ms'] as int));
    }
    return out;
  }

  /// Le righe di una sezione dei riassunti («Cose da fare», «Dati chiave», «Decisioni»).
  Future<List<Risultato>> dalleSezioni(String titolo, {int? nota}) async {
    final r = await d.rawQuery(
      "SELECT r.* FROM riassunto r JOIN nota n ON n.id=r.nota WHERE n.cestinata IS NULL${nota != null ? ' AND n.id=?' : ''} ORDER BY n.creata DESC",
      nota != null ? [nota] : [],
    );
    final out = <Risultato>[];
    final visti = <String>{};
    for (final m in r) {
      final ria = Riassunto(m);
      final n = await this.nota(m['nota'] as int);
      if (n == null) continue;
      for (final s in ria.sezioni) {
        if (s.titolo.toLowerCase() != titolo.toLowerCase()) continue;
        for (final riga in s.righe) {
          if (visti.add('${n.id}|$riga')) out.add(Risultato(n, riga, null));
        }
      }
    }
    return out;
  }

  Future<void> salvaChat(int? nota, String domanda, String risposta, List<int> fonti) =>
      d.insert('chat', {'nota': nota, 'domanda': domanda, 'risposta': risposta, 'fonti': jsonEncode(fonti), 'creata': DateTime.now().millisecondsSinceEpoch});
  Future<List<Map<String, Object?>>> storicoChat({int? nota}) =>
      d.query('chat', where: nota == null ? 'nota IS NULL' : 'nota=?', whereArgs: nota == null ? null : [nota], orderBy: 'id');
  Future<void> svuotaChat({int? nota}) => d.delete('chat', where: nota == null ? 'nota IS NULL' : 'nota=?', whereArgs: nota == null ? null : [nota]);
}

late Db db;
