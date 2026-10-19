import 'package:flutter/material.dart';

import '../cloud.dart';
import '../l10n.dart';
import '../store.dart';
import '../sync.dart';
import '../theme.dart';
import '../ui.dart';
import 'welcome_screen.dart' show LanguageChips;

String _err(Object e) => e is CloudError ? _arError(e) : '$e';

String _arError(CloudError e) {
  if (!isAr) return e.message;
  return switch (e.code) {
    'EMAIL_NOT_FOUND' || 'INVALID_PASSWORD' || 'INVALID_LOGIN_CREDENTIALS' => 'البريد أو كلمة المرور غير صحيحة.',
    'EMAIL_EXISTS' => 'هذا البريد لديه حساب بالفعل.',
    'INVALID_EMAIL' => 'البريد الإلكتروني غير صحيح.',
    'PERMISSION_DENIED' => 'هذا الحساب ليس ضمن الفريق. اطلب من المالك إضافته.',
    'OFFLINE' => 'لا يوجد اتصال بالإنترنت.',
    'TOO_MANY_ATTEMPTS_TRY_LATER' => 'محاولات كثيرة. انتظر بضع دقائق.',
    _ when e.code.startsWith('WEAK_PASSWORD') => 'كلمة المرور يجب أن تكون 6 أحرف على الأقل.',
    _ => e.message,
  };
}

/// One line saying whether this device is in step with the shared copy.
String syncLine(CloudSync c) => switch (c.state) {
      SyncState.off => tx('Not signed in', 'غير مسجّل الدخول'),
      SyncState.working => tx('Syncing…', 'جارٍ المزامنة…'),
      SyncState.synced => c.lastSync == null
          ? tx('Up to date', 'محدّث')
          : tx('Up to date · ${fmtTime(c.lastSync!)}', 'محدّث · ${fmtTime(c.lastSync!)}'),
      SyncState.offline => tx('Offline. Changes are kept and sent when the internet is back.',
          'بدون إنترنت. التغييرات محفوظة وستُرسل عند عودة الاتصال.'),
      SyncState.error => c.error ?? tx('Could not sync', 'تعذّرت المزامنة'),
    };

String fmtTime(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

Color syncColor(SyncState s) => switch (s) {
      SyncState.synced => AppColors.good,
      SyncState.working => AppColors.info,
      SyncState.offline => AppColors.warn,
      SyncState.error => AppColors.bad,
      SyncState.off => Colors.grey,
    };

IconData syncIcon(SyncState s) => switch (s) {
      SyncState.synced => Icons.cloud_done_outlined,
      SyncState.working => Icons.cloud_sync_outlined,
      SyncState.offline => Icons.cloud_off_outlined,
      SyncState.error => Icons.error_outline,
      SyncState.off => Icons.cloud_outlined,
    };

/// Sign in to the shared store, or set it up the first time.
class CloudSignInScreen extends StatefulWidget {
  const CloudSignInScreen({super.key, required this.store, this.setup = false});
  final WarehouseStore store;
  final bool setup;

  @override
  State<CloudSignInScreen> createState() => _CloudSignInScreenState();
}

class _CloudSignInScreenState extends State<CloudSignInScreen> {
  late bool _setup = widget.setup;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  late final _project = TextEditingController(text: widget.store.cloud?.config.projectId);
  late final _key = TextEditingController(text: widget.store.cloud?.config.apiKey);
  bool _busy = false;
  bool _hide = true;
  String? _error;

  bool get _builtIn => CloudConfig.builtIn.isSet;
  CloudConfig get _config =>
      _builtIn ? CloudConfig.builtIn : CloudConfig(projectId: _project.text.trim(), apiKey: _key.text.trim());

  Future<void> _go() async {
    final sync = widget.store.cloud!;
    if (!_config.isSet) return setState(() => _error = tx('Enter the Project ID and Web API key.', 'أدخل معرّف المشروع ومفتاح الويب.'));
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      return setState(() => _error = tx('Enter your email and password.', 'أدخل البريد الإلكتروني وكلمة المرور.'));
    }
    if (!_setup && widget.store.started) {
      final ok = await confirm(
          context,
          tx('Use the shared data on this device?', 'استخدام البيانات المشتركة على هذا الجهاز؟'),
          tx('The data on this device will be replaced by the shared online data. Export a backup first if this device has work that is not online.',
              'ستُستبدل البيانات على هذا الجهاز بالبيانات المشتركة. صدّر نسخة احتياطية أولاً إذا كان على هذا الجهاز عمل غير موجود أونلاين.'),
          action: tx('Sign in', 'تسجيل الدخول'));
      if (!ok) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_setup) {
        await sync.createStore(_config, _email.text, _password.text, name: _name.text.trim());
      } else {
        await sync.signIn(_config, _email.text, _password.text);
      }
      if (mounted) {
        toast(context, tx('Signed in. This device now uses the shared data.', 'تم تسجيل الدخول. هذا الجهاز يستخدم البيانات المشتركة الآن.'));
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    if (_email.text.trim().isEmpty || !_config.isSet) {
      return setState(() => _error = tx('Type your email first.', 'اكتب بريدك الإلكتروني أولاً.'));
    }
    try {
      await CloudClient(_config).sendPasswordReset(_email.text);
      if (mounted) toast(context, tx('A password reset email was sent.', 'أُرسل بريد لإعادة تعيين كلمة المرور.'));
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_setup ? tx('Set up shared store', 'إعداد المخزن المشترك') : tx('Sign in', 'تسجيل الدخول'))),
      body: PageBody(maxWidth: 520, children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: AutofillGroup(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(
                  _setup
                      ? tx('Create the owner account. The data on this device becomes the shared data, and you can then add your team.',
                          'أنشئ حساب المالك. البيانات على هذا الجهاز تصبح البيانات المشتركة، ثم يمكنك إضافة فريقك.')
                      : tx('Sign in with the account the store owner made for you. Everyone on the team sees the same stock.',
                          'سجّل الدخول بالحساب الذي أنشأه لك مالك المخزن. كل الفريق يرى نفس المخزون.'),
                  style: TextStyle(color: t.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                if (_setup) ...[
                  TextField(controller: _name, decoration: InputDecoration(labelText: tx('Your name', 'اسمك'))),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: InputDecoration(labelText: tx('Email', 'البريد الإلكتروني')),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: _hide,
                  autofillHints: [_setup ? AutofillHints.newPassword : AutofillHints.password],
                  onSubmitted: (_) => _go(),
                  decoration: InputDecoration(
                    labelText: tx('Password', 'كلمة المرور'),
                    suffixIcon: IconButton(
                        onPressed: () => setState(() => _hide = !_hide), icon: Icon(_hide ? Icons.visibility : Icons.visibility_off)),
                  ),
                ),
                if (!_builtIn) ...[
                  const SizedBox(height: 16),
                  Text(tx('Firebase connection (from the setup steps)', 'اتصال Firebase (من خطوات الإعداد)'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  TextField(controller: _project, decoration: InputDecoration(labelText: tx('Project ID', 'معرّف المشروع'))),
                  const SizedBox(height: 12),
                  TextField(controller: _key, decoration: InputDecoration(labelText: tx('Web API key', 'مفتاح Web API'))),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: AppColors.bad, fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _go,
                  child: _busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_setup ? tx('Create store and sign in', 'إنشاء المخزن وتسجيل الدخول') : tx('Sign in', 'تسجيل الدخول')),
                ),
                const SizedBox(height: 8),
                Wrap(alignment: WrapAlignment.spaceBetween, children: [
                  if (!_setup) TextButton(onPressed: _forgot, child: Text(tx('Forgot password?', 'نسيت كلمة المرور؟'))),
                  TextButton(
                    onPressed: () => setState(() {
                      _setup = !_setup;
                      _error = null;
                    }),
                    child: Text(_setup
                        ? tx('I already have an account', 'لدي حساب بالفعل')
                        : tx('First time? Set up the shared store', 'أول مرة؟ أعدّ المخزن المشترك')),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// The "Online sharing" card in Settings.
class CloudCard extends StatelessWidget {
  const CloudCard({super.key, required this.store});
  final WarehouseStore store;

  @override
  Widget build(BuildContext context) {
    final c = store.cloud;
    if (c == null) return const SizedBox.shrink();
    final t = Theme.of(context);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(syncIcon(c.state), color: syncColor(c.state)),
              const SizedBox(width: 8),
              Expanded(child: Text(tx('Online sharing', 'المشاركة أونلاين'), style: t.textTheme.titleLarge)),
            ]),
            const SizedBox(height: 8),
            if (!c.signedIn) ...[
              Text(tx(
                  'Sign in so everyone on your team works on the same stock from their own iPad or phone. '
                      'The app still works without internet and sends changes when it is back.',
                  'سجّل الدخول ليعمل كل فريقك على نفس المخزون من أجهزتهم. '
                      'التطبيق يعمل بدون إنترنت ويرسل التغييرات عند عودة الاتصال.')),
              const SizedBox(height: 14),
              Wrap(spacing: 12, runSpacing: 12, children: [
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CloudSignInScreen(store: store))),
                  icon: const Icon(Icons.login),
                  label: Text(tx('Sign in', 'تسجيل الدخول')),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => CloudSignInScreen(store: store, setup: true))),
                  icon: const Icon(Icons.add_business_outlined),
                  label: Text(tx('Set up shared store', 'إعداد المخزن المشترك')),
                ),
              ]),
            ] else ...[
              Text(tx('Signed in as ${c.email}', 'مسجّل الدخول باسم ${c.email}'), style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(c.isOwner ? tx('Owner', 'المالك') : tx('Team member', 'عضو في الفريق'),
                  style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              Text(syncLine(c), style: TextStyle(color: syncColor(c.state), fontWeight: FontWeight.w600)),
              if (c.lastBy != null && c.lastBy != c.email)
                Text(tx('Last change online by ${c.lastBy}', 'آخر تغيير أونلاين من ${c.lastBy}'),
                    style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 14),
              Wrap(spacing: 12, runSpacing: 12, children: [
                FilledButton.tonalIcon(
                    onPressed: c.syncNow, icon: const Icon(Icons.sync), label: Text(tx('Sync now', 'مزامنة الآن'))),
                if (c.isOwner)
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TeamScreen(store: store))),
                    icon: const Icon(Icons.group_outlined),
                    label: Text(tx('Team', 'الفريق')),
                  ),
                OutlinedButton.icon(
                  onPressed: () async {
                    if (await confirm(
                        context,
                        tx('Sign out?', 'تسجيل الخروج؟'),
                        tx('The shared data is removed from this device. It stays online for the rest of the team.',
                            'ستُحذف البيانات المشتركة من هذا الجهاز، وتبقى أونلاين لبقية الفريق.'),
                        action: tx('Sign out', 'تسجيل الخروج'))) {
                      await c.syncNow();
                      await c.signOut();
                    }
                  },
                  icon: const Icon(Icons.logout),
                  label: Text(tx('Sign out', 'تسجيل الخروج')),
                ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Small cloud icon for the Home header: tap to open Settings.
class SyncBadge extends StatelessWidget {
  const SyncBadge({super.key, required this.store, required this.onTap});
  final WarehouseStore store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = store.cloud;
    if (c == null || !c.signedIn) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: c,
      builder: (_, _) => IconButton(
        tooltip: syncLine(c),
        onPressed: onTap,
        icon: Icon(syncIcon(c.state), color: Colors.white),
        style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: .14)),
      ),
    );
  }
}

/// The owner's list of people who can sign in.
class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key, required this.store});
  final WarehouseStore store;

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  List<Member>? _members;
  String? _error;

  CloudClient get _client => widget.store.cloud!.client!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final m = await _client.members();
      if (mounted) setState(() => _members = m);
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    }
  }

  Future<void> _add() async {
    final added = await showDialog<bool>(context: context, builder: (_) => _AddMemberDialog(client: _client));
    if (added == true) _load();
  }

  Future<void> _remove(Member m) async {
    if (!await confirm(context, tx('Remove ${m.email}?', 'إزالة ${m.email}؟'),
        tx('They can no longer see or change the shared data.', 'لن يتمكن من رؤية البيانات المشتركة أو تغييرها.'),
        action: tx('Remove', 'إزالة'))) {
      return;
    }
    try {
      await _client.removeMember(m.email);
      _load();
    } catch (e) {
      if (mounted) toast(context, _err(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.store.cloud!.email;
    final list = _members;
    return Scaffold(
      appBar: AppBar(title: Text(tx('Team', 'الفريق'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.person_add_alt),
        label: Text(tx('Add person', 'إضافة شخص')),
      ),
      body: PageBody(maxWidth: 720, children: [
        Text(tx('Everyone here can sign in and work on the shared stock. Owners can also add and remove people.',
            'كل من هنا يمكنه تسجيل الدخول والعمل على المخزون المشترك. المالك يمكنه أيضاً إضافة الأشخاص وإزالتهم.')),
        const SizedBox(height: 12),
        if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.bad)),
        if (list == null && _error == null) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
        if (list != null)
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final (i, m) in list.indexed) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  leading: CircleAvatar(child: Icon(m.isOwner ? Icons.verified_user_outlined : Icons.person_outline)),
                  title: Text(m.name.isEmpty ? m.email : m.name),
                  subtitle: Text('${m.email} · ${m.isOwner ? tx('Owner', 'المالك') : tx('Team member', 'عضو')}'),
                  trailing: m.email == me
                      ? Text(tx('You', 'أنت'))
                      : IconButton(
                          tooltip: tx('Remove', 'إزالة'), onPressed: () => _remove(m), icon: const Icon(Icons.person_remove_outlined)),
                ),
              ],
            ]),
          ),
      ]),
    );
  }
}

class _AddMemberDialog extends StatefulWidget {
  const _AddMemberDialog({required this.client});
  final CloudClient client;

  @override
  State<_AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<_AddMemberDialog> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _owner = false;
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    final email = _email.text.trim().toLowerCase();
    if (email.isEmpty) return setState(() => _error = tx('Enter their email.', 'أدخل بريده الإلكتروني.'));
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_password.text.isNotEmpty) {
        try {
          await widget.client.signUp(email, _password.text, keepCurrent: true);
        } on CloudError catch (e) {
          if (e.code != 'EMAIL_EXISTS') rethrow; // they already have an account: just add them
        }
      }
      await widget.client.setMember(Member(email: email, name: _name.text.trim(), role: _owner ? 'owner' : 'staff'));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tx('Add person', 'إضافة شخص')),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: _name, decoration: InputDecoration(labelText: tx('Name', 'الاسم'))),
            const SizedBox(height: 12),
            TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: tx('Email', 'البريد الإلكتروني'))),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              decoration: InputDecoration(
                labelText: tx('Password for them', 'كلمة مرور له'),
                helperText: tx('At least 6 characters. Give it to them; they can change it with "Forgot password".',
                    '6 أحرف على الأقل. أعطها له؛ ويمكنه تغييرها من "نسيت كلمة المرور".'),
                helperMaxLines: 3,
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _owner,
              onChanged: (v) => setState(() => _owner = v ?? false),
              contentPadding: EdgeInsets.zero,
              title: Text(tx('Owner (can manage the team)', 'مالك (يدير الفريق)')),
            ),
            if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.bad, fontWeight: FontWeight.w600)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tx('Cancel', 'إلغاء'))),
          FilledButton(onPressed: _busy ? null : _save, child: Text(tx('Add', 'إضافة'))),
        ],
      );
}

/// Settings for team members: language and the online account.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, required this.store});
  final WarehouseStore store;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tx('Account', 'الحساب'))),
        body: PageBody(maxWidth: 720, children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Expanded(child: Text('Language / اللغة', style: Theme.of(context).textTheme.titleLarge)),
                LanguageChips(store: store),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          CloudCard(store: store),
          const SizedBox(height: 12),
          Text(tx('Your account can issue supplies to departments. Ask the store owner for anything else.',
              'حسابك يستطيع صرف المواد إلى الأقسام. اطلب من مالك المخزن أي شيء آخر.')),
        ]),
      );
}
