import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AccountFormSheet extends StatefulWidget {
  final Map<String, dynamic>? account;
  const AccountFormSheet({super.key, this.account});

  @override
  State<AccountFormSheet> createState() => _AccountFormSheetState();
}

class _AccountFormSheetState extends State<AccountFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _balanceCtrl = TextEditingController();
  final _supabase = Supabase.instance.client;
  String _type = 'bank';
  String _currency = 'IDR';
  String _color = '#1976D2';
  bool _saving = false;

  static const _types = ['bank', 'ewallet', 'cash', 'investment'];
  static const _typeLabels = {
    'bank': 'Bank',
    'ewallet': 'E-Wallet',
    'cash': 'Tunai',
    'investment': 'Investasi',
  };
  static const _currencies = {
    'IDR': 'Rupiah (Rp)',
    'CNY': 'Yuan Tiongkok (¥)',
  };
  static const _currencyPrefix = {
    'IDR': 'Rp ',
    'CNY': '¥ ',
  };
  static const _colors = [
    '#1976D2', '#4CAF50', '#E91E63', '#FF9800', '#9C27B0',
    '#00BCD4', '#FF5722', '#607D8B', '#795548', '#F44336',
  ];

  bool get _isEdit => widget.account != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _nameCtrl.text = widget.account!['name'] ?? '';
      _type = widget.account!['type'] ?? 'bank';
      _currency = widget.account!['currency_code'] ?? 'IDR';
      _color = widget.account!['color'] ?? '#1976D2';
      _balanceCtrl.text =
          (widget.account!['initial_balance'] as num? ?? 0).toStringAsFixed(0);
    } else {
      _balanceCtrl.text = '0';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _balanceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await _supabase.from('accounts').update({
          'name': _nameCtrl.text.trim(),
          'type': _type,
          'color': _color,
        }).eq('id', widget.account!['id']);
      } else {
        final userId = await _supabase.rpc('get_current_user_id');
        final balance =
            double.tryParse(_balanceCtrl.text.replaceAll(',', '')) ?? 0;
        await _supabase.from('accounts').insert({
          'user_id': userId,
          'name': _nameCtrl.text.trim(),
          'type': _type,
          'initial_balance': balance,
          'currency_code': _currency,
          'color': _color,
          'is_active': true,
        });
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal menyimpan: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isEdit ? 'Edit Akun' : 'Tambah Akun',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nama Akun',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Nama wajib diisi' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: 'Tipe',
                border: OutlineInputBorder(),
              ),
              items: _types
                  .map((t) =>
                      DropdownMenuItem(value: t, child: Text(_typeLabels[t]!)))
                  .toList(),
              onChanged: (v) => setState(() => _type = v!),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _currency,
              decoration: const InputDecoration(
                labelText: 'Mata Uang',
                border: OutlineInputBorder(),
              ),
              items: _currencies.entries
                  .map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value),
                      ))
                  .toList(),
              onChanged: _isEdit
                  ? null
                  : (v) => setState(() => _currency = v!),
            ),
            if (!_isEdit) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _balanceCtrl,
                decoration: InputDecoration(
                  labelText: 'Saldo Awal',
                  border: const OutlineInputBorder(),
                  prefixText: _currencyPrefix[_currency],
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Saldo wajib diisi';
                  if (double.tryParse(
                        v.replaceAll('.', '').replaceAll(',', ''),
                      ) ==
                      null) {
                    return 'Angka tidak valid';
                  }
                  return null;
                },
              ),
            ],
            const SizedBox(height: 16),
            const Text('Warna', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _colors.map((c) {
                final selected = _color == c;
                final col = Color(int.parse(c.replaceFirst('#', '0xFF')));
                return GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: col,
                      shape: BoxShape.circle,
                      border: selected
                          ? Border.all(color: Colors.black54, width: 2)
                          : null,
                    ),
                    child: selected
                        ? const Icon(Icons.check, color: Colors.white, size: 16)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
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
                    : Text(_isEdit ? 'Simpan Perubahan' : 'Tambah Akun'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
