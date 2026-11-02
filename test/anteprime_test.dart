import 'dart:io';

import 'package:diginotes/db.dart';
import 'package:diginotes/theme.dart';
import 'package:diginotes/ui/home_screen.dart';
import 'package:diginotes/ui/chiedi_screen.dart';
import 'package:diginotes/ui/nota_screen.dart';
import 'package:diginotes/ui/registra_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Disegna le schermate vere con i caratteri veri, per guardarle senza telefono:
/// flutter test test/anteprime_test.dart --update-goldens (PNG in test/anteprime).
/// Si salta se mancano i caratteri di Windows.
void main() {
  sqfliteFfiInit();
  final segoe = File(r'C:\Windows\Fonts\segoeui.ttf');
  final grassetto = File(r'C:\Windows\Fonts\segoeuib.ttf');

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    ReceiveSharingIntent.setMockValues(initialMedia: const [], mediaStream: const Stream.empty());
    await initializeDateFormatting('it');
    db = await Db.apri(percorso: inMemoryDatabasePath, fabbrica: databaseFactoryFfiNoIsolate);
    final c = await db.nuovaCartella('Clienti', 1);
    for (final (t, tipo, stato) in [('Sopralluogo cantiere Lugano', 'appuntamento', Stato.caricata), ('Idea per il sito', 'idea', Stato.registrata), ('Colloquio con il commercialista', 'appuntamento', Stato.caricamento)]) {
      final id = await db.nuovaNota(titolo: t, tipo: tipo, stato: stato, cartella: c);
      await db.aggiornaNota(id, {'durata_ms': 3300000});
    }
    if (!segoe.existsSync()) return;
    final f = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.sublistView(segoe.readAsBytesSync())))
      ..addFont(Future.value(ByteData.sublistView(grassetto.readAsBytesSync())));
    await f.load();
    final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? r'C:\flutter';
    final ic = File('$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
    if (ic.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(ic.readAsBytesSync())))).load();
    }
  });

  Future<void> scatta(WidgetTester t, Widget w, String nome, {Future<void> Function()? dopo}) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(RepaintBoundary(child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme().copyWith(textTheme: buildTheme().textTheme.apply(fontFamily: 'Roboto')), home: w)));
    await t.runAsync(() async {
      for (final e in find.byType(Image).evaluate()) {
        await precacheImage((e.widget as Image).image, e);
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await t.pump(const Duration(milliseconds: 200));
    if (dopo != null) {
      await dopo();
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    }
    await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile('anteprime/$nome.png'));
  }

  testWidgets('home', (t) => scatta(t, const Principale2(), 'home'), skip: !autoUpdateGoldenFiles || !segoe.existsSync());
  testWidgets('menu', (t) => scatta(t, const Principale2(), 'menu', dopo: () async {
        await t.tap(find.byIcon(Icons.menu));
      }), skip: !autoUpdateGoldenFiles || !segoe.existsSync());
  testWidgets('riassunto', (t) => scatta(t, const NotaScreen(id: 1), 'riassunto'), skip: !autoUpdateGoldenFiles || !segoe.existsSync());
  testWidgets('testo', (t) => scatta(t, const NotaScreen(id: 1, scheda: 1), 'testo'), skip: !autoUpdateGoldenFiles || !segoe.existsSync());
  testWidgets('mappa', (t) => scatta(t, const NotaScreen(id: 1, scheda: 2), 'mappa'), skip: !autoUpdateGoldenFiles || !segoe.existsSync());
  testWidgets('registra', (t) => scatta(t, const RegistraScreen(), 'registra'), skip: !autoUpdateGoldenFiles || !segoe.existsSync());
  testWidgets('chiedi', (t) => scatta(t, const Scaffold(body: ChiediVista()), 'chiedi'), skip: !autoUpdateGoldenFiles || !segoe.existsSync());
  testWidgets('impostazioni', (t) => scatta(t, const Principale2(), 'impostazioni', dopo: () async {
        await t.tap(find.text('Impost.'));
      }), skip: !autoUpdateGoldenFiles || !segoe.existsSync());
}
