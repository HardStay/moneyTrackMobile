import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/category_form_sheet.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _income = [];
  List<Map<String, dynamic>> _expense = [];
  bool _loading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _supabase
          .from('categories')
          .select()
          .eq('is_active', true)
          .not('user_id', 'is', null)
          .order('name');
      final all = List<Map<String, dynamic>>.from(res);
      setState(() {
        _income = all.where((c) => c['type'] == 'income').toList();
        _expense = all.where((c) => c['type'] == 'expense').toList();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openAddForm() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const CategoryFormSheet(),
    );
    if (result == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> cat) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Kategori'),
        content: Text('Hapus kategori "${cat['name']}"?'),
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
      await _supabase.from('categories').delete().eq('id', cat['id']);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kategori'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Pemasukan'), Tab(text: 'Pengeluaran')],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddForm,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _CategoryList(
                  categories: _income,
                  color: const Color(0xFF4CAF50),
                  onDelete: _delete,
                ),
                _CategoryList(
                  categories: _expense,
                  color: const Color(0xFFE53935),
                  onDelete: _delete,
                ),
              ],
            ),
    );
  }
}

class _CategoryList extends StatelessWidget {
  final List<Map<String, dynamic>> categories;
  final Color color;
  final Future<void> Function(Map<String, dynamic>) onDelete;

  const _CategoryList({
    required this.categories,
    required this.color,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return const Center(
        child: Text(
          'Belum ada kategori\nTap + untuk menambah',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final cat = categories[index];
        final catColor = cat['color'] != null
            ? Color(int.parse(cat['color'].replaceFirst('#', '0xFF')))
            : color;
        return Dismissible(
          key: Key('cat_${cat['id']}'),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) async {
            await onDelete(cat);
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
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: catColor.withValues(alpha: 0.15),
                child: Icon(Icons.label_outline, color: catColor, size: 20),
              ),
              title: Text(cat['name']),
            ),
          ),
        );
      },
    );
  }
}
