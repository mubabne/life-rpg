import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data.dart';
import 'domain.dart';

const ink = Color(0xFF24352E);
const green = Color(0xFF426B50);
const paper = Color(0xFFF7F7F2);
const muted = Color(0xFF778078);
const line = Color(0xFFE5E8DF);

class LifeRpgApp extends StatelessWidget {
  const LifeRpgApp({super.key, this.client});
  final SupabaseClient? client;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Life RPG',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: green, surface: paper),
      scaffoldBackgroundColor: paper,
      fontFamily: 'Segoe UI',
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 38,
          height: 1.15,
          fontWeight: FontWeight.w800,
          color: ink,
          letterSpacing: -1.5,
        ),
        headlineMedium: TextStyle(
          fontSize: 27,
          fontWeight: FontWeight.w700,
          color: ink,
          letterSpacing: -.8,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: ink),
        bodySmall: TextStyle(fontSize: 12, height: 1.5, color: muted),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 19),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      dividerColor: line,
    ),
    home: AccountGate(client: client),
  );
}

class AccountGate extends StatefulWidget {
  const AccountGate({super.key, this.client});
  final SupabaseClient? client;
  @override
  State<AccountGate> createState() => _AccountGateState();
}

class _AccountGateState extends State<AccountGate> {
  bool preview = false;
  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    if (client == null) return const ProviderScope(child: GameShell());
    return StreamBuilder<AuthState>(
      stream: client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final user = client.auth.currentUser;
        if (user == null && !preview) {
          return SignInPage(
            client: client,
            onPreview: () => setState(() => preview = true),
          );
        }
        return ProviderScope(
          key: ValueKey(user?.id ?? 'preview'),
          overrides: [
            repositoryProvider.overrideWithValue(
              user == null
                  ? PreviewRepository()
                  : SupabaseGameRepository(client),
            ),
          ],
          child: GameShell(
            onAccount: () async {
              if (user == null) {
                setState(() => preview = false);
              } else {
                await client.auth.signOut();
              }
            },
          ),
        );
      },
    );
  }
}

class SignInPage extends StatefulWidget {
  const SignInPage({super.key, required this.client, required this.onPreview});
  final SupabaseClient client;
  final VoidCallback onPreview;
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  final form = GlobalKey<FormState>();
  bool busy = false, signup = false, hidden = true;
  String? error, notice;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      if (signup) {
        final response = await widget.client.auth.signUp(
          email: email.text.trim(),
          password: password.text,
          emailRedirectTo: kIsWeb ? Uri.base.origin : null,
        );
        if (mounted && response.session == null) {
          setState(
            () => notice = 'Almost there! Check your inbox to confirm your account, then sign in.',
          );
        }
      } else {
        await widget.client.auth.signInWithPassword(
          email: email.text.trim(),
          password: password.text,
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resetPassword() async {
    final address = email.text.trim();
    if (!address.contains('@')) {
      setState(
        () => error = 'Enter your email first, then tap “Forgot password?”.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      await widget.client.auth.resetPasswordForEmail(
        address,
        redirectTo: kIsWeb ? Uri.base.origin : null,
      );
      if (mounted) {
        setState(
          () => notice = 'If that account exists, a reset link is on its way.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Align(child: BrandMark(size: 64)),
                const SizedBox(height: 24),
                Text(
                  'A little better.\nEvery day.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Turn small steps into your next great adventure.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 36),
                TextFormField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) =>
                      v != null && v.contains('@') ? null : 'Enter your email',
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: password,
                  obscureText: hidden,
                  autofillHints: [
                    signup ? AutofillHints.newPassword : AutofillHints.password,
                  ],
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      tooltip: hidden ? 'Show password' : 'Hide password',
                      onPressed: () => setState(() => hidden = !hidden),
                      icon: Icon(
                        hidden
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (v) => v != null && v.length >= 8
                      ? null
                      : 'Use at least 8 characters',
                  onFieldSubmitted: (_) => busy ? null : submit(),
                ),
                if (!signup)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: busy ? null : resetPassword,
                      child: const Text('Forgot password?'),
                    ),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      error!,
                      style: const TextStyle(color: Color(0xFF986437)),
                    ),
                  ),
                if (notice != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(notice!, style: const TextStyle(color: green)),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: busy ? null : submit,
                  child: Text(
                    busy
                        ? 'One moment…'
                        : signup
                        ? 'Create your character'
                        : 'Continue your adventure',
                  ),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          signup = !signup;
                          error = null;
                        }),
                  child: Text(
                    signup
                        ? 'Already a member? Sign in'
                        : 'New here? Create an account',
                  ),
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: widget.onPreview,
                  child: const Text('Explore the preview'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class GameShell extends ConsumerStatefulWidget {
  const GameShell({super.key, this.onAccount});
  final AsyncCallback? onAccount;
  @override
  ConsumerState<GameShell> createState() => _GameShellState();
}

typedef AsyncCallback = Future<void> Function();

class _GameShellState extends ConsumerState<GameShell>
    with WidgetsBindingObserver {
  int page = 0;
  String filter = 'Today';
  final busyIds = <String>{};
  static const pages = ['Quest board', 'Habits', 'Character', 'Weekly review'];
  static const icons = [
    Icons.dashboard_outlined,
    Icons.spa_outlined,
    Icons.person_outline_rounded,
    Icons.auto_stories_outlined,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.invalidate(gameProvider);
  }

  void message(String text) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
  );
  Future<void> perform(
    String key,
    String action,
    Map<String, dynamic> args, [
    String? success,
  ]) async {
    if (busyIds.contains(key)) return;
    setState(() => busyIds.add(key));
    try {
      await ref.read(gameProvider.notifier).act(action, args);
      if (mounted && success != null) message(success);
    } catch (e) {
      if (mounted) message(friendlyError(e));
    } finally {
      if (mounted) setState(() => busyIds.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(gameProvider);
    final preview = ref.watch(repositoryProvider).isPreview;
    final wide = MediaQuery.sizeOf(context).width >= 960;
    return Scaffold(
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: page,
              onDestinationSelected: (v) => setState(() => page = v),
              destinations: [
                for (var i = 0; i < pages.length; i++)
                  NavigationDestination(
                    icon: Icon(icons[i]),
                    label: ['Quests', 'Habits', 'Character', 'Review'][i],
                  ),
              ],
            ),
      body: Row(
        children: [
          if (wide)
            Container(
              width: 230,
              color: const Color(0xFF203B2C),
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(26, 32, 20, 42),
                      child: Row(
                        children: [
                          BrandMark(),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'life rpg',
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              style: TextStyle(
                                fontSize: 23,
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    for (var i = 0; i < pages.length; i++)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                        child: Material(
                          color: Colors.transparent,
                          child: ListTile(
                            selected: page == i,
                            selectedTileColor: Colors.white.withValues(
                              alpha: .1,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            leading: Icon(
                              icons[i],
                              color: page == i
                                  ? const Color(0xFFCCE1A2)
                                  : const Color(0xFF9DB1A2),
                            ),
                            title: Text(
                              pages[i],
                              style: TextStyle(
                                color: page == i
                                    ? Colors.white
                                    : const Color(0xFFADBCB0),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            onTap: () => setState(() => page = i),
                          ),
                        ),
                      ),
                    const Spacer(),
                    const Padding(
                      padding: EdgeInsets.all(26),
                      child: Text(
                        'GROW AT YOUR OWN PACE\n\nEvery small step is part\nof a bigger story.',
                        style: TextStyle(
                          color: Color(0xFFAFC3AE),
                          fontSize: 12,
                          height: 1.7,
                          letterSpacing: .5,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: TextButton.icon(
                        onPressed: widget.onAccount,
                        icon: Icon(
                          preview ? Icons.login : Icons.logout,
                          size: 18,
                        ),
                        label: Text(preview ? 'Sign in' : 'Sign out'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: SafeArea(
              child: Column(
                children: [
                  Container(
                    height: 76,
                    padding: EdgeInsets.symmetric(horizontal: wide ? 36 : 20),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: line)),
                    ),
                    child: Row(
                      children: [
                        if (!wide)
                          const Padding(
                            padding: EdgeInsets.only(right: 10),
                            child: BrandMark(size: 30),
                          ),
                        Expanded(
                          child: Text(
                            pages[page],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (preview)
                          const BadgePill('PREVIEW', color: Color(0xFF887245)),
                        const SizedBox(width: 14),
                        IconButton(
                          tooltip: 'Get quests with AI',
                          onPressed: () => showImport(),
                          icon: const Icon(
                            Icons.auto_awesome_outlined,
                            size: 22,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Settings',
                          onPressed: () => showSettings(async.value),
                          icon: const Icon(Icons.tune_rounded, size: 21),
                        ),
                        if (!wide && widget.onAccount != null)
                          IconButton(
                            tooltip: preview ? 'Sign in' : 'Sign out',
                            onPressed: widget.onAccount,
                            icon: Icon(
                              preview ? Icons.login : Icons.logout,
                              size: 21,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: async.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(30),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.cloud_off_rounded,
                                size: 40,
                                color: muted,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                friendlyError(e),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: () => ref.invalidate(gameProvider),
                                child: const Text('Try again'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      data: (game) => RefreshIndicator(
                        onRefresh: () async {
                          try {
                            await ref.read(gameProvider.notifier).refresh();
                          } catch (e) {
                            if (mounted) message(friendlyError(e));
                          }
                        },
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.all(wide ? 36 : 20),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1180),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (preview)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 22,
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.explore_outlined,
                                            color: green,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 9),
                                          const Expanded(
                                            child: Text(
                                              'A peek at your next adventure. Sign in to save your progress.',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: muted,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  switch (page) {
                                    0 => questBoard(game, wide),
                                    1 => habitBoard(game),
                                    2 => characterBoard(game),
                                    _ => reviewBoard(game),
                                  },
                                  const SizedBox(height: 30),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget questBoard(GameSnapshot game, bool wide) {
    final completed = game.quests.where((q) => q.completed).length;
    final filtered = game.quests.where((q) {
      if (filter == 'Completed') return q.completed;
      if (q.status != 'pending') return false;
      return switch (filter) {
        'Today' => q.dueDate.compareTo(game.today) <= 0,
        'Weekly' => q.cadence == 'weekly',
        'Monthly' => q.cadence == 'monthly',
        _ => true,
      };
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.wb_sunny_outlined, size: 17, color: green),
            const SizedBox(width: 8),
            Text(
              DateFormat('EEEE, MMMM d')
                  .format(DateTime.parse(game.today))
                  .toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: green,
                letterSpacing: 1.6,
              ),
            ),
          ],
        ),
        const SizedBox(height: 17),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 24,
          runSpacing: 20,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your next chapter\nstarts today.',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Small quests. Real growth. A life well played.',
                  style: TextStyle(color: muted, fontSize: 14),
                ),
              ],
            ),
            SizedBox(
              width: wide ? 310 : double.infinity,
              child: Surface(
                child: Row(
                  children: [
                    const CharacterEmblem(size: 66),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'LEVEL ${game.level} · ADVENTURER',
                            style: const TextStyle(
                              fontSize: 10,
                              letterSpacing: 1,
                              color: green,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            game.name,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 9),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: game.levelFraction,
                              minHeight: 5,
                              color: green,
                              backgroundColor: line,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${game.progress['xp_into_level']} / ${game.progress['xp_to_next']} XP to next level',
                            style: const TextStyle(fontSize: 10, color: muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 24) return const SizedBox.shrink();
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                MetricTile(
                  width: (constraints.maxWidth - 24) / 3,
                  label: 'QUESTS FINISHED',
                  value: '$completed',
                  icon: Icons.check_circle_outline,
                  color: green,
                ),
                MetricTile(
                  width: (constraints.maxWidth - 24) / 3,
                  label: 'TOTAL XP',
                  value: '${game.xp}',
                  icon: Icons.bolt_rounded,
                  color: const Color(0xFF9473B8),
                ),
                MetricTile(
                  width: (constraints.maxWidth - 24) / 3,
                  label: 'GOLD EARNED',
                  value: '${game.gold}',
                  icon: Icons.toll_rounded,
                  color: const Color(0xFFB18A3D),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 34),
        Row(
          children: [
            Expanded(
              child: Text(
                'The quest board',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: () => showQuestForm(game),
              icon: const Icon(Icons.add, size: 17),
              label: const Text('New quest'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final label in [
              'Today',
              'Weekly',
              'Monthly',
              'All',
              'Completed',
            ])
              ChoiceChip(
                label: Text(label),
                selected: filter == label,
                showCheckmark: false,
                onSelected: (_) => setState(() => filter = label),
                side: BorderSide(color: filter == label ? green : line),
                selectedColor: green,
                backgroundColor: Colors.white,
                labelStyle: TextStyle(
                  color: filter == label ? Colors.white : muted,
                  fontSize: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        if (filtered.isEmpty)
          Surface(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Column(
                children: [
                  const Icon(Icons.landscape_outlined, color: green, size: 42),
                  const SizedBox(height: 14),
                  Text(
                    filter == 'Completed'
                        ? 'Your story is just getting started.'
                        : 'A little room for your next adventure.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Create a quest, or tap ✨ to have AI plan your week.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        for (final quest in filtered)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: questCard(quest, game.today),
          ),
        const SizedBox(height: 22),
        Row(
          children: [
            const Icon(Icons.repeat_rounded, color: green, size: 19),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Recurring responsibilities',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: () => showTemplates(game),
              child: Text('${game.templates.length} active · Manage'),
            ),
          ],
        ),
        const Text(
          'Your essentials stay on the board. Flexible challenges grow with you.',
          style: TextStyle(fontSize: 12, color: muted),
        ),
      ],
    );
  }

  Widget questCard(Quest q, String today) => Surface(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 43,
          height: 43,
          decoration: BoxDecoration(
            color: q.stat.color.withValues(alpha: .18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            q.stat.icon,
            size: 21,
            color: Color.lerp(q.stat.color, ink, .35),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 5,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    q.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      decoration: q.completed
                          ? TextDecoration.lineThrough
                          : null,
                      color: q.completed ? muted : ink,
                    ),
                  ),
                  if (q.source == 'ai')
                    const BadgePill('AI QUEST', color: Color(0xFF8D79A3)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                q.description,
                style: const TextStyle(fontSize: 12, color: muted),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 13,
                runSpacing: 8,
                children: [
                  BadgePill(
                    q.stat.label,
                    color: Color.lerp(q.stat.color, ink, .4)!,
                  ),
                  SmallLabel(Icons.schedule, '${q.minutes} min'),
                  SmallLabel(
                    Icons.event_outlined,
                    q.dueDate.compareTo(today) < 0
                        ? 'Overdue · ${q.dueDate}'
                        : q.dueDate == today
                        ? 'Due today'
                        : q.dueDate,
                  ),
                  Text(
                    '+${q.xp} XP',
                    style: const TextStyle(
                      color: green,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                  SmallLabel(
                    Icons.toll_outlined,
                    '+${q.gold}',
                    color: const Color(0xFFAA8137),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 5),
        Column(
          children: [
            IconButton(
              tooltip: q.completed ? 'Completed' : 'Complete quest',
              onPressed: q.completed || busyIds.contains(q.id)
                  ? null
                  : () => perform(q.id, 'complete_quest', {
                      'id': q.id,
                    }, 'Quest complete. Your rewards have been saved.'),
              icon: busyIds.contains(q.id)
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      q.completed
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked,
                      color: q.completed ? green : const Color(0xFFB9C3B5),
                    ),
            ),
            if (!q.completed)
              IconButton(
                tooltip: 'Skip quest',
                onPressed: () => showSkip(q),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.more_horiz, size: 18, color: muted),
              ),
          ],
        ),
      ],
    ),
  );

  Widget habitBoard(GameSnapshot game) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Build your everyday magic.',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 8),
      const Text(
        'Consistency grows slowly. A missed day is just a small dent.',
        style: TextStyle(color: muted),
      ),
      const SizedBox(height: 26),
      Row(
        children: [
          Expanded(
            child: Text(
              'Your habits',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: () => showHabitForm(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New habit'),
          ),
        ],
      ),
      const SizedBox(height: 18),
      if (game.habits.isEmpty)
        const Surface(
          child: Text(
            'Start with something small: a glass of water, a page of reading, or a moment outside.',
          ),
        ),
      for (final habit in game.habits)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      habit.stat.icon,
                      color: Color.lerp(habit.stat.color, ink, .4),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        habit.title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Archive habit',
                      onPressed: () => confirmArchive(habit),
                      icon: const Icon(
                        Icons.archive_outlined,
                        size: 18,
                        color: muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 18,
                  runSpacing: 12,
                  children: [
                    SmallLabel(
                      Icons.local_fire_department_outlined,
                      '${habit.streak} day streak',
                    ),
                    SmallLabel(
                      Icons.ac_unit_rounded,
                      '${habit.freezesLeft} freezes left',
                    ),
                    const SmallLabel(Icons.bolt_rounded, '+5 XP per check-in'),
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    for (var i = 0; i < habit.week.length; i++)
                      Expanded(
                        child: Column(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: habit.week[i] == 'completed'
                                    ? green
                                    : habit.week[i] == 'frozen'
                                    ? const Color(0xFFDDEDF6)
                                    : const Color(0xFFF0F1EA),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                habit.week[i] == 'completed'
                                    ? Icons.check
                                    : habit.week[i] == 'frozen'
                                    ? Icons.ac_unit
                                    : Icons.remove,
                                size: 15,
                                color: habit.week[i] == 'completed'
                                    ? Colors.white
                                    : muted,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              DateFormat('EEEEE').format(
                                DateTime.parse(game.today)
                                    .subtract(Duration(days: 6 - i)),
                              ),
                              style: const TextStyle(
                                fontSize: 10,
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  'Habit strength · ${(habit.strength * 100).round()}%',
                  style: const TextStyle(fontSize: 12, color: muted),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: habit.strength,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(6),
                  backgroundColor: line,
                  color: green,
                ),
                const SizedBox(height: 18),
                FilledButton.tonalIcon(
                  onPressed: habit.completedToday || busyIds.contains(habit.id)
                      ? null
                      : () => perform(habit.id, 'checkin_habit', {
                          'id': habit.id,
                        }, 'One small step, saved. +5 XP'),
                  icon: Icon(
                    habit.completedToday ? Icons.check : Icons.add_task_rounded,
                    size: 18,
                  ),
                  label: Text(
                    habit.completedToday
                        ? 'Done for today'
                        : busyIds.contains(habit.id)
                        ? 'Saving…'
                        : 'Check in today',
                  ),
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 8),
      const Text(
        'Two automatic freezes per habit each month protect your streak and strength. Frozen days earn no XP.',
        style: TextStyle(color: muted, fontSize: 12),
      ),
    ],
  );

  Widget characterBoard(GameSnapshot game) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Meet your growing self.',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 8),
      const Text(
        'Every quest leaves a little something with you.',
        style: TextStyle(color: muted),
      ),
      const SizedBox(height: 26),
      Surface(
        child: Column(
          children: [
            const CharacterEmblem(size: 100),
            const SizedBox(height: 18),
            Text(game.name, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            BadgePill('LEVEL ${game.level} · ADVENTURER', color: green),
            const SizedBox(height: 24),
            LinearProgressIndicator(
              value: game.levelFraction,
              minHeight: 8,
              borderRadius: BorderRadius.circular(8),
              backgroundColor: line,
              color: green,
            ),
            const SizedBox(height: 10),
            Text(
              '${game.xp} lifetime XP · ${game.gold} gold',
              style: const TextStyle(color: muted),
            ),
          ],
        ),
      ),
      const SizedBox(height: 28),
      Text(
        'Five paths of growth',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 16),
      for (final stat in LifeStat.values)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Surface(
            child: Row(
              children: [
                Icon(stat.icon, color: Color.lerp(stat.color, ink, .3)),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    stat.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${game.stats[stat.name] ?? 0} XP',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: green,
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );

  Widget reviewBoard(GameSnapshot game) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Pause. Reflect. Grow.',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 8),
      const Text(
        'A kinder look at the week behind you.',
        style: TextStyle(color: muted),
      ),
      const SizedBox(height: 26),
      Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BadgePill('WEEK OF ${game.review['week_start']}', color: green),
            const SizedBox(height: 22),
            Wrap(
              spacing: 35,
              runSpacing: 20,
              children: [
                ReviewNumber('${game.review['completed']}', 'Completed', green),
                ReviewNumber('${game.review['skipped']}', 'Skipped', muted),
                ReviewNumber(
                  '${game.review['overdue']}',
                  'Unfinished',
                  const Color(0xFFB18A3D),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              game.review['message'] as String,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 12),
            Text(
              'Next flexible workload cap: ${game.review['next_capacity']} minutes.',
              style: const TextStyle(color: muted),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.auto_awesome_outlined, color: green),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Help your next quests fit your life',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Copy this review into your ChatGPT quest chat before the next weekly run. Your finished and skipped quests help shape what comes next.',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 18),
            SelectableText(
              game.review['export_text'] as String,
              style: const TextStyle(fontSize: 12, height: 1.8),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: game.review['export_text'] as String),
                );
                if (mounted) message('Weekly review copied.');
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy for ChatGPT'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      OutlinedButton.icon(
        onPressed: () => showReviewNotes(),
        icon: const Icon(Icons.edit_note_rounded),
        label: const Text('Add a reflection'),
      ),
    ],
  );

  Future<void> showQuestForm(GameSnapshot game) async {
    await showDialog<void>(
      context: context,
      builder: (_) => QuestForm(
        today: game.today,
        onSave: (action, args) =>
            ref.read(gameProvider.notifier).act(action, args),
      ),
    );
  }

  Future<void> showHabitForm() async {
    await showDialog<void>(
      context: context,
      builder: (_) => HabitForm(
        onSave: (args) =>
            ref.read(gameProvider.notifier).act('create_habit', args),
      ),
    );
  }

  Future<void> showImport() async {
    await showDialog<void>(
      context: context,
      builder: (_) {
        final game = ref.read(gameProvider).value;
        final preview = ref.read(repositoryProvider).isPreview;
        return ImportDialog(
          receipts: game?.imports ?? [],
          prompt: game == null ? null : chatGptPrompt(game),
          onGenerate: preview
              ? null
              : (week, focus) => ref
                    .read(gameProvider.notifier)
                    .generate(week: week, focus: focus),
          onSave: (batch) => ref.read(gameProvider.notifier).act(
            'import_batch',
            {'batch': batch},
          ),
        );
      },
    );
  }

  Future<void> showSettings(GameSnapshot? game) async {
    if (game == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => SettingsDialog(
        game: game,
        onSave: (args) => ref.read(gameProvider.notifier).act('settings', args),
      ),
    );
  }

  Future<void> showSkip(Quest q) async {
    final reason = TextEditingController();
    final skip = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Make room for real life'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Skip “${q.title}”? A short reason helps shape your next quests.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reason,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'What got in the way?',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep quest'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Skip quest'),
          ),
        ],
      ),
    );
    if (skip == true) {
      await perform(q.id, 'skip_quest', {
        'id': q.id,
        'reason': reason.text,
      }, 'Quest skipped. Your next chapter can adjust.');
    }
    reason.dispose();
  }

  Future<void> confirmArchive(Habit h) async {
    final archive = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive this habit?'),
        content: Text(
          '“${h.title}” will stop appearing. Your past check-ins stay in your story.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (archive == true) await perform(h.id, 'archive_habit', {'id': h.id});
  }

  Future<void> showTemplates(GameSnapshot game) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your recurring responsibilities'),
        content: SizedBox(
          width: 440,
          child: game.templates.isEmpty
              ? const Text(
                  'Create a quest and turn on “Repeat this responsibility” to keep essentials coming back.',
                )
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final t in game.templates)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(t['title'] as String),
                          subtitle: Text(t['cadence'] as String),
                          trailing: IconButton(
                            tooltip: 'Stop repeating',
                            icon: const Icon(Icons.pause_circle_outline),
                            onPressed: () {
                              Navigator.pop(ctx);
                              perform(t['id'] as String, 'archive_template', {
                                'id': t['id'],
                              });
                            },
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> showReviewNotes() async {
    final notes = TextEditingController();
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('How did this week feel?'),
        content: SizedBox(
          width: 460,
          child: TextField(
            controller: notes,
            maxLines: 5,
            maxLength: 2000,
            decoration: const InputDecoration(
              hintText: 'What worked? What should be lighter next week?',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save reflection'),
          ),
        ],
      ),
    );
    if (save == true) {
      await perform('notes', 'review_notes', {
        'notes': notes.text,
      }, 'Reflection saved.');
    }
    notes.dispose();
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 36});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: const Color(0xFFD2E4AF),
      borderRadius: BorderRadius.circular(size * .28),
    ),
    child: Icon(
      Icons.spa_rounded,
      color: const Color(0xFF365740),
      size: size * .6,
    ),
  );
}

class CharacterEmblem extends StatelessWidget {
  const CharacterEmblem({super.key, this.size = 70});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: const Color(0xFFEDF1E2),
      borderRadius: BorderRadius.circular(size * .25),
      border: Border.all(color: const Color(0xFFD6DFC3), width: 2),
    ),
    child: Stack(
      alignment: Alignment.center,
      children: [
        Icon(
          Icons.landscape_rounded,
          size: size * .8,
          color: const Color(0xFFC7D6AC),
        ),
        Positioned(
          bottom: size * .12,
          child: Icon(Icons.hiking_rounded, size: size * .65, color: green),
        ),
        Positioned(
          top: size * .12,
          right: size * .12,
          child: Icon(
            Icons.auto_awesome,
            color: const Color(0xFFC7AA67),
            size: size * .2,
          ),
        ),
      ],
    ),
  );
}

class Surface extends StatelessWidget {
  const Surface({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: line),
    ),
    child: child,
  );
}

class BadgePill extends StatelessWidget {
  const BadgePill(this.text, {super.key, required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 9,
        letterSpacing: .6,
        color: color,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class SmallLabel extends StatelessWidget {
  const SmallLabel(this.icon, this.text, {super.key, this.color = muted});
  final IconData icon;
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 4),
      Text(text, style: TextStyle(fontSize: 10, color: color)),
    ],
  );
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final double width;
  final String label, value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              letterSpacing: .8,
              color: muted,
            ),
          ),
        ],
      ),
    ),
  );
}

class ReviewNumber extends StatelessWidget {
  const ReviewNumber(this.value, this.label, this.color, {super.key});
  final String value, label;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: TextStyle(
          fontSize: 36,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
      Text(label, style: const TextStyle(color: muted, fontSize: 12)),
    ],
  );
}

class QuestForm extends StatefulWidget {
  const QuestForm({super.key, required this.today, required this.onSave});
  final String today;
  final Future<void> Function(String, Map<String, dynamic>) onSave;
  @override
  State<QuestForm> createState() => _QuestFormState();
}

class _QuestFormState extends State<QuestForm> {
  final form = GlobalKey<FormState>();
  final title = TextEditingController(),
      description = TextEditingController(),
      minutes = TextEditingController(text: '15');
  LifeStat stat = LifeStat.mind;
  String cadence = 'daily';
  int difficulty = 1;
  bool repeat = false, busy = false;
  String? error;
  late String due = widget.today;
  @override
  void dispose() {
    title.dispose();
    description.dispose();
    minutes.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.onSave(repeat ? 'create_template' : 'create_quest', {
        'title': title.text.trim(),
        'description': description.text.trim(),
        'stat_tag': stat.name,
        'cadence': cadence,
        'difficulty': difficulty,
        'estimated_minutes': int.parse(minutes.text),
        'due_local_date': due,
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('A new side quest'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: title,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'What will you do?',
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Give your quest a title'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: description,
                maxLength: 2000,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'A little more detail',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<LifeStat>(
                initialValue: stat,
                decoration: const InputDecoration(labelText: 'Life area'),
                items: [
                  for (final s in LifeStat.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (v) => setState(() => stat = v!),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: cadence,
                decoration: const InputDecoration(labelText: 'Cadence'),
                items: [
                  for (final s in ['daily', 'weekly', 'monthly'])
                    DropdownMenuItem(
                      value: s,
                      child: Text('${s[0].toUpperCase()}${s.substring(1)}'),
                    ),
                ],
                onChanged: (v) => setState(() => cadence = v!),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: difficulty,
                decoration: const InputDecoration(labelText: 'Difficulty'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Easy')),
                  DropdownMenuItem(value: 2, child: Text('Medium')),
                  DropdownMenuItem(value: 3, child: Text('Hard')),
                ],
                onChanged: (v) => setState(() => difficulty = v!),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: minutes,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Estimated minutes',
                ),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  return n == null || n < 1 || n > 480
                      ? 'Use 1–480 minutes'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final day = await showDatePicker(
                    context: context,
                    initialDate: DateTime.parse(due),
                    firstDate: DateTime.parse(widget.today),
                    lastDate: DateTime.parse(widget.today)
                        .add(const Duration(days: 365)),
                  );
                  if (day != null) {
                    setState(() => due = DateFormat('yyyy-MM-dd').format(day));
                  }
                },
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text('Due $due'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Repeat this responsibility',
                  style: TextStyle(fontSize: 13),
                ),
                subtitle: const Text('Creates a new quest each period.'),
                value: repeat,
                onChanged: (v) => setState(() => repeat = v),
              ),
              if (error != null)
                Text(
                  error!,
                  style: const TextStyle(
                    color: Colors.deepOrange,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: busy ? null : save,
        child: Text(busy ? 'Saving…' : 'Add quest'),
      ),
    ],
  );
}

class HabitForm extends StatefulWidget {
  const HabitForm({super.key, required this.onSave});
  final Future<void> Function(Map<String, dynamic>) onSave;
  @override
  State<HabitForm> createState() => _HabitFormState();
}

class _HabitFormState extends State<HabitForm> {
  final title = TextEditingController();
  LifeStat stat = LifeStat.health;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Start something small'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: title,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Your daily habit'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<LifeStat>(
            initialValue: stat,
            decoration: const InputDecoration(labelText: 'Life area'),
            items: [
              for (final s in LifeStat.values)
                DropdownMenuItem(value: s, child: Text(s.label)),
            ],
            onChanged: (v) => setState(() => stat = v!),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                error!,
                style: const TextStyle(color: Colors.deepOrange),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: busy
            ? null
            : () async {
                if (title.text.trim().isEmpty) {
                  setState(() => error = 'Give your habit a name.');
                  return;
                }
                setState(() {
                  busy = true;
                  error = null;
                });
                try {
                  await widget.onSave({
                    'title': title.text.trim(),
                    'stat_tag': stat.name,
                  });
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (mounted) setState(() => error = friendlyError(e));
                } finally {
                  if (mounted) setState(() => busy = false);
                }
              },
        child: Text(busy ? 'Saving…' : 'Create habit'),
      ),
    ],
  );
}

class ImportDialog extends StatefulWidget {
  const ImportDialog({
    super.key,
    required this.onSave,
    this.onGenerate,
    this.prompt,
    this.receipts = const [],
  });
  final Future<void> Function(Map<String, dynamic>) onSave;
  final Future<AiPlan> Function(String week, String focus)? onGenerate;
  final String? prompt;
  final List<Map<String, dynamic>> receipts;
  @override
  State<ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<ImportDialog> {
  final input = TextEditingController();
  final focus = TextEditingController();
  bool busy = false, generating = false, copied = false;
  String week = 'auto';
  String? error, aiError;
  AiPlan? plan;
  Map<String, dynamic>? batch;
  @override
  void dispose() {
    input.dispose();
    focus.dispose();
    super.dispose();
  }

  Future<void> generate() async {
    setState(() {
      generating = true;
      aiError = null;
      plan = null;
    });
    try {
      final result = await widget.onGenerate!(week, focus.text.trim());
      if (mounted) setState(() => plan = result);
    } catch (e) {
      if (mounted) setState(() => aiError = friendlyError(e));
    } finally {
      if (mounted) setState(() => generating = false);
    }
  }

  Widget section(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(subtitle, style: const TextStyle(color: muted, fontSize: 13)),
      const SizedBox(height: 12),
    ],
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Get your next quests'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.onGenerate != null) ...[
              section(
                'Plan with AI',
                'GPT reads your weekly review, habits and pending quests, then adds a balanced set of quests within your weekly budget.',
              ),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'auto', label: Text('Auto')),
                  ButtonSegment(value: 'current', label: Text('This week')),
                  ButtonSegment(value: 'next', label: Text('Next week')),
                ],
                selected: {week},
                onSelectionChanged: generating
                    ? null
                    : (v) => setState(() => week = v.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: focus,
                maxLength: 500,
                enabled: !generating,
                decoration: const InputDecoration(
                  labelText: 'Anything to focus on? (optional)',
                  hintText: 'e.g. exams on Friday, start running again',
                ),
              ),
              FilledButton.icon(
                onPressed: generating || busy ? null : generate,
                icon: generating
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text(
                  generating ? 'Planning your week…' : 'Generate quests',
                ),
              ),
              if (plan != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Added ${plan!.count} quests for the week of ${plan!.periodStart}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: green,
                  ),
                ),
                for (final t in plan!.titles)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('• $t'),
                  ),
              ],
              if (aiError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    aiError!,
                    style: const TextStyle(color: Colors.deepOrange),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Divider(),
              ),
            ],
            section(
              'Or use your ChatGPT subscription',
              'Free: copy the prompt, paste it into ChatGPT, then paste its JSON answer below. You’ll review the titles before importing.',
            ),
            if (widget.prompt != null) ...[
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: widget.prompt!));
                  if (mounted) setState(() => copied = true);
                },
                icon: Icon(
                  copied ? Icons.check_rounded : Icons.copy_rounded,
                  size: 18,
                ),
                label: Text(
                  copied
                      ? 'Prompt copied, now ask ChatGPT'
                      : 'Copy prompt for ChatGPT',
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (widget.receipts.isNotEmpty) ...[
              const Text(
                'Recent email imports',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final receipt in widget.receipts.take(3))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    receipt['status'] == 'committed'
                        ? 'Imported · ${receipt['gmail_message_id']}'
                        : 'Needs attention · ${receipt['error']}',
                    style: TextStyle(
                      fontSize: 12,
                      color: receipt['status'] == 'committed'
                          ? green
                          : const Color(0xFF986437),
                    ),
                  ),
                ),
              const SizedBox(height: 14),
            ],
            TextField(
              controller: input,
              maxLines: 8,
              maxLength: 64000,
              decoration: const InputDecoration(
                hintText: '{ "schema_version": 1, … }',
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              onChanged: (_) => setState(() {
                batch = null;
                error = null;
              }),
            ),
            if (batch != null) ...[
              const SizedBox(height: 12),
              Text(
                '${(batch!['quests'] as List).length} quests to import',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final q in batch!['quests'] as List)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('• ${q is Map ? q['title'] : 'Invalid quest'}'),
                ),
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error!,
                  style: const TextStyle(color: Colors.deepOrange),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy || generating ? null : () => Navigator.pop(context),
        child: Text(plan != null ? 'Done' : 'Cancel'),
      ),
      FilledButton(
        onPressed: busy || generating || input.text.trim().isEmpty
            ? null
            : () async {
                if (batch == null) {
                  try {
                    setState(() {
                      batch = parseQuestBatch(input.text);
                      error = null;
                    });
                  } catch (e) {
                    setState(() => error = friendlyError(e));
                  }
                  return;
                }
                setState(() {
                  busy = true;
                  error = null;
                });
                try {
                  await widget.onSave(batch!);
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (mounted) setState(() => error = friendlyError(e));
                } finally {
                  if (mounted) setState(() => busy = false);
                }
              },
        child: Text(
          busy
              ? 'Importing…'
              : batch == null
              ? 'Review pasted JSON'
              : 'Import quests',
        ),
      ),
    ],
  );
}

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key, required this.game, required this.onSave});
  final GameSnapshot game;
  final Future<void> Function(Map<String, dynamic>) onSave;
  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final name = TextEditingController(text: widget.game.name);
  late final timezone = TextEditingController(
    text: widget.game.profile['timezone'] as String,
  );
  late final capacity = TextEditingController(
    text: '${widget.game.profile['weekly_capacity']}',
  );
  bool busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    timezone.dispose();
    capacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Your adventure, your pace'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'Character name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: timezone,
              decoration: const InputDecoration(
                labelText: 'Time zone',
                helperText: 'For example: Asia/Ulaanbaatar',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: capacity,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Weekly flexible quest budget (minutes)',
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Weeks start Monday. Changes to your time zone apply to future days; past check-ins stay saved.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.deepOrange)),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: busy
            ? null
            : () async {
                final minutes = int.tryParse(capacity.text);
                if (name.text.trim().isEmpty ||
                    minutes == null ||
                    minutes < 15 ||
                    minutes > 10080) {
                  setState(
                    () => error =
                        'Enter a name and a budget of 15–10080 minutes.',
                  );
                  return;
                }
                setState(() {
                  busy = true;
                  error = null;
                });
                try {
                  await widget.onSave({
                    'display_name': name.text.trim(),
                    'timezone': timezone.text.trim(),
                    'weekly_capacity': minutes,
                  });
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (mounted) setState(() => error = friendlyError(e));
                } finally {
                  if (mounted) setState(() => busy = false);
                }
              },
        child: Text(busy ? 'Saving…' : 'Save settings'),
      ),
    ],
  );
}
