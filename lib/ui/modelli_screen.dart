import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../db.dart';
import '../registratore.dart';
import '../theme.dart';

/// Sceglie un modello e ne restituisce il nome.
Future<String?> scegliModello(BuildContext context) async {
  final mm = await db.modelli();
  if (!context.mounted) return null;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * .75),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(14), children: [
          const Etichetta('Scegli il modello'),
          const SizedBox(height: 8),
          for (final m in mm)
            ListTile(title: Text(m.nome, style: const TextStyle(fontWeight: FontWeight.w600)), subtitle: Text(m.descrizione), onTap: () => Navigator.pop(c, m.nome)),
        ]),
      ),
    ),
  );
}

class ModelliVista extends StatefulWidget {
  const ModelliVista({super.key});
  @override
  State<ModelliVista> createState() => _ModelliVistaState();
}

class _ModelliVistaState extends State<ModelliVista> {
  List<Modello> _m = [];
  String _q = '';

  @override
  void initState() {
    super.initState();
    _carica();
  }

  Future<void> _carica() async {
    final m = await db.modelli();
    if (mounted) setState(() => _m = m);
  }

  Future<void> _apri({Modello? m, bool daFoto = false}) async {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ModelloEdit(modello: m, daFoto: daFoto)));
    _carica();
  }

  Widget _griglia(List<Modello> l) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: l.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8, mainAxisExtent: 86),
        itemBuilder: (_, i) {
          final m = l[i];
          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _apri(m: m),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: kG1, borderRadius: BorderRadius.circular(8), border: Border.all(color: kFilo)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.nome, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(m.descrizione, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)),
              ]),
            ),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final filtrati = _m.where((m) => _q.isEmpty || m.nome.toLowerCase().contains(_q) || m.descrizione.toLowerCase().contains(_q)).toList();
    final pronti = filtrati.where((m) => !m.proprio).toList();
    final miei = filtrati.where((m) => m.proprio).toList();
    return ListView(padding: const EdgeInsets.all(12), children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Etichetta('Modelli'),
        Chip2('+ Nuovo', acceso: true, onTap: () => _apri()),
      ]),
      const SizedBox(height: 10),
      TextField(decoration: const InputDecoration(hintText: 'Cerca un modello', prefixIcon: Icon(Icons.search), isDense: true), onChanged: (v) => setState(() => _q = v.toLowerCase())),
      const SizedBox(height: 10),
      _griglia(pronti),
      const SizedBox(height: 14),
      const Etichetta('I miei'),
      const SizedBox(height: 8),
      if (miei.isEmpty) const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Ancora nessuno. Scrivine uno o parti dalla foto di un modulo.', style: TextStyle(fontSize: 15))),
      _griglia(miei),
      const SizedBox(height: 8),
      Secondario(testo: 'Crea dalla foto di un modulo', icona: Icons.photo_camera_outlined, onTap: () => _apri(daFoto: true)),
    ]);
  }
}

class ModelloEdit extends StatefulWidget {
  const ModelloEdit({super.key, this.modello, this.daFoto = false});
  final Modello? modello;
  final bool daFoto;
  @override
  State<ModelloEdit> createState() => _ModelloEditState();
}

class _ModelloEditState extends State<ModelloEdit> {
  late final _nome = TextEditingController(text: widget.modello?.nome);
  late final _descr = TextEditingController(text: widget.modello?.descrizione);
  late final _istr = TextEditingController(text: widget.modello?.istruzioni);
  String? _foto;

  bool get _sola => widget.modello != null && !widget.modello!.proprio;

  @override
  void initState() {
    super.initState();
    _foto = widget.modello?.foto;
    if (widget.daFoto) WidgetsBinding.instance.addPostFrameCallback((_) => _scatta());
  }

  Future<void> _scatta() async {
    final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 2200);
    if (x == null) return;
    final dir = await Registratore.cartellaAudio();
    final dest = p.join(dir.path, 'modello-${DateTime.now().millisecondsSinceEpoch}.jpg');
    await File(x.path).copy(dest);
    if (!mounted) return;
    setState(() {
      _foto = dest;
      if (_istr.text.isEmpty) _istr.text = 'Riempi i campi del modulo in foto con i dati della registrazione.';
    });
  }

  Future<void> _salva() async {
    if (_nome.text.trim().isEmpty) {
      avviso(context, 'Scrivi il nome del modello');
      return;
    }
    await db.salvaModello(
      id: widget.modello?.proprio == true ? widget.modello!.id : null,
      nome: _nome.text.trim(),
      descrizione: _descr.text.trim().isEmpty ? 'Modello personale' : _descr.text.trim(),
      istruzioni: _istr.text.trim(),
      foto: _foto,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: Barra(titolo: widget.modello == null ? 'Nuovo modello' : widget.modello!.nome, azioni: [
          if (widget.modello?.proprio == true)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Elimina',
              onPressed: () async {
                final ok = await conferma(context, 'Elimina modello', 'Il modello «${widget.modello!.nome}» non si recupera. Le note già fatte restano.', si: 'Elimina');
                if (!ok) return;
                await db.eliminaModello(widget.modello!.id);
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ]),
        body: ListView(padding: const EdgeInsets.all(14), children: [
          if (_sola) ...[
            const Text('È un modello pronto. Se lo modifichi, viene salvato come copia tua tra «I miei».', style: TextStyle(fontSize: 15)),
            const SizedBox(height: 12),
          ],
          TextField(controller: _nome, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Nome')),
          const SizedBox(height: 10),
          TextField(controller: _descr, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'A cosa serve')),
          const SizedBox(height: 10),
          TextField(controller: _istr, minLines: 6, maxLines: 14, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Come vuoi il riassunto', alignLabelWithHint: true)),
          const SizedBox(height: 10),
          if (_foto != null && File(_foto!).existsSync()) ...[
            ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(_foto!), height: 200, fit: BoxFit.cover)),
            const SizedBox(height: 8),
          ],
          Secondario(testo: _foto == null ? 'Aggiungi la foto di un modulo' : 'Cambia la foto', icona: Icons.photo_camera_outlined, onTap: _scatta),
          const SizedBox(height: 14),
          Principale(testo: 'Salva', onTap: _salva),
        ]),
      );
}
