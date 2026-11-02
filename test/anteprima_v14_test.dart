import 'dart:async';
import 'dart:io';

import 'package:diginotes/db.dart';
import 'package:diginotes/theme.dart';
import 'package:diginotes/ui/anteprima_screen.dart';
import 'package:diginotes/ui/home_screen.dart';
import 'package:diginotes/ui/nota_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Le schermate vere dopo Fine, con un lettore finto che dice solo «16 secondi»: sul PC il lettore vero non c'è.
/// flutter test test/anteprima_v14_test.dart --update-goldens (PNG in test/anteprime).
class _Piattaforma extends JustAudioPlatform with MockPlatformInterfaceMixin {
  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async => _Lettore(request.id);
  @override
  Future<DisposePlayerResponse> disposePlayer(DisposePlayerRequest request) async => DisposePlayerResponse();
  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(DisposeAllPlayersRequest request) async => DisposeAllPlayersResponse();
}

class _Lettore extends AudioPlayerPlatform {
  _Lettore(super.id);
  final _eventi = StreamController<PlaybackEventMessage>.broadcast();
  static const _durata = Duration(seconds: 16);
  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _eventi.stream;
  @override
  Stream<PlayerDataMessage> get playerDataMessageStream => const Stream.empty();
  @override
  Future<LoadResponse> load(LoadRequest request) async {
    _eventi.add(PlaybackEventMessage(processingState: ProcessingStateMessage.ready, updateTime: DateTime.now(), updatePosition: Duration.zero, bufferedPosition: _durata, duration: _durata, icyMetadata: null, currentIndex: 0, androidAudioSessionId: null));
    return LoadResponse(duration: _durata);
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async => PlayResponse();
  @override
  Future<PauseResponse> pause(PauseRequest request) async => PauseResponse();
  @override
  Future<SeekResponse> seek(SeekRequest request) async => SeekResponse();
  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async => SetVolumeResponse();
  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async => SetSpeedResponse();
  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async => SetPitchResponse();
  @override
  Future<SetSkipSilenceResponse> setSkipSilence(SetSkipSilenceRequest request) async => SetSkipSilenceResponse();
  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async => SetLoopModeResponse();
  @override
  Future<SetShuffleModeResponse> setShuffleMode(SetShuffleModeRequest request) async => SetShuffleModeResponse();
  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(SetAndroidAudioAttributesRequest request) async => SetAndroidAudioAttributesResponse();
  @override
  Future<SetPreferredPeakBitRateResponse> setPreferredPeakBitRate(SetPreferredPeakBitRateRequest request) async => SetPreferredPeakBitRateResponse();
  @override
  Future<AudioEffectSetEnabledResponse> audioEffectSetEnabled(AudioEffectSetEnabledRequest request) async => AudioEffectSetEnabledResponse();
  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    await _eventi.close();
    return DisposeResponse();
  }
}

void main() {
  sqfliteFfiInit();
  final segoe = File(r'C:\Windows\Fonts\segoeui.ttf');
  final grassetto = File(r'C:\Windows\Fonts\segoeuib.ttf');
  late int nota;
  late Directory cartella;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    ReceiveSharingIntent.setMockValues(initialMedia: const [], mediaStream: const Stream.empty());
    JustAudioPlatform.instance = _Piattaforma();
    await initializeDateFormatting('it');
    db = await Db.apri(percorso: inMemoryDatabasePath, fabbrica: databaseFactoryFfiNoIsolate);
    cartella = Directory.systemTemp.createTempSync('anteprima-v14-');
    final audio = File('${cartella.path}/nota.ogg')..writeAsBytesSync([0]);
    nota = await db.nuovaNota(titolo: 'Nota 02.11 09:38', tipo: 'appuntamento', stato: Stato.daInviare);
    await db.aggiungiParte(nota, audio.path);
    await db.aggiornaNota(nota, {'durata_ms': 16000});
    if (!segoe.existsSync()) return;
    await (FontLoader('Roboto')
          ..addFont(Future.value(ByteData.sublistView(segoe.readAsBytesSync())))
          ..addFont(Future.value(ByteData.sublistView(grassetto.readAsBytesSync()))))
        .load();
    // Il testo senza carattere indicato usa quello delle prove, a barrette: qui diventa quello vero.
    await (FontLoader('FlutterTest')
          ..addFont(Future.value(ByteData.sublistView(segoe.readAsBytesSync())))
          ..addFont(Future.value(ByteData.sublistView(grassetto.readAsBytesSync()))))
        .load();
    final ic = File('${Platform.environment['FLUTTER_ROOT'] ?? r'C:\flutter'}/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
    if (ic.existsSync()) await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(ic.readAsBytesSync())))).load();
  });

  Future<void> scatta(WidgetTester t, Widget w, String nome, {Future<void> Function()? dopo}) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(RepaintBoundary(child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme().copyWith(textTheme: buildTheme().textTheme.apply(fontFamily: 'Roboto')), home: w)));
    for (var i = 0; i < 6; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await t.pump(const Duration(milliseconds: 200));
    }
    if (dopo != null) {
      await dopo();
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await t.pump(const Duration(milliseconds: 600));
      await t.pump(const Duration(milliseconds: 600));
    }
    await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile('anteprime/$nome.png'));
    await t.pumpWidget(const SizedBox());
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump(const Duration(seconds: 1));
  }

  final salta = !autoUpdateGoldenFiles || !segoe.existsSync();
  testWidgets('anteprima dopo Fine', (t) => scatta(t, AnteprimaScreen(id: nota), 'v14-anteprima'), skip: salta);
  testWidgets('elenco con una nota da inviare', (t) => scatta(t, const Principale2(), 'v14-elenco'), skip: salta);
  testWidgets('tre puntini con Invia', (t) => scatta(t, NotaScreen(id: nota), 'v14-menu', dopo: () async {
        await t.tap(find.byIcon(Icons.more_vert));
      }), skip: salta);
}
