import 'package:flutter/material.dart';

/// Grafica della famiglia DiGi Apps (DiGiShare «Videoteca»): grafite, testo mai grigio,
/// gerarchia fatta con grandezza e peso, etichette in maiuscolo da 20.
const kG0 = Color(0xFF141317);
const kG1 = Color(0xFF1C1B20);
const kG2 = Color(0xFF25242B);
const kG3 = Color(0xFF302F37);
const kInk = Color(0xFFF6F4F8);
const kContorno = Color(0xFF14001A);
const kFilo = Color(0x14FFFFFF);
const kFilo2 = Color(0x24FFFFFF);
const kRosa = Color(0xFFE0306A);
const kViola = Color(0xFF8A2BA8);
const kPuntoRosso = Color(0xFFFF2D2D);
const kPuntoGiallo = Color(0xFFFAEB1E);
const kVerde = Color(0xFF47C97E);

const kBarra = LinearGradient(colors: [Color(0xFFFF284B), Color(0xFF7624C4)]);
const kMarchio = LinearGradient(colors: [kRosa, Color(0xFFB52E8C), kViola]);
const kTenue = LinearGradient(colors: [Color(0x38E0306A), Color(0x388A2BA8)]);

const kEtichetta = TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kInk, height: 1.2);

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: kRosa,
    onPrimary: Colors.white,
    secondary: kViola,
    onSecondary: Colors.white,
    surface: kG0,
    onSurface: kInk,
    onSurfaceVariant: kInk,
    outline: kFilo2,
    outlineVariant: kFilo,
    surfaceContainerLowest: kG0,
    surfaceContainerLow: kG1,
    surfaceContainer: kG1,
    surfaceContainerHigh: kG2,
    surfaceContainerHighest: kG2,
    surfaceTint: Colors.transparent,
    error: kPuntoRosso,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, hintColor: kInk);
  final text = base.textTheme.apply(bodyColor: kInk, displayColor: kInk);
  final forma = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
  return base.copyWith(
    scaffoldBackgroundColor: kG0,
    textTheme: text,
    primaryTextTheme: text,
    iconTheme: const IconThemeData(color: kInk),
    dividerColor: kFilo,
    dialogTheme: DialogThemeData(backgroundColor: kG1, shape: forma, titleTextStyle: kEtichetta, contentTextStyle: const TextStyle(fontSize: 15, color: kInk)),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: kG1,
      modalBackgroundColor: kG1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
    ),
    snackBarTheme: SnackBarThemeData(backgroundColor: kG3, contentTextStyle: const TextStyle(color: kInk, fontSize: 15), shape: forma, behavior: SnackBarBehavior.floating),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kG1,
      labelStyle: const TextStyle(color: kInk),
      hintStyle: const TextStyle(color: kInk),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: kFilo2)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: kFilo2)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0x80FFFFFF))),
    ),
    switchTheme: SwitchThemeData(
      // Regola della famiglia DiGi: acceso = colore del marchio pieno, si deve vedere a colpo d'occhio.
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? kRosa : kG3),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
  );
}

/// Barra in alto a gradiente con bordo scuro, come DiGiShare.
class Barra extends StatelessWidget implements PreferredSizeWidget {
  const Barra({super.key, this.titolo, this.azioni = const [], this.indietro = true, this.marchio = false, this.menu});
  final String? titolo;
  final List<Widget> azioni;
  final bool indietro;
  final bool marchio;
  final VoidCallback? menu;

  @override
  Size get preferredSize => const Size.fromHeight(63);

  @override
  Widget build(BuildContext context) {
    final alto = MediaQuery.paddingOf(context).top;
    return Container(
      padding: EdgeInsets.only(top: alto, left: 6, right: 6),
      decoration: const BoxDecoration(gradient: kBarra, border: Border(bottom: BorderSide(color: kContorno, width: 3))),
      child: SizedBox(
        height: 60,
        child: IconTheme(
          data: const IconThemeData(color: Colors.white),
          child: Row(children: [
            if (menu != null)
              IconButton(icon: const Icon(Icons.menu), tooltip: 'Menu', onPressed: menu)
            else if (indietro)
              IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Indietro', onPressed: () => Navigator.maybePop(context)),
            if (marchio) ...[
              const SizedBox(width: 2),
              ClipRRect(borderRadius: BorderRadius.circular(9), child: Image.asset('assets/logo.png', width: 36, height: 36)),
              const SizedBox(width: 9),
              const Expanded(child: Align(alignment: Alignment.centerLeft, child: Marchio())),
            ] else
              Expanded(
                child: Text(titolo ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ...azioni,
          ]),
        ),
      ),
    );
  }
}

/// Scritta DiGiNotes con i puntini rosso e giallo sulle due i.
class Marchio extends StatelessWidget {
  const Marchio({super.key});
  static const _s = TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w700, letterSpacing: -.2, height: 1.2);

  Widget _i(Color colore) => Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
        const Text('ı', style: _s),
        Positioned(
          top: 1,
          child: Container(width: 7.5, height: 7.5, decoration: BoxDecoration(color: colore, shape: BoxShape.circle, border: Border.all(color: kContorno, width: 1.5))),
        ),
      ]);

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        const Text('D', style: _s),
        _i(kPuntoRosso),
        const Text('G', style: _s),
        _i(kPuntoGiallo),
        const Text('Notes', style: _s),
      ]);
}

class Etichetta extends StatelessWidget {
  const Etichetta(this.testo, {super.key});
  final String testo;
  @override
  Widget build(BuildContext context) => Text(testo.toUpperCase(), style: kEtichetta);
}

/// Pulsante principale col gradiente del marchio.
class Principale extends StatelessWidget {
  const Principale({super.key, required this.testo, this.icona, required this.onTap, this.alto = 50});
  final String testo;
  final IconData? icona;
  final VoidCallback? onTap;
  final double alto;
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onTap == null ? .5 : 1,
        child: Material(
          color: Colors.transparent,
          child: Ink(
            height: alto,
            decoration: BoxDecoration(gradient: kMarchio, borderRadius: BorderRadius.circular(8)),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (icona != null) ...[Icon(icona, color: Colors.white, size: 21), const SizedBox(width: 8)],
                Flexible(child: Text(testo, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600))),
              ]),
            ),
          ),
        ),
      );
}

class Secondario extends StatelessWidget {
  const Secondario({super.key, required this.testo, this.icona, required this.onTap, this.alto = 44});
  final String testo;
  final IconData? icona;
  final VoidCallback? onTap;
  final double alto;
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onTap == null ? .5 : 1,
        child: Material(
          color: kG2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: kFilo2)),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: SizedBox(
              height: alto,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (icona != null) ...[Icon(icona, size: 20), const SizedBox(width: 7)],
                  Flexible(child: Text(testo, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500))),
                ]),
              ),
            ),
          ),
        ),
      );
}

class Chip2 extends StatelessWidget {
  const Chip2(this.testo, {super.key, this.acceso = false, this.onTap, this.icona});
  final String testo;
  final bool acceso;
  final VoidCallback? onTap;
  final IconData? icona;
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 34),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            gradient: acceso ? kMarchio : null,
            color: acceso ? null : kG2,
            borderRadius: BorderRadius.circular(6),
            border: acceso ? null : Border.all(color: kFilo2),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icona != null) ...[Icon(icona, size: 16), const SizedBox(width: 5)],
            Flexible(child: Text(testo, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: acceso ? FontWeight.w600 : FontWeight.w500, color: acceso ? Colors.white : kInk))),
          ]),
        ),
      );
}

/// Riquadro che raccoglie righe: fondo g1, angoli 8, fili sottili.
class Elenco extends StatelessWidget {
  const Elenco({super.key, required this.figli});
  final List<Widget> figli;
  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: kG1, borderRadius: BorderRadius.circular(8), border: Border.all(color: kFilo)),
        child: Column(children: [
          for (var i = 0; i < figli.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: kFilo),
            figli[i],
          ],
        ]),
      );
}

void avviso(BuildContext context, String testo) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(testo)));
}

Future<bool> conferma(BuildContext context, String titolo, String testo, {String si = 'Conferma'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titolo),
      content: Text(testo),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annulla', style: TextStyle(color: kInk))),
        TextButton(onPressed: () => Navigator.pop(c, true), child: Text(si, style: const TextStyle(color: kInk, fontWeight: FontWeight.w700))),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> chiediTesto(BuildContext context, String titolo, {String iniziale = '', String? etichetta, int righe = 1, String si = 'Salva'}) async {
  final c = TextEditingController(text: iniziale);
  final r = await showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(titolo),
      content: TextField(controller: c, autofocus: true, maxLines: righe, minLines: 1, decoration: InputDecoration(labelText: etichetta), textCapitalization: TextCapitalization.sentences),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annulla', style: TextStyle(color: kInk))),
        TextButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: Text(si, style: const TextStyle(color: kInk, fontWeight: FontWeight.w700))),
      ],
    ),
  );
  return (r == null || r.isEmpty) ? null : r;
}
