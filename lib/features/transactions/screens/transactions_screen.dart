import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/balance_visibility.dart';
import 'add_edit_transaction_screen.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final _supabase = Supabase.instance.client;
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timer? _debounce;

  // Normal paginated list
  List<Map<String, dynamic>> _transactions = [];
  bool _loading = true;
  bool _loadingMore = false; // synchronous guard — prevents duplicate in-flight requests
  String _filterType = 'all';
  int _page = 0;
  static const _pageSize = 20;
  bool _hasMore = true;
  DateTime? _lastLoaded;
  String? _lastLoadedFilter;
  String? _lastLoadedDatePreset;
  static const _cacheValidity = Duration(minutes: 3);

  // Date filter
  String _datePreset = 'all';
  DateTimeRange? _dateFilter;

  // Search state
  List<Map<String, dynamic>>? _searchResults;
  bool _searchLoading = false;

  // Selection state
  bool _selectMode = false;
  final Set<dynamic> _selectedIds = {};
  final Map<dynamic, GlobalKey> _tileKeys = {};

  bool get _isSearching => _searchCtrl.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_isSearching || _loadingMore || !_hasMore) return;
    final pos = _scrollCtrl.position;
    // Start loading 300px before reaching the bottom
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      _load();
    }
  }

  // ── Normal paginated load ─────────────────────────────────────────────────

  Future<void> _load({bool reset = false, bool forceRefresh = false}) async {
    // Skip initial load if cache is valid and all filters match
    if (reset &&
        !forceRefresh &&
        _lastLoaded != null &&
        _lastLoadedFilter == _filterType &&
        _lastLoadedDatePreset == _datePreset &&
        _transactions.isNotEmpty &&
        DateTime.now().difference(_lastLoaded!) < _cacheValidity) {
      return;
    }
    if (_loadingMore) return; // guard: reject if a request is already in-flight
    if (reset) {
      _page = 0;
      _hasMore = true;
      _transactions = [];
      _clearSelection();
    }
    if (!_hasMore) return;
    _loadingMore = true;
    setState(() => _loading = true);
    try {
      var query = _supabase
          .from('transactions')
          .select(
            '*, accounts!account_id(name, currency_code), categories(name, icon, color)',
          );

      if (_filterType != 'all') query = query.eq('type', _filterType);
      if (_dateFilter != null) {
        final s = _dateFilter!.start.toIso8601String().split('T')[0];
        final e = _dateFilter!.end.toIso8601String().split('T')[0];
        query = query.gte('transaction_date', s).lte('transaction_date', e);
      }

      final res = await query
          .order('transaction_date', ascending: false)
          .order('created_at', ascending: false)
          .range(_page * _pageSize, (_page + 1) * _pageSize - 1);

      final list = List<Map<String, dynamic>>.from(res);
      if (mounted) {
        setState(() {
          _transactions.addAll(list);
          _hasMore = list.length == _pageSize;
          _page++;
          if (_page == 1) {
            _lastLoaded = DateTime.now();
            _lastLoadedFilter = _filterType;
            _lastLoadedDatePreset = _datePreset;
          }
        });
      }
    } finally {
      _loadingMore = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Search ────────────────────────────────────────────────────────────────

  void _onSearchChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    if (value.isEmpty) {
      setState(() {
        _searchResults = null;
        _searchLoading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _performSearch(value);
    });
  }

  Future<void> _performSearch(String text) async {
    if (text.isEmpty) return;
    setState(() => _searchLoading = true);
    try {
      final futures = await Future.wait([
        _supabase.from('categories').select('id').ilike('name', '%$text%'),
        _supabase.from('accounts').select('id').ilike('name', '%$text%'),
      ]);

      final catIds = (futures[0] as List).map((c) => c['id']).toList();
      final accIds = (futures[1] as List).map((a) => a['id']).toList();

      final orParts = <String>['description.ilike.%$text%'];
      if (catIds.isNotEmpty) orParts.add('category_id.in.(${catIds.join(',')})');
      if (accIds.isNotEmpty) orParts.add('account_id.in.(${accIds.join(',')})');

      final numA = double.tryParse(text.replaceAll(',', ''));
      final numB = double.tryParse(
        text.replaceAll(',', '').replaceAll('.', ''),
      );
      for (final n in {numA, numB}) {
        if (n != null && n > 0) orParts.add('amount.eq.$n');
      }

      var txQuery = _supabase
          .from('transactions')
          .select(
            '*, accounts!account_id(name, currency_code), categories(name, icon, color)',
          )
          .or(orParts.join(','));

      if (_filterType != 'all') txQuery = txQuery.eq('type', _filterType);
      if (_dateFilter != null) {
        final s = _dateFilter!.start.toIso8601String().split('T')[0];
        final e = _dateFilter!.end.toIso8601String().split('T')[0];
        txQuery = txQuery.gte('transaction_date', s).lte('transaction_date', e);
      }

      final res = await txQuery
          .order('transaction_date', ascending: false)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(
          () => _searchResults = List<Map<String, dynamic>>.from(res),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mencari: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _searchLoading = false);
    }
  }

  // ── Selection ─────────────────────────────────────────────────────────────

  void _enterSelectMode(dynamic txId) {
    setState(() {
      _selectMode = true;
      _selectedIds.add(txId);
    });
  }

  void _toggleSelect(dynamic txId) {
    setState(() {
      if (_selectedIds.contains(txId)) {
        _selectedIds.remove(txId);
        if (_selectedIds.isEmpty) _selectMode = false;
      } else {
        _selectedIds.add(txId);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectMode = false;
      _selectedIds.clear();
    });
  }

  // ── Date filter ───────────────────────────────────────────────────────────

  DateTimeRange _computeRange(String preset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (preset) {
      case 'today':
        return DateTimeRange(start: today, end: today);
      case 'week':
        final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
        return DateTimeRange(start: startOfWeek, end: today);
      case 'month':
        return DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: DateTime(now.year, now.month + 1, 0),
        );
      case 'lastMonth':
        return DateTimeRange(
          start: DateTime(now.year, now.month - 1, 1),
          end: DateTime(now.year, now.month, 0),
        );
      default:
        return DateTimeRange(start: today, end: today);
    }
  }

  String get _datePresetLabel {
    switch (_datePreset) {
      case 'today':
        return 'Hari Ini';
      case 'week':
        return 'Minggu Ini';
      case 'month':
        return 'Bulan Ini';
      case 'lastMonth':
        return 'Bulan Lalu';
      case 'custom':
        if (_dateFilter != null) {
          final fmt = DateFormat('d MMM', 'id_ID');
          final s = fmt.format(_dateFilter!.start);
          final e = fmt.format(_dateFilter!.end);
          return s == e ? s : '$s – $e';
        }
        return 'Kustom';
      default:
        return 'Semua Waktu';
    }
  }

  Future<void> _showDateFilterSheet() async {
    final presets = [
      ('all', 'Semua Waktu', Icons.all_inclusive),
      ('today', 'Hari Ini', Icons.today),
      ('week', 'Minggu Ini', Icons.view_week),
      ('month', 'Bulan Ini', Icons.calendar_month),
      ('lastMonth', 'Bulan Lalu', Icons.chevron_left),
      ('custom', 'Kustom...', Icons.date_range),
    ];

    final selected = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Filter Tanggal',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...presets.map(
              (p) => ListTile(
                leading: Icon(p.$3),
                title: Text(p.$2),
                trailing: _datePreset == p.$1
                    ? Icon(
                        Icons.check,
                        color: Theme.of(ctx).colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.pop(ctx, p.$1),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (selected == null || !mounted) return;

    if (selected == 'custom') {
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        initialDateRange: _dateFilter,
      );
      if (range == null || !mounted) return;
      setState(() {
        _datePreset = 'custom';
        _dateFilter = range;
      });
    } else {
      setState(() {
        _datePreset = selected;
        _dateFilter = selected == 'all' ? null : _computeRange(selected);
      });
    }

    if (_isSearching) {
      _performSearch(_searchCtrl.text);
    } else {
      _load(reset: true, forceRefresh: true);
    }
  }

  void _clearDateFilter() {
    setState(() {
      _datePreset = 'all';
      _dateFilter = null;
    });
    if (_isSearching) {
      _performSearch(_searchCtrl.text);
    } else {
      _load(reset: true, forceRefresh: true);
    }
  }

  // Hit-test: find which tile's GlobalKey contains the given global position
  void _selectItemAt(Offset globalPos) {
    for (final entry in _tileKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize || !box.attached) continue;
      final topLeft = box.localToGlobal(Offset.zero);
      if ((topLeft & box.size).contains(globalPos)) {
        if (!_selectedIds.contains(entry.key)) {
          setState(() => _selectedIds.add(entry.key));
        }
        return;
      }
    }
  }

  GlobalKey _keyFor(dynamic txId) =>
      _tileKeys.putIfAbsent(txId, () => GlobalKey());

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _openForm({Map<String, dynamic>? tx}) async {
    if (_selectMode) return;
    final result = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddEditTransactionScreen(transaction: tx),
      ),
    );
    if (result == true) {
      if (_isSearching) {
        _performSearch(_searchCtrl.text);
      } else {
        _load(reset: true, forceRefresh: true);
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> tx) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Transaksi'),
        content: const Text('Yakin ingin menghapus transaksi ini?'),
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
      await _supabase.from('transactions').delete().eq('id', tx['id']);
      if (_isSearching) {
        _performSearch(_searchCtrl.text);
      } else {
        _load(reset: true, forceRefresh: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus: $e')),
        );
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final fmt =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return PopScope(
      canPop: !_selectMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectMode) _clearSelection();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Transaksi'),
          actions: [
            IconButton(
              icon: Badge(
                isLabelVisible: _datePreset != 'all',
                child: const Icon(Icons.tune),
              ),
              onPressed: _showDateFilterSheet,
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'all', label: Text('Semua')),
                  ButtonSegment(value: 'income', label: Text('Masuk')),
                  ButtonSegment(value: 'expense', label: Text('Keluar')),
                  ButtonSegment(value: 'transfer', label: Text('Transfer')),
                ],
                selected: {_filterType},
                onSelectionChanged: (v) {
                  setState(() => _filterType = v.first);
                  if (_isSearching) {
                    _performSearch(_searchCtrl.text);
                  } else {
                    _load(reset: true, forceRefresh: true);
                  }
                },
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ),
        ),
        floatingActionButton: _selectMode
            ? null
            : FloatingActionButton(
                onPressed: () => _openForm(),
                child: const Icon(Icons.add),
              ),
        body: Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Cari deskripsi, kategori, akun, nominal...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            _onSearchChanged('');
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor:
                      Theme.of(context).colorScheme.surfaceContainerLowest,
                ),
                onChanged: _onSearchChanged,
              ),
            ),

            // Active date filter chip
            if (_datePreset != 'all')
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: Row(
                  children: [
                    InputChip(
                      avatar: const Icon(Icons.calendar_month, size: 16),
                      label: Text(
                        _datePresetLabel,
                        style: const TextStyle(fontSize: 12),
                      ),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      onDeleted: _clearDateFilter,
                      onPressed: _showDateFilterSheet,
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.08),
                    ),
                  ],
                ),
              ),

            // Transaction list
            Expanded(child: _buildList(fmt)),

            // Selection summary bar
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              child: _selectMode
                  ? _buildSelectionBar(fmt)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionBar(NumberFormat _) {
    // Accumulate totals per currency — no mixing IDR with CNY
    final Map<String, double> incByCur = {};
    final Map<String, double> expByCur = {};

    final allKnown = <dynamic, Map<String, dynamic>>{
      for (final tx in _transactions) tx['id']: tx,
      for (final tx in _searchResults ?? []) tx['id']: tx,
    };
    for (final id in _selectedIds) {
      final tx = allKnown[id];
      if (tx == null) continue;
      final amount = (tx['amount'] as num).toDouble();
      final cur = (tx['accounts']?['currency_code'] as String?) ?? 'IDR';
      if (tx['type'] == 'income') {
        incByCur[cur] = (incByCur[cur] ?? 0) + amount;
      } else if (tx['type'] == 'expense') {
        expByCur[cur] = (expByCur[cur] ?? 0) + amount;
      }
    }

    // Format preserving exact decimals
    String fmtAmt(double v, String cur) {
      final hasDecimal = (v - v.truncateToDouble()).abs() > 1e-9;
      if (cur == 'CNY') {
        return NumberFormat.currency(
          locale: 'zh_CN',
          symbol: '¥ ',
          decimalDigits: 2,
        ).format(v);
      }
      return NumberFormat.currency(
        locale: 'id_ID',
        symbol: 'Rp ',
        decimalDigits: hasDecimal ? 2 : 0,
      ).format(v);
    }

    final allCurrencies = {...incByCur.keys, ...expByCur.keys}.toList()..sort();
    final hasAny = allCurrencies.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 16, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: _clearSelection,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          ),
          const SizedBox(width: 4),
          Text(
            '${_selectedIds.length} dipilih',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const Spacer(),
          ValueListenableBuilder<bool>(
            valueListenable: BalanceVisibility.hidden,
            builder: (_, hidden, _) {
              if (!hasAny) {
                // Only transfers selected
                return Text(
                  'Transfer saja',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                );
              }
              return Wrap(
                spacing: 10,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  for (final cur in allCurrencies) ...[
                    if ((incByCur[cur] ?? 0) > 0)
                      Text(
                        hidden
                            ? '+••••••'
                            : '+${fmtAmt(incByCur[cur]!, cur)}',
                        style: const TextStyle(
                          color: Color(0xFF4CAF50),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    if ((expByCur[cur] ?? 0) > 0)
                      Text(
                        hidden
                            ? '-••••••'
                            : '-${fmtAmt(expByCur[cur]!, cur)}',
                        style: const TextStyle(
                          color: Color(0xFFE53935),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildList(NumberFormat fmt) {
    if (_isSearching) {
      if (_searchLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      final results = _searchResults ?? [];
      if (results.isEmpty && _searchResults != null) {
        return const Center(
          child: Text(
            'Tidak ada hasil',
            style: TextStyle(color: Colors.grey),
          ),
        );
      }
      if (_searchResults == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        itemCount: results.length,
        itemBuilder: (context, index) {
          final tx = results[index];
          final txId = tx['id'];
          return _TxTile(
            tx: tx,
            formatter: fmt,
            tileKey: _keyFor(txId),
            selectMode: _selectMode,
            isSelected: _selectedIds.contains(txId),
            onTap: () => _selectMode ? _toggleSelect(txId) : _openForm(tx: tx),
            onDelete: () => _delete(tx),
            onLongPress: () => _enterSelectMode(txId),
            onLongPressMoveUpdate: (d) => _selectItemAt(d.globalPosition),
          );
        },
      );
    }

    if (_loading && _transactions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true, forceRefresh: true),
      child: _transactions.isEmpty
          ? const Center(
              child: Text(
                'Belum ada transaksi\nTap + untuk menambah',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            )
          : ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              itemCount: _transactions.length + (_loadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _transactions.length) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                final tx = _transactions[index];
                final txId = tx['id'];
                return _TxTile(
                  tx: tx,
                  formatter: fmt,
                  tileKey: _keyFor(txId),
                  selectMode: _selectMode,
                  isSelected: _selectedIds.contains(txId),
                  onTap: () =>
                      _selectMode ? _toggleSelect(txId) : _openForm(tx: tx),
                  onDelete: () => _delete(tx),
                  onLongPress: () => _enterSelectMode(txId),
                  onLongPressMoveUpdate: (d) =>
                      _selectItemAt(d.globalPosition),
                );
              },
            ),
    );
  }
}

// ── Tile ──────────────────────────────────────────────────────────────────────

class _TxTile extends StatelessWidget {
  final Map<String, dynamic> tx;
  final NumberFormat formatter;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final bool selectMode;
  final bool isSelected;
  final VoidCallback onLongPress;
  final void Function(LongPressMoveUpdateDetails) onLongPressMoveUpdate;
  final GlobalKey tileKey;

  const _TxTile({
    required this.tx,
    required this.formatter,
    required this.onTap,
    required this.onDelete,
    required this.selectMode,
    required this.isSelected,
    required this.onLongPress,
    required this.onLongPressMoveUpdate,
    required this.tileKey,
  });

  @override
  Widget build(BuildContext context) {
    final type = tx['type'] as String;
    final amount = (tx['amount'] as num).toDouble();
    final isIncome = type == 'income';
    final isTransfer = type == 'transfer';
    final color = isTransfer
        ? const Color(0xFF1976D2)
        : isIncome
            ? const Color(0xFF4CAF50)
            : const Color(0xFFE53935);
    final sign = isIncome ? '+' : isTransfer ? '' : '-';
    final category =
        tx['categories']?['name'] ?? (isTransfer ? 'Transfer' : 'Lainnya');
    final account = tx['accounts']?['name'] ?? '';
    final currency = (tx['accounts']?['currency_code'] as String?) ?? 'IDR';
    final txFmt = currency == 'CNY'
        ? NumberFormat.currency(locale: 'zh_CN', symbol: '¥ ', decimalDigits: 2)
        : formatter;
    final date = DateFormat('d MMM yyyy', 'id_ID')
        .format(DateTime.parse(tx['transaction_date']));
    final balanceBefore = tx['balance_before'] != null
        ? (tx['balance_before'] as num).toDouble()
        : null;

    final primaryColor = Theme.of(context).colorScheme.primary;

    return Dismissible(
      key: Key('tx_${tx['id']}'),
      // Disable swipe-to-delete while in selection mode
      direction:
          selectMode ? DismissDirection.none : DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
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
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        onLongPressMoveUpdate: onLongPressMoveUpdate,
        child: Card(
          key: tileKey,
          elevation: 0,
          color: isSelected
              ? primaryColor.withValues(alpha: 0.1)
              : Theme.of(context).colorScheme.surfaceContainerLowest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isSelected
                ? BorderSide(color: primaryColor, width: 1.5)
                : BorderSide.none,
          ),
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: selectMode
                ? AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? primaryColor : Colors.transparent,
                      border: Border.all(
                        color:
                            isSelected ? primaryColor : Colors.grey.shade400,
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 20)
                        : null,
                  )
                : CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.1),
                    child: Icon(
                      isTransfer
                          ? Icons.swap_horiz
                          : isIncome
                              ? Icons.arrow_downward
                              : Icons.arrow_upward,
                      color: color,
                      size: 20,
                    ),
                  ),
            title: Text(
              tx['description'] ?? category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$account • $date',
                  style: const TextStyle(fontSize: 12),
                ),
                if (balanceBefore != null)
                  ValueListenableBuilder<bool>(
                    valueListenable: BalanceVisibility.hidden,
                    builder: (_, hidden, _) => Text(
                      hidden
                          ? 'Saldo sblm: ••••••'
                          : 'Saldo sblm: ${txFmt.format(balanceBefore)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                      ),
                    ),
                  ),
              ],
            ),
            trailing: Text(
              '$sign${txFmt.format(amount)}',
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }
}
