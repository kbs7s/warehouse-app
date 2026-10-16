import 'package:flutter/material.dart';

import '../models.dart';
import '../shell.dart';
import '../store.dart';
import '../theme.dart';
import '../ui.dart';
import 'invoice_screens.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key, required this.store});
  final WarehouseStore store;

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final q = _q.trim().toLowerCase();
    final list = s.clients
        .where((c) => q.isEmpty || c.name.toLowerCase().contains(q) || (c.phone ?? '').contains(q))
        .toList()
      ..sort((a, b) {
        final c = s.owedBy(b.id).compareTo(s.owedBy(a.id));
        return c != 0 ? c : a.name.compareTo(b.name);
      });

    return Scaffold(
      appBar: AppBar(title: const Text('Clients'), bottom: SubNav.bar(context)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => editClient(context, s, null),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('New client'),
      ),
      body: PageBody(children: [
        SearchField(onChanged: (v) => setState(() => _q = v), hint: 'Name or phone'),
        const SizedBox(height: 12),
        if (list.isEmpty)
          EmptyState(
            icon: Icons.people_outline,
            title: s.clients.isEmpty ? 'No clients yet' : 'No clients match',
            message: s.clients.isEmpty ? 'Add the people or companies you sell to. Each one gets a running balance.' : null,
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final (i, c) in list.indexed) ...[
                if (i > 0) const Divider(height: 1),
                _ClientTile(store: s, c: c),
              ],
            ]),
          ),
      ]),
    );
  }
}

class _ClientTile extends StatelessWidget {
  const _ClientTile({required this.store, required this.c});
  final WarehouseStore store;
  final Client c;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final owed = store.owedBy(c.id);
    final late = store.invoicesOf(c.id).any((i) => i.status(todayIso()) == InvoiceStatus.overdue);
    return ListTile(
      onTap: () => openClient(context, store, c.id),
      leading: CircleAvatar(
        backgroundColor: t.colorScheme.secondaryContainer,
        child: Text(c.name.isEmpty ? '?' : c.name.characters.first.toUpperCase(),
            style: TextStyle(color: t.colorScheme.onSecondaryContainer, fontWeight: FontWeight.w700)),
      ),
      title: NameText(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${store.invoicesOf(c.id).length} invoices${c.phone == null ? '' : ' · ${c.phone}'}'),
      trailing: owed <= 0
          ? Text('Settled', style: TextStyle(color: t.colorScheme.onSurfaceVariant))
          : Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(fmtMoney(owed), style: TextStyle(fontWeight: FontWeight.w700, color: late ? AppColors.bad : AppColors.warn)),
              Text(late ? 'overdue' : 'owes you', style: t.textTheme.bodySmall),
            ]),
    );
  }
}

Future<void> openClient(BuildContext context, WarehouseStore store, String id) => Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => ListenableBuilder(listenable: store, builder: (_, _) => ClientDetail(store: store, id: id))));

class ClientDetail extends StatelessWidget {
  const ClientDetail({super.key, required this.store, required this.id});
  final WarehouseStore store;
  final String id;

  @override
  Widget build(BuildContext context) {
    final c = store.client(id);
    if (c == null) return const Scaffold(body: Center(child: Text('This client was deleted.')));
    final t = Theme.of(context);
    final invs = store.invoicesOf(id).reversed.toList();
    final billed = invs.fold<num>(0, (s, i) => s + i.total);
    final paid = invs.fold<num>(0, (s, i) => s + i.paid);
    final contact = [?c.phone, ?c.email, ?c.address];

    return Scaffold(
      appBar: AppBar(
        title: NameText(c.name),
        actions: [
          IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: () => editClient(context, store, c)),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (invs.isNotEmpty) return toast(context, 'This client has invoices, so it cannot be deleted.');
              if (await confirm(context, 'Delete ${c.name}?', 'This client has no invoices.')) {
                store.deleteClient(id);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openInvoice(context, store, null, clientId: id),
        icon: const Icon(Icons.add),
        label: const Text('New invoice'),
      ),
      body: PageBody(maxWidth: 860, children: [
        if (contact.isNotEmpty || c.note != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final x in contact) Padding(padding: const EdgeInsets.only(bottom: 4), child: NameText(x)),
                if (c.note != null) Text(c.note!, style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
              ]),
            ),
          ),
        const SizedBox(height: 12),
        TileGrid(wideColumns: 3, children: [
          MetricTile(label: 'Billed in total', value: fmtMoneyShort(billed), icon: Icons.receipt_long_outlined),
          MetricTile(label: 'Paid', value: fmtMoneyShort(paid), icon: Icons.check_circle_outline, color: AppColors.good),
          MetricTile(
              label: 'Owes you',
              value: fmtMoneyShort(store.owedBy(id)),
              icon: Icons.hourglass_bottom,
              color: store.owedBy(id) > 0 ? AppColors.warn : null),
        ]),
        SectionTitle('Invoices', trailing: Text('${invs.length}')),
        if (invs.isEmpty)
          const Card(child: ListTile(title: Text('No invoices for this client yet.')))
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final (i, inv) in invs.indexed) ...[
                if (i > 0) const Divider(height: 1),
                InvoiceTile(store: store, inv: inv, showClient: false),
              ],
            ]),
          ),
      ]),
    );
  }
}

/// Searchable client list with a "new client" option; returns the chosen client id.
Future<String?> pickClient(BuildContext context, WarehouseStore store) =>
    showDialog<String>(context: context, builder: (_) => _ClientPicker(store: store));

class _ClientPicker extends StatefulWidget {
  const _ClientPicker({required this.store});
  final WarehouseStore store;

  @override
  State<_ClientPicker> createState() => _ClientPickerState();
}

class _ClientPickerState extends State<_ClientPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final list = [for (final c in widget.store.clients) if (q.isEmpty || c.name.toLowerCase().contains(q)) c]
      ..sort((a, b) => a.name.compareTo(b.name));
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(hintText: 'Find a client', prefixIcon: Icon(Icons.search)),
            ),
          ),
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_add_alt)),
            title: Text(_q.trim().isEmpty ? 'New client' : 'New client "${_q.trim()}"',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            onTap: () async {
              final id = await editClient(context, widget.store, null, name: _q.trim());
              if (id != null && context.mounted) Navigator.pop(context, id);
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(children: [
              for (final c in list)
                ListTile(
                  title: NameText(c.name),
                  subtitle: c.phone == null ? null : Text(c.phone!),
                  onTap: () => Navigator.pop(context, c.id),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Add or edit a client. Returns the client's id when saved.
Future<String?> editClient(BuildContext context, WarehouseStore store, Client? c, {String? name}) =>
    showDialog<String>(context: context, builder: (_) => _ClientForm(store: store, c: c, name: name));

class _ClientForm extends StatefulWidget {
  const _ClientForm({required this.store, this.c, this.name});
  final WarehouseStore store;
  final Client? c;
  final String? name;

  @override
  State<_ClientForm> createState() => _ClientFormState();
}

class _ClientFormState extends State<_ClientForm> {
  late final _name = TextEditingController(text: widget.c?.name ?? widget.name);
  late final _phone = TextEditingController(text: widget.c?.phone);
  late final _email = TextEditingController(text: widget.c?.email);
  late final _address = TextEditingController(text: widget.c?.address);
  late final _note = TextEditingController(text: widget.c?.note);

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.c == null ? 'New client' : 'Edit client'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListenableBuilder(
                listenable: _name,
                builder: (_, _) => TextField(
                  controller: _name,
                  autofocus: widget.c == null,
                  textDirection: dirOf(_name.text),
                  decoration: const InputDecoration(labelText: 'Name (person or company)'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
              const SizedBox(height: 12),
              TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
              const SizedBox(height: 12),
              TextField(controller: _address, decoration: const InputDecoration(labelText: 'Address')),
              const SizedBox(height: 12),
              TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note')),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (_name.text.trim().isEmpty) return toast(context, 'Enter a name.');
              String? v(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
              final client = Client(
                id: widget.c?.id ?? widget.store.newId('c'),
                name: _name.text.trim(),
                phone: v(_phone),
                email: v(_email),
                address: v(_address),
                note: v(_note),
              );
              widget.store.saveClient(client);
              Navigator.pop(context, client.id);
            },
            child: const Text('Save'),
          ),
        ],
      );
}
