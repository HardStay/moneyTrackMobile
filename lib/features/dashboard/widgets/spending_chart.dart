import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SpendingChart extends StatefulWidget {
  final String period; // 'day' | 'month' | 'year' — controlled by parent
  const SpendingChart({super.key, required this.period});

  @override
  State<SpendingChart> createState() => _SpendingChartState();
}

class _SpendingChartState extends State<SpendingChart> {
  final _supabase = Supabase.instance.client;

  String _showType = 'both'; // 'both' | 'income' | 'expense'
  String _currency = 'IDR';
  List<String> _availableCurrencies = [];
  bool _loading = true;
  List<_Entry> _data = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SpendingChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period != widget.period) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final now = DateTime.now();

      final DateTime rangeStart;
      if (widget.period == 'day') {
        rangeStart = now.subtract(const Duration(days: 6));
      } else if (widget.period == 'month') {
        rangeStart = DateTime(now.year, now.month - 5, 1);
      } else {
        rangeStart = DateTime(now.year - 4, 1, 1);
      }

      final startStr = rangeStart.toIso8601String().split('T')[0];

      final accRes = await _supabase
          .from('accounts')
          .select('id, currency_code')
          .eq('is_active', true);

      final Map<String, List<dynamic>> accountsByCurrency = {};
      for (final a in accRes as List) {
        final c = (a['currency_code'] as String?) ?? 'IDR';
        accountsByCurrency.putIfAbsent(c, () => []).add(a['id']);
      }

      final available = accountsByCurrency.keys.toList()..sort();

      if (!accountsByCurrency.containsKey(_currency)) {
        _currency = available.isNotEmpty ? available.first : 'IDR';
      }

      final selectedIds = accountsByCurrency[_currency] ?? [];

      if (selectedIds.isEmpty) {
        setState(() {
          _availableCurrencies = available;
          _data = _buildEmptyData(now);
        });
        return;
      }

      final txRes = await _supabase
          .from('transactions')
          .select('type, amount, transaction_date, account_id')
          .gte('transaction_date', startStr)
          .inFilter('account_id', selectedIds)
          .neq('type', 'transfer');

      final Map<String, double> income = {};
      final Map<String, double> expense = {};

      for (final tx in txRes as List) {
        final date = DateTime.parse(tx['transaction_date'] as String);
        final key = _periodKey(date);
        final amount = (tx['amount'] as num).toDouble();
        if (tx['type'] == 'income') {
          income[key] = (income[key] ?? 0) + amount;
        } else {
          expense[key] = (expense[key] ?? 0) + amount;
        }
      }

      setState(() {
        _availableCurrencies = available;
        _data = _buildData(now, income, expense);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat grafik: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _periodKey(DateTime d) {
    if (widget.period == 'day') {
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    } else if (widget.period == 'month') {
      return '${d.year}-${d.month.toString().padLeft(2, '0')}';
    } else {
      return '${d.year}';
    }
  }

  List<_Entry> _buildData(
    DateTime now,
    Map<String, double> income,
    Map<String, double> expense,
  ) {
    final List<_Entry> result = [];
    if (widget.period == 'day') {
      for (int i = 6; i >= 0; i--) {
        final d = now.subtract(Duration(days: i));
        final key = _periodKey(d);
        result.add(_Entry(
          key: key,
          label: '${d.day}/${d.month}',
          income: income[key] ?? 0,
          expense: expense[key] ?? 0,
        ));
      }
    } else if (widget.period == 'month') {
      for (int i = 5; i >= 0; i--) {
        final d = DateTime(now.year, now.month - i, 1);
        final key = _periodKey(d);
        result.add(_Entry(
          key: key,
          label: DateFormat('MMM', 'id_ID').format(d),
          income: income[key] ?? 0,
          expense: expense[key] ?? 0,
        ));
      }
    } else {
      for (int i = 4; i >= 0; i--) {
        final d = DateTime(now.year - i);
        final key = _periodKey(d);
        result.add(_Entry(
          key: key,
          label: '${d.year}',
          income: income[key] ?? 0,
          expense: expense[key] ?? 0,
        ));
      }
    }
    return result;
  }

  List<_Entry> _buildEmptyData(DateTime now) => _buildData(now, {}, {});

  static String _shortAmount(double v, String currency) {
    if (currency == 'CNY') {
      if (v >= 10000) return '${(v / 10000).toStringAsFixed(1)}w';
      if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
      return v.toStringAsFixed(0);
    }
    if (v >= 1000000000) return '${(v / 1000000000).toStringAsFixed(1)}M';
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(0)}jt';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}rb';
    return v.toStringAsFixed(0);
  }

  List<BarChartGroupData> _buildGroups() {
    final showIncome = _showType == 'both' || _showType == 'income';
    final showExpense = _showType == 'both' || _showType == 'expense';
    const incomeColor = Color(0xFF4CAF50);
    const expenseColor = Color(0xFFE53935);

    return _data.asMap().entries.map((e) {
      final i = e.key;
      final d = e.value;
      final rods = <BarChartRodData>[
        if (showIncome)
          BarChartRodData(
            toY: d.income,
            color: incomeColor,
            width: _showType == 'both' ? 7 : 14,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        if (showExpense)
          BarChartRodData(
            toY: d.expense,
            color: expenseColor,
            width: _showType == 'both' ? 7 : 14,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
      ];
      return BarChartGroupData(x: i, barRods: rods, barsSpace: 3);
    }).toList();
  }

  NumberFormat get _tooltipFmt => _currency == 'CNY'
      ? NumberFormat.currency(locale: 'zh_CN', symbol: '¥ ', decimalDigits: 2)
      : NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  @override
  Widget build(BuildContext context) {
    final showIncome = _showType == 'both' || _showType == 'income';
    final showExpense = _showType == 'both' || _showType == 'expense';
    final showCurrencySelector = _availableCurrencies.length > 1;

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with legend
            Row(
              children: [
                const Text(
                  'Grafik Keuangan',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (showIncome) ...[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Color(0xFF4CAF50),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Masuk',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(width: 8),
                ],
                if (showExpense) ...[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE53935),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Keluar',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),

            // Type selector
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'both', label: Text('Semua')),
                ButtonSegment(value: 'income', label: Text('Pemasukan')),
                ButtonSegment(value: 'expense', label: Text('Pengeluaran')),
              ],
              selected: {_showType},
              onSelectionChanged: (v) => setState(() => _showType = v.first),
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),

            // Currency selector — only when user has both IDR and CNY
            if (showCurrencySelector) ...[
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: _availableCurrencies
                    .map((c) => ButtonSegment(value: c, label: Text(c)))
                    .toList(),
                selected: {_currency},
                onSelectionChanged: (v) {
                  setState(() => _currency = v.first);
                  _load();
                },
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
            ],
            const SizedBox(height: 16),

            // Chart
            SizedBox(
              height: 200,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: _data.isEmpty
                            ? 1
                            : _data.fold<double>(
                                    0,
                                    (m, e) => [
                                          m,
                                          if (showIncome) e.income,
                                          if (showExpense) e.expense,
                                        ].reduce((a, b) => a > b ? a : b)) *
                                1.2,
                        barGroups: _buildGroups(),
                        gridData: const FlGridData(
                          show: true,
                          drawVerticalLine: false,
                        ),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 24,
                              getTitlesWidget: (value, meta) {
                                final i = value.toInt();
                                if (i < 0 || i >= _data.length) {
                                  return const SizedBox();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    _data[i].label,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                );
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 44,
                              getTitlesWidget: (value, meta) {
                                if (value == 0) {
                                  return const Text(
                                    '0',
                                    style: TextStyle(fontSize: 9),
                                  );
                                }
                                return Text(
                                  _shortAmount(value, _currency),
                                  style: const TextStyle(fontSize: 9),
                                );
                              },
                            ),
                          ),
                        ),
                        barTouchData: BarTouchData(
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipColor: (_) => Colors.black87,
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              if (groupIndex >= _data.length) return null;
                              final entry = _data[groupIndex];
                              final isIncome =
                                  showIncome && (!showExpense || rodIndex == 0);
                              final type =
                                  isIncome ? 'Pemasukan' : 'Pengeluaran';
                              final amount =
                                  isIncome ? entry.income : entry.expense;
                              return BarTooltipItem(
                                '${entry.label}\n$type\n${_tooltipFmt.format(amount)}',
                                const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Entry {
  final String key;
  final String label;
  final double income;
  final double expense;
  const _Entry({
    required this.key,
    required this.label,
    required this.income,
    required this.expense,
  });
}
