import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'db.dart';
import 'digishare.dart';
import 'registratore.dart';
import 'theme.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('it');
  FlutterForegroundTask.initCommunicationPort();
  Registratore.prepara();
  db = await Db.apri();
  await db.recuperaInterrotte();
  runApp(const DiGiNotes());
  unawaited(cloud.avvia());
}

class DiGiNotes extends StatelessWidget {
  const DiGiNotes({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'DiGiNotes',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        locale: const Locale('it'),
        supportedLocales: const [Locale('it')],
        localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
        home: const Blocco(),
      );
}

/// Se è attivo lo sblocco, chiede impronta o volto all'apertura e al ritorno dopo un minuto.
class Blocco extends StatefulWidget {
  const Blocco({super.key});
  @override
  State<Blocco> createState() => _BloccoState();
}

class _BloccoState extends State<Blocco> with WidgetsBindingObserver {
  bool _aperto = false;
  DateTime? _via;
  bool _chiedo = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _verifica();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused) _via = DateTime.now();
    if (s == AppLifecycleState.resumed && _via != null && DateTime.now().difference(_via!).inSeconds > 60 && !registratore.attivo) {
      _verifica();
    }
  }

  Future<void> _verifica() async {
    if (_chiedo) return;
    final p = await SharedPreferences.getInstance();
    if (!(p.getBool('sblocco') ?? false)) {
      if (mounted) setState(() => _aperto = true);
      if (!(p.getBool('benvenuto') ?? false)) {
        await p.setBool('benvenuto', true);
        WidgetsBinding.instance.addPostFrameCallback((_) => _benvenuto());
      }
      return;
    }
    _chiedo = true;
    if (mounted) setState(() => _aperto = false);
    var ok = false;
    try {
      ok = await LocalAuthentication().authenticate(localizedReason: 'Sblocca DiGiNotes');
    } catch (_) {
      // Sblocco non disponibile: resta la schermata col pulsante Riprova.
    }
    _chiedo = false;
    if (mounted) setState(() => _aperto = ok);
  }

  void _benvenuto() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('BENVENUTO IN DIGINOTES'),
        content: const Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('1. Premi il pulsante rotondo e registra. Puoi spegnere lo schermo.'),
          SizedBox(height: 8),
          Text('2. Segna i momenti importanti, scatta foto, scrivi note mentre registri.'),
          SizedBox(height: 8),
          Text('3. Trovi testo, riassunto e mappa nella nota. Per provarli c\'è una nota di esempio.'),
          SizedBox(height: 8),
          Text('Avvisa sempre i presenti che stai registrando: la legge chiede il loro assenso.', style: TextStyle(fontWeight: FontWeight.w700)),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Ho capito', style: TextStyle(color: kInk, fontWeight: FontWeight.w700)))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _aperto
      ? const Principale2()
      : Scaffold(
          appBar: const Barra(marchio: true, indietro: false),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Principale(testo: 'Sblocca', icona: Icons.fingerprint, onTap: _verifica),
            ),
          ),
        );
}
