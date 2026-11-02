import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'db.dart';

/// Registra col microfono del telefono: Opus 24 kbit/s mono, lo stesso formato che Groq accetta e che DiGiShare
/// già usa per l'audio dei sottotitoli. Il servizio in primo piano tiene viva la registrazione a schermo spento;
/// Android lo permette solo se parte con l'app aperta.
class Registratore extends ChangeNotifier {
  late final AudioRecorder _rec = AudioRecorder();
  final Stopwatch _orologio = Stopwatch();
  Timer? _battito;
  StreamSubscription<Amplitude>? _amp;
  StreamSubscription<RecordState>? _stato;
  static const _sogliaMuto = -120.0;
  int? _mutoDa;

  /// Il microfono non passa più audio: la schermata lo dice.
  bool muto = false;

  int? notaId;
  String tipo = 'appuntamento';
  bool inPausa = false;
  final List<double> livelli = [];
  final List<Segno> segni = [];

  bool get attivo => notaId != null;
  Duration get tempo => _orologio.elapsed;
  int get ms => _orologio.elapsedMilliseconds;

  static void prepara() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'registrazione',
        channelName: 'Registrazione in corso',
        channelDescription: 'Avviso fisso mentre DiGiNotes registra',
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(eventAction: ForegroundTaskEventAction.nothing()),
    );
  }

  static String titoloPredefinito(String tipo, DateTime quando) {
    return 'Nota ${DateFormat('dd.MM HH:mm').format(quando)}';
  }

  /// Un titolo che l'utente non ha toccato: quando la nota è pronta lo sostituisce quello dell'IA. Vale anche per le note nate col formato di prima.
  static bool titoloAutomatico(String titolo, String tipo, DateTime quando) {
    final q = DateFormat('d MMM, HH:mm', 'it').format(quando);
    return titolo == titoloPredefinito(tipo, quando) || titolo == 'Appuntamento del $q' || titolo == 'Idea del $q';
  }

  static Future<Directory> cartellaAudio() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(base.path, 'audio'));
    await d.create(recursive: true);
    return d;
  }

  /// Filtro rumore acceso: la sorgente delle telefonate, che Android pulisce di più. Spento: microfono nudo.
  static RecordConfig configDi(String filtro) {
    const base = (encoder: AudioEncoder.opus, bitRate: 24000, sampleRate: 16000, numChannels: 1);
    // Un'altra app che usa l'audio non ferma la registrazione: di serie il registratore si metterebbe in pausa da solo.
    return switch (filtro) {
      'spento' => RecordConfig(encoder: base.encoder, bitRate: base.bitRate, sampleRate: base.sampleRate, numChannels: base.numChannels, audioInterruption: AudioInterruptionMode.none),
      _ => RecordConfig(encoder: base.encoder, bitRate: base.bitRate, sampleRate: base.sampleRate, numChannels: base.numChannels, audioInterruption: AudioInterruptionMode.none, noiseSuppress: true, echoCancel: true, autoGain: true, androidConfig: const AndroidRecordConfig(audioSource: AndroidAudioSource.voiceCommunication)),
    };
  }

  Future<bool> haPermesso() => _rec.hasPermission();

  Future<int> inizia({required String tipo, int? cartella, String? modello}) async {
    if (attivo) return notaId!;
    this.tipo = tipo;
    final adesso = DateTime.now();
    final dir = await cartellaAudio();
    final file = p.join(dir.path, 'nota-${adesso.millisecondsSinceEpoch}.ogg');
    // La nota nasce prima dell'audio: se il telefono si spegne, al riavvio la registrazione si ritrova.
    final pref = await SharedPreferences.getInstance();
    final id = await db.nuovaNota(titolo: titoloPredefinito(tipo, adesso), tipo: tipo, cartella: cartella, modello: modello);
    await db.aggiungiParte(id, file);
    try {
      final servizio = await FlutterForegroundTask.startService(
        serviceId: 701,
        serviceTypes: const [ForegroundServiceTypes.microphone],
        notificationTitle: 'DiGiNotes sta registrando',
        notificationText: 'Tocca per tornare alla registrazione',
      );
      // Senza servizio la registrazione si fermerebbe a schermo spento: meglio dirlo subito.
      if (servizio is ServiceRequestFailure) throw servizio.error;
      await _rec.start(configDi(pref.getString('filtro_rumore') ?? 'forte'), path: file);
    } catch (_) {
      await FlutterForegroundTask.stopService();
      await db.eliminaDefinitivamente(id);
      rethrow;
    }
    notaId = id;
    inPausa = false;
    livelli.clear();
    segni.clear();
    _orologio
      ..reset()
      ..start();
    muto = false;
    _mutoDa = null;
    _stato = _rec.onStateChanged().listen((s) {
      // Android ci ha fermati senza che l'utente premesse Pausa: l'orologio si ferma con l'audio e lo si dice.
      if (s == RecordState.pause && !inPausa && attivo) {
        _orologio.stop();
        inPausa = true;
        _avvisaMuto();
      }
    });
    _amp = _rec.onAmplitudeChanged(const Duration(milliseconds: 120)).listen((a) {
      _controllaMicrofono(a.current);
      // Da dBFS a 0..1, con il silenzio a -50.
      livelli.add(((a.current + 50) / 50).clamp(0.03, 1.0));
      if (livelli.length > 200) livelli.removeRange(0, livelli.length - 200);
      notifyListeners();
    });
    var conta = 0;
    _battito = Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners();
      if (++conta % 5 == 0) db.aggiornaNota(id, {'durata_ms': ms});
    });
    notifyListeners();
    return id;
  }

  /// Silenzio digitale per 5 secondi: Android non passa più il microfono, per esempio durante una chiamata.
  /// Una stanza silenziosa non arriva mai così in basso. Avvisa subito e segna il punto nella nota.
  void _controllaMicrofono(double db) {
    if (inPausa) return;
    if (db > _sogliaMuto) {
      _mutoDa = null;
      if (muto) {
        muto = false;
        segna('segna', testo: 'Microfono tornato');
        FlutterForegroundTask.updateService(notificationText: 'Tocca per tornare alla registrazione');
      }
      return;
    }
    _mutoDa ??= ms;
    if (!muto && ms - _mutoDa! >= 5000) _avvisaMuto();
  }

  void _avvisaMuto() {
    muto = true;
    HapticFeedback.vibrate();
    segna('segna', testo: 'Microfono muto: qui manca l\'audio');
    FlutterForegroundTask.updateService(notificationTitle: 'DiGiNotes non sente più', notificationText: 'Il microfono è muto: manca l\'audio');
    notifyListeners();
  }

  Future<void> pausa() async {
    if (!attivo || inPausa) return;
    await _rec.pause();
    _orologio.stop();
    inPausa = true;
    notifyListeners();
  }

  Future<void> riprendi() async {
    if (!attivo || !inPausa) return;
    await _rec.resume();
    _orologio.start();
    inPausa = false;
    muto = false;
    _mutoDa = null;
    notifyListeners();
  }

  Future<void> segna(String tipo, {String? testo, String? percorso}) async {
    final id = notaId;
    if (id == null) return;
    final s = await db.aggiungiSegno(id, ms, tipo, testo: testo, percorso: percorso);
    segni.add(Segno({'id': s, 'nota': id, 'ms': ms, 'tipo': tipo, 'testo': testo, 'percorso': percorso}));
    notifyListeners();
  }

  /// Chiude e restituisce la nota. Se non c'è audio la nota non resta vuota nell'elenco.
  Future<int?> ferma() async {
    final id = notaId;
    if (id == null) return null;
    final fine = ms;
    _battito?.cancel();
    await _amp?.cancel();
    await _stato?.cancel();
    muto = false;
    _orologio.stop();
    String? file;
    try {
      file = await _rec.stop();
    } finally {
      await FlutterForegroundTask.stopService();
    }
    notaId = null;
    inPausa = false;
    final esiste = file != null && await File(file).exists() && await File(file).length() > 0;
    if (!esiste) {
      await db.eliminaDefinitivamente(id);
      notifyListeners();
      return null;
    }
    await db.aggiornaNota(id, {'durata_ms': fine, 'stato': Stato.daInviare});
    notifyListeners();
    return id;
  }

  @override
  void dispose() {
    _battito?.cancel();
    _amp?.cancel();
    _stato?.cancel();
    _rec.dispose();
    super.dispose();
  }
}

final registratore = Registratore();

String durata(int ms, {bool lunga = false}) {
  final t = Duration(milliseconds: ms);
  final h = t.inHours, m = t.inMinutes % 60, s = t.inSeconds % 60;
  String due(int x) => x.toString().padLeft(2, '0');
  if (lunga) return '${due(h)}:${due(m)}:${due(s)}';
  return h > 0 ? '$h:${due(m)}:${due(s)}' : '${due(m)}:${due(s)}';
}

String durataBreve(int ms) {
  final t = Duration(milliseconds: ms);
  if (t.inHours > 0) return '${t.inHours} h ${t.inMinutes % 60} min';
  if (t.inMinutes > 0) return '${t.inMinutes} min';
  return '${t.inSeconds} s';
}
