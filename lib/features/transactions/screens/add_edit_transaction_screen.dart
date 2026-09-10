import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddEditTransactionScreen extends StatefulWidget {
  final Map<String, dynamic>? transaction;
  const AddEditTransactionScreen({super.key, this.transaction});

  @override
  State<AddEditTransactionScreen> createState() =>
      _AddEditTransactionScreenState();
}

class _AddEditTransactionScreenState extends State<AddEditTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _supabase = Supabase.instance.client;

  String _type = 'expense';
  int? _accountId;
  int? _toAccountId;
  int? _categoryId;
  DateTime _date = DateTime.now();
  bool _saving = false;
  bool _loadingData = true;

  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> _categories = [];

  bool get _isEdit => widget.transaction != null;

  @override
  void initState() {
    super.initState();
    final tx = widget.transaction;
    if (tx != null) {
      _type = tx['type'] ?? 'expense';
      _amountCtrl.text = (tx['amount'] as num).toStringAsFixed(0);
      _descCtrl.text = tx['description'] ?? '';
      _accountId = tx['account_id'] as int?;
      _toAccountId = tx['to_account_id'] as int?;
      _categoryId = tx['category_id'] as int?;
      _date = DateTime.parse(tx['transaction_date']);
    }
    _loadData();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final accounts = await _supabase
          .from('accounts')
          .select('id, name, type, currency_code')
          .eq('is_active', true)
          .order('name');
      final categories = await _supabase
          .from('categories')
          .select('id, name, type')
          .eq('is_active', true)
          .not('user_id', 'is', null)
          .order('name');
      setState(() {
        _accounts = List<Map<String, dynamic>>.from(accounts);
        _categories = List<Map<String, dynamic>>.from(categories);
        if (_accountId == null && _accounts.isNotEmpty) {
          _accountId = _accounts.first['id'] as int;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat data: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingData = false);
    }
  }

  List<Map<String, dynamic>> get _filteredCategories =>
      _categories.where((c) => c['type'] == _type).toList();

  String get _selectedCurrency {
    if (_accountId == null) return 'IDR';
    final acc = _accounts.firstWhere(
      (a) => a['id'] == _accountId,
      orElse: () => {'currency_code': 'IDR'},
    );
    return (acc['currency_code'] as String?) ?? 'IDR';
  }

  String get _currencyPrefix => _selectedCurrency == 'CNY' ? '¥ ' : 'Rp ';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_accountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih akun terlebih dahulu')),
      );
      return;
    }
    if (_type == 'transfer' && _toAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih akun tujuan transfer')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final amount = double.parse(
        _amountCtrl.text.replaceAll(',', ''),
      );
      final userId = await _supabase.rpc('get_current_user_id');
      final data = {
        'user_id': userId,
        'type': _type,
        'amount': amount,
        'account_id': _accountId,
        'category_id': _type != 'transfer' ? _categoryId : null,
        'to_account_id': _type == 'transfer' ? _toAccountId : null,
        'description': _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        'transaction_date': _date.toIso8601String().split('T')[0],
      };

      if (_isEdit) {
        // Delete old → trigger reverses balance; insert new → trigger applies new balance
        await _supabase
            .from('transactions')
            .delete()
            .eq('id', widget.transaction!['id']);
      }
      await _supabase.from('transactions').insert(data);

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Transaksi' : 'Tambah Transaksi'),
        actions: [
          TextButton(
            onPressed: _saving || _loadingData ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Simpan'),
          ),
        ],
      ),
      body: _loadingData
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'expense', label: Text('Keluar')),
                      ButtonSegment(value: 'income', label: Text('Masuk')),
                      ButtonSegment(value: 'transfer', label: Text('Transfer')),
                    ],
                    selected: {_type},
                    onSelectionChanged: (v) => setState(() {
                      _type = v.first;
                      _categoryId = null;
                      _toAccountId = null;
                    }),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _amountCtrl,
                    decoration: InputDecoration(
                      labelText: 'Jumlah',
                      border: const OutlineInputBorder(),
                      prefixText: _currencyPrefix,
                    ),
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    autofocus: !_isEdit,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Jumlah wajib diisi';
                      }
                      final n = double.tryParse(v.replaceAll(',', ''));
                      if (n == null || n <= 0) {
                        return 'Jumlah harus lebih dari 0';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _AccountDropdown(
                    label: 'Akun',
                    accounts: _accounts,
                    value: _accountId,
                    onChanged: (v) => setState(() => _accountId = v),
                  ),
                  if (_type == 'transfer') ...[
                    const SizedBox(height: 16),
                    _AccountDropdown(
                      label: 'Akun Tujuan',
                      accounts: _accounts
                          .where((a) => a['id'] != _accountId)
                          .toList(),
                      value: _toAccountId,
                      onChanged: (v) => setState(() => _toAccountId = v),
                      required: true,
                    ),
                  ],
                  if (_type != 'transfer') ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      initialValue: _filteredCategories.any(
                        (c) => c['id'] == _categoryId,
                      )
                          ? _categoryId
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Kategori',
                        border: OutlineInputBorder(),
                      ),
                      items: _filteredCategories
                          .map(
                            (c) => DropdownMenuItem<int>(
                              value: c['id'] as int,
                              child: Text(c['name'] as String),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _categoryId = v),
                      validator: (v) =>
                          v == null ? 'Pilih kategori' : null,
                    ),
                  ],
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    title: const Text('Tanggal'),
                    subtitle: Text(
                      DateFormat('d MMMM yyyy', 'id_ID').format(_date),
                    ),
                    trailing: const Icon(Icons.calendar_today, size: 20),
                    shape: RoundedRectangleBorder(
                      side: BorderSide(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    onTap: _pickDate,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Keterangan (opsional)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(_isEdit ? 'Simpan Perubahan' : 'Tambah Transaksi'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _AccountDropdown extends StatelessWidget {
  final String label;
  final List<Map<String, dynamic>> accounts;
  final int? value;
  final ValueChanged<int?> onChanged;
  final bool required;

  const _AccountDropdown({
    required this.label,
    required this.accounts,
    required this.value,
    required this.onChanged,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      initialValue: accounts.any((a) => a['id'] == value) ? value : null,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: accounts
          .map(
            (a) => DropdownMenuItem<int>(
              value: a['id'] as int,
              child: Text(a['name'] as String),
            ),
          )
          .toList(),
      onChanged: onChanged,
      validator: required ? (v) => v == null ? 'Pilih $label' : null : null,
    );
  }
}
