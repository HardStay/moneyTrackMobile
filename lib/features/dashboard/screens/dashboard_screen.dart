import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../../core/balance_visibility.dart';
import '../widgets/spending_chart.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = false;
  String _period = 'day'; // 'day' | 'month' | 'year'
  static const _cacheValidity = Duration(minutes: 3);

  // Per-period cache: period → (data, loadedAt)
  final Map<String, ({Map<String, dynamic> data, DateTime loadedAt})>
      _cacheByPeriod = {};

  bool _isCacheValid(String p) {
    final e = _cacheByPeriod[p];
    if (e == null) return false;
    return DateTime.now().difference(e.loadedAt) < _cacheValidity;
  }

  Map<String, dynamic>? get _summary => _cacheByPeriod[_period]?.data;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary({bool forceRefresh = false}) async {
    if (forceRefresh) _cacheByPeriod.clear(); // flush all periods on manual refresh
    if (_isCacheValid(_period)) {
      setState(() {}); // rebuild to display cached data
      return;
    }
    setState(() => _loading = true);
    // Capture period at the start — user might switch while awaiting
    final period = _period;
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final accountsRes = await _supabase
          .from('accounts')
          .select('id, current_balance, currency_code')
          .eq('is_active', true);

      final Map<String, double> balanceByCurrency = {};
      final Map<dynamic, String> accountCurrency = {};
      for (final acc in accountsRes as List) {
        final currency = (acc['currency_code'] as String?) ?? 'IDR';
        balanceByCurrency[currency] =
            (balanceByCurrency[currency] ?? 0) +
            (acc['current_balance'] as num).toDouble();
        accountCurrency[acc['id']] = currency;
      }

      // Date range based on period
      final now = DateTime.now();
      final String firstDay, lastDay;
      if (period == 'day') {
        final today = now.toIso8601String().split('T')[0];
        firstDay = today;
        lastDay = today;
      } else if (period == 'year') {
        firstDay = DateTime(now.year, 1, 1).toIso8601String().split('T')[0];
        lastDay = DateTime(now.year, 12, 31).toIso8601String().split('T')[0];
      } else {
        firstDay =
            DateTime(now.year, now.month, 1).toIso8601String().split('T')[0];
        lastDay = DateTime(
          now.year,
          now.month + 1,
          0,
        ).toIso8601String().split('T')[0];
      }

      final txRes = await _supabase
          .from('transactions')
          .select('type, amount, account_id')
          .gte('transaction_date', firstDay)
          .lte('transaction_date', lastDay);

      final Map<String, double> incomeByCur = {};
      final Map<String, double> expenseByCur = {};
      for (final tx in txRes as List) {
        final currency = accountCurrency[tx['account_id']];
        if (currency == null) continue;
        final amount = (tx['amount'] as num).toDouble();
        if (tx['type'] == 'income') {
          incomeByCur[currency] = (incomeByCur[currency] ?? 0) + amount;
        } else if (tx['type'] == 'expense') {
          expenseByCur[currency] = (expenseByCur[currency] ?? 0) + amount;
        }
      }
      // Pastikan kedua kartu selalu punya set currency yang sama —
      // isi 0 untuk currency yang punya akun tapi tidak ada transaksi di periode ini
      for (final currency in balanceByCurrency.keys) {
        incomeByCur.putIfAbsent(currency, () => 0);
        expenseByCur.putIfAbsent(currency, () => 0);
      }

      if (mounted) {
        setState(() {
          _cacheByPeriod[period] = (
            data: {
              'balanceByCurrency': balanceByCurrency,
              'monthIncomeByCurrency': incomeByCur,
              'monthExpenseByCurrency': expenseByCur,
            },
            loadedAt: DateTime.now(),
          );
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat data: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name =
        _supabase.auth.currentUser?.userMetadata?['full_name'] ?? 'User';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Halo, ${name.toString().split(' ').first} 👋',
              style: const TextStyle(fontSize: 16),
            ),
            const Text(
              'MoneyTrack',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadSummary(forceRefresh: true),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _loadSummary(forceRefresh: true),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _TotalBalanceCard(
                    balanceByCurrency: Map<String, double>.from(
                      _summary?['balanceByCurrency'] ?? {'IDR': 0.0},
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Shared period selector
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'day', label: Text('Harian')),
                      ButtonSegment(value: 'month', label: Text('Bulanan')),
                      ButtonSegment(value: 'year', label: Text('Tahunan')),
                    ],
                    selected: {_period},
                    onSelectionChanged: (v) {
                      setState(() => _period = v.first);
                      _loadSummary(); // pakai cache kalau sudah ada
                    },
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: _SummaryCard(
                          label: _period == 'day'
                              ? 'Pemasukan Hari Ini'
                              : _period == 'year'
                                  ? 'Pemasukan Tahun Ini'
                                  : 'Pemasukan Bulan Ini',
                          amountByCurrency: Map<String, double>.from(
                            _summary?['monthIncomeByCurrency'] ?? {},
                          ),
                          color: const Color(0xFF4CAF50),
                          icon: Icons.arrow_downward,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SummaryCard(
                          label: _period == 'day'
                              ? 'Pengeluaran Hari Ini'
                              : _period == 'year'
                                  ? 'Pengeluaran Tahun Ini'
                                  : 'Pengeluaran Bulan Ini',
                          amountByCurrency: Map<String, double>.from(
                            _summary?['monthExpenseByCurrency'] ?? {},
                          ),
                          color: const Color(0xFFE53935),
                          icon: Icons.arrow_upward,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SpendingChart(period: _period),
                ],
              ),
            ),
    );
  }
}

class _TotalBalanceCard extends StatelessWidget {
  final Map<String, double> balanceByCurrency;
  const _TotalBalanceCard({required this.balanceByCurrency});

  static final _fmtIDR =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  static final _fmtCNY =
      NumberFormat.currency(locale: 'zh_CN', symbol: '¥ ', decimalDigits: 2);

  String _format(String currency, double amount) {
    return currency == 'CNY'
        ? _fmtCNY.format(amount)
        : _fmtIDR.format(amount);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1976D2), Color(0xFF42A5F5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Total Saldo',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const Spacer(),
              ValueListenableBuilder<bool>(
                valueListenable: BalanceVisibility.hidden,
                builder: (_, hidden, _) => GestureDetector(
                  onTap: BalanceVisibility.toggle,
                  child: Icon(
                    hidden ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white70,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<bool>(
            valueListenable: BalanceVisibility.hidden,
            builder: (_, hidden, _) {
              if (hidden) {
                return const Text(
                  '••••••',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                );
              }
              if (balanceByCurrency.isEmpty) {
                return const Text(
                  'Rp 0',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: balanceByCurrency.entries
                    .map(
                      (e) => Text(
                        _format(e.key, e.value),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 4),
          Text(
            'Bulan ${DateFormat('MMMM yyyy', 'id_ID').format(DateTime.now())}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final Map<String, double> amountByCurrency;
  final Color color;
  final IconData icon;

  const _SummaryCard({
    required this.label,
    required this.amountByCurrency,
    required this.color,
    required this.icon,
  });

  static final _fmtIDR =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  static final _fmtCNY =
      NumberFormat.currency(locale: 'zh_CN', symbol: '¥ ', decimalDigits: 2);

  String _format(String currency, double amount) =>
      currency == 'CNY' ? _fmtCNY.format(amount) : _fmtIDR.format(amount);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<bool>(
            valueListenable: BalanceVisibility.hidden,
            builder: (_, hidden, _) {
              if (hidden) {
                return Text(
                  '••••••',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                );
              }
              if (amountByCurrency.isEmpty) {
                return Text(
                  _fmtIDR.format(0),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: amountByCurrency.entries
                    .map(
                      (e) => Text(
                        _format(e.key, e.value),
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
