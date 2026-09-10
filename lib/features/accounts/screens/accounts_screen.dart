import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/balance_visibility.dart';
import '../widgets/account_form_sheet.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _accounts = [];
  bool _loading = true;
  DateTime? _lastLoaded;
  static const _cacheValidity = Duration(minutes: 3);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _lastLoaded != null &&
        _accounts.isNotEmpty &&
        DateTime.now().difference(_lastLoaded!) < _cacheValidity) {
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await _supabase
          .from('accounts')
          .select()
          .eq('is_active', true)
          .order('created_at', ascending: false);
      setState(() {
        _accounts = List<Map<String, dynamic>>.from(res);
        _lastLoaded = DateTime.now();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm({Map<String, dynamic>? account}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => AccountFormSheet(account: account),
    );
    if (result == true) _load(forceRefresh: true);
  }

  Future<void> _delete(Map<String, dynamic> account) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Akun'),
        content: Text(
          'Hapus akun "${account['name']}"? Semua transaksi terkait akan terpengaruh.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _supabase
          .from('accounts')
          .update({'is_active': false}).eq('id', account['id']);
      _load(forceRefresh: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus: $e')),
        );
      }
    }
  }

  String _typeLabel(String type) {
    const labels = {
      'bank': 'Bank',
      'ewallet': 'E-Wallet',
      'cash': 'Tunai',
      'investment': 'Investasi',
    };
    return labels[type] ?? type;
  }

  IconData _typeIcon(String type) {
    const icons = {
      'bank': Icons.account_balance,
      'ewallet': Icons.phone_android,
      'cash': Icons.payments,
      'investment': Icons.trending_up,
    };
    return icons[type] ?? Icons.account_balance_wallet;
  }

  @override
  Widget build(BuildContext context) {
    final fmt =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final cnyFmt =
        NumberFormat.currency(locale: 'zh_CN', symbol: '¥ ', decimalDigits: 2);

    // Group totals per currency — don't mix IDR and CNY
    final Map<String, double> totalByCurrency = {};
    for (final acc in _accounts) {
      final currency = (acc['currency_code'] as String?) ?? 'IDR';
      totalByCurrency[currency] =
          (totalByCurrency[currency] ?? 0) +
          (acc['current_balance'] as num).toDouble();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Akun Saya')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _load(forceRefresh: true),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'Total Saldo',
                              style: TextStyle(fontSize: 13),
                            ),
                            const SizedBox(width: 8),
                            ValueListenableBuilder<bool>(
                              valueListenable: BalanceVisibility.hidden,
                              builder: (_, hidden, _) => GestureDetector(
                                onTap: BalanceVisibility.toggle,
                                child: Icon(
                                  hidden
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  size: 18,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ValueListenableBuilder<bool>(
                          valueListenable: BalanceVisibility.hidden,
                          builder: (_, hidden, _) {
                            if (hidden) {
                              return const Text(
                                '••••••',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            }
                            if (totalByCurrency.isEmpty) {
                              return const Text(
                                'Rp 0',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            }
                            return Column(
                              children: totalByCurrency.entries
                                  .map(
                                    (e) => Text(
                                      (e.key == 'CNY' ? cnyFmt : fmt)
                                          .format(e.value),
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  )
                                  .toList(),
                            );
                          },
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_accounts.length} akun aktif',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_accounts.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: Text(
                          'Belum ada akun\nTap + untuk menambah',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    ..._accounts.map((acc) {
                      final balance =
                          (acc['current_balance'] as num).toDouble();
                      final colorHex = acc['color'] ?? '#1976D2';
                      final color = Color(
                        int.parse(colorHex.replaceFirst('#', '0xFF')),
                      );
                      return Dismissible(
                        key: Key('acc_${acc['id']}'),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) async {
                          await _delete(acc);
                          return false;
                        },
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.delete, color: Colors.red),
                        ),
                        child: Card(
                          elevation: 0,
                          color:
                              Theme.of(context).colorScheme.surfaceContainerLowest,
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            onTap: () => _openForm(account: acc),
                            leading: CircleAvatar(
                              backgroundColor: color.withValues(alpha: 0.15),
                              child: Icon(_typeIcon(acc['type']), color: color),
                            ),
                            title: Text(
                              acc['name'],
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(_typeLabel(acc['type'])),
                            trailing: ValueListenableBuilder<bool>(
                              valueListenable: BalanceVisibility.hidden,
                              builder: (_, hidden, _) => Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    hidden
                                        ? '••••••'
                                        : (acc['currency_code'] == 'CNY'
                                                ? cnyFmt
                                                : fmt)
                                            .format(balance),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    acc['currency_code'] ?? 'IDR',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
