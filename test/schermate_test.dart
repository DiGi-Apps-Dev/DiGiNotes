import 'package:diginotes/db.dart';
import 'package:diginotes/digishare.dart';
import 'package:diginotes/theme.dart';
import 'package:diginotes/ui/anteprima_screen.dart';
import 'package:diginotes/ui/chiedi_screen.dart';
import 'package:diginotes/ui/home_screen.dart';
import 'package:diginotes/ui/impostazioni_screen.dart';
import 'package:diginotes/ui/modelli_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Le schermate si disegnano sul formato di un telefono senza sforare: un overflow fa fallire la prova.
void main() {
  sqfliteFfiInit();

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('it');
    db = await Db.apri(percorso: inMemoryDatabasePath, fabbrica: databaseFactoryFfiNoIsolate);
  });

  Future<void> disegna(WidgetTester t, Widget w) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: w)));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump(const Duration(milliseconds: 100));
  }

  testWidgets('Senza server: l\'indirizzo è vuoto e lo scrive ognuno', (t) async {
    await disegna(t, const CollegaScreen());
    expect(cloud.collegato, isFalse);
    expect(find.text('Indirizzo del server'), findsOneWidget);
    final indirizzo = t.widget<TextField>(find.byType(TextField).first);
    expect(indirizzo.controller!.text, isEmpty);
  });

  testWidgets('Note: mostra l\'esempio e i filtri', (t) async {
    await disegna(t, NoteVista(nomeCartella: 'Tutte', importa: () {}));
    expect(find.text('Esempio: rinnovo polizza'), findsOneWidget);
    expect(find.text('Esempio'), findsOneWidget);
    expect(find.text('Appuntamenti'), findsOneWidget);
  });

  testWidgets('Modelli: pronti e miei', (t) async {
    await disegna(t, const ModelliVista());
    expect(find.text('Colloquio cliente'), findsOneWidget);
    expect(find.text('I MIEI'), findsOneWidget);
  });

  testWidgets('Chiedi: una domanda trova la frase e la sua nota', (t) async {
    await disegna(t, const ChiediVista());
    await t.enterText(find.byType(TextField), 'Che franchigia?');
    await t.tap(find.byIcon(Icons.send));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('franchigia si può abbassare'), findsOneWidget);
  });

  testWidgets('Impostazioni: tutte le voci in chiaro', (t) async {
    await disegna(t, const ImpostazioniVista());
    expect(find.text('Carica solo con Wi-Fi'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Glossario'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Glossario'), findsOneWidget);
  });

  Future<int> notaDaInviare(String titolo) => db.nuovaNota(titolo: titolo, tipo: 'appuntamento', stato: Stato.daInviare);

  Future<void> anteprima(WidgetTester t, int id) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: AnteprimaScreen(id: id)));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump(const Duration(milliseconds: 100));
  }

  testWidgets('Anteprima: titolo modificabile, Invia ed Elimina, e la nota non parte da sola', (t) async {
    final id = await t.runAsync(() => notaDaInviare('Nota 02.11 08:05'));
    await anteprima(t, id!);
    expect(find.text('Nota 02.11 08:05'), findsOneWidget);
    expect(find.text('Invia'), findsOneWidget);
    expect(find.text('Elimina'), findsOneWidget);
    expect(await t.runAsync(() => db.daInviare()), isEmpty);
    await t.enterText(find.byType(TextField), 'Visita al cantiere');
    await t.pumpWidget(const SizedBox());
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    final n = await t.runAsync(() => db.nota(id));
    expect(n!.titolo, 'Visita al cantiere');
    expect(n.stato, Stato.daInviare);
  });

  testWidgets('Anteprima: Elimina chiede conferma e toglie la nota dal telefono', (t) async {
    final id = await t.runAsync(() => notaDaInviare('Da buttare'));
    await anteprima(t, id!);
    await t.tap(find.text('Elimina'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('non si recupera'), findsOneWidget);
    expect(await t.runAsync(() => db.nota(id)), isNotNull);
    await t.tap(find.widgetWithText(TextButton, 'Elimina'));
    await t.pump(const Duration(milliseconds: 400));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    expect(await t.runAsync(() => db.nota(id)), isNull);
  });

  test('Invia: solo la conferma mette la nota in coda', () async {
    final id = await notaDaInviare('Confermata');
    expect((await db.daInviare()).map((n) => n.id), isNot(contains(id)));
    await cloud.confermaInvio(id);
    expect((await db.nota(id))!.stato, Stato.registrata);
    expect((await db.daInviare()).map((n) => n.id), contains(id));
    await db.aggiornaNota(id, {'stato': Stato.pronta});
  });

  testWidgets('Cestino vuoto', (t) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: const CestinoScreen()));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Il cestino è vuoto.'), findsOneWidget);
  });
}
