// 第二波 A3 — Geo 编辑器(GEOADD/GEODIST/删除)
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../theme/app_theme.dart';
import '../../../../providers/app_provider.dart';
import '../../../../models/redis_geo_member.dart';

class GeoEditor extends StatefulWidget {
  final String keyName;
  final String connectionId;
  final String databaseName;
  final AppProvider provider;
  final VoidCallback? onChanged;

  const GeoEditor({
    super.key,
    required this.keyName,
    required this.connectionId,
    required this.databaseName,
    required this.provider,
    this.onChanged,
  });

  @override
  State<GeoEditor> createState() => _GeoEditorState();
}

class _GeoRow {
  final String name;
  final double? lng;
  final double? lat;
  const _GeoRow(this.name, this.lng, this.lat);
}

class _GeoEditorState extends State<GeoEditor> {
  bool _isLoading = true;
  List<_GeoRow> _rows = [];
  String? _error;
  final TextEditingController _lngCtrl = TextEditingController();
  final TextEditingController _latCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  String? _distM1;
  String? _distM2;
  String _distUnit = 'm';
  String? _distResult;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _lngCtrl.dispose();
    _latCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final adapter = widget.provider.getRedisAdapter(widget.connectionId);
    if (adapter == null) {
      setState(() {
        _error = 'Redis adapter not available';
        _isLoading = false;
      });
      return;
    }
    try {
      final members = await adapter.getGeo(widget.keyName);
      final positions = await adapter.getGeoPositions(widget.keyName, members);
      if (!mounted) return;
      setState(() {
        _rows = members.map((n) {
          final pos = positions[n];
          return _GeoRow(
            n,
            pos != null && pos.isNotEmpty ? pos[0] : null,
            pos != null && pos.length >= 2 ? pos[1] : null,
          );
        }).toList();
        _distM1 = null;
        _distM2 = null;
        _distResult = null;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to load geo data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addMember() async {
    final lng = double.tryParse(_lngCtrl.text.trim());
    final lat = double.tryParse(_latCtrl.text.trim());
    final name = _nameCtrl.text.trim();
    if (lng == null || lat == null || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Valid longitude/latitude/name required'),
          backgroundColor: context.themeColors.accentOrange,
        ),
      );
      return;
    }
    final adapter = widget.provider.getRedisAdapter(widget.connectionId);
    if (adapter == null) return;
    setState(() => _adding = true);
    try {
      await adapter.geoAdd(widget.keyName, [
        GeoMember(lng: lng, lat: lat, name: name),
      ]);
      if (!mounted) return;
      _lngCtrl.clear();
      _latCtrl.clear();
      _nameCtrl.clear();
      widget.onChanged?.call();
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('GEOADD failed: $e'),
          backgroundColor: context.themeColors.accentRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _removeMember(String name) async {
    final adapter = widget.provider.getRedisAdapter(widget.connectionId);
    if (adapter == null) return;
    try {
      await adapter.geoRemove(widget.keyName, name);
      if (!mounted) return;
      widget.onChanged?.call();
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Remove failed: $e'),
          backgroundColor: context.themeColors.accentRed,
        ),
      );
    }
  }

  Future<void> _calcDist() async {
    if (_distM1 == null || _distM2 == null) return;
    final adapter = widget.provider.getRedisAdapter(widget.connectionId);
    if (adapter == null) return;
    try {
      final d = await adapter.geoDist(
        widget.keyName,
        _distM1!,
        _distM2!,
        unit: _distUnit,
      );
      if (!mounted) return;
      setState(() {
        _distResult = d?.toStringAsFixed(2);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('GEODIST failed: $e'),
          backgroundColor: context.themeColors.accentRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.circleAlert,
              size: 48,
              color: context.themeColors.accentRed,
            ),
            const SizedBox(height: AppDesignSystem.space3),
            Text(
              _error!,
              style: TextStyle(color: context.themeColors.textSecondary),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        _buildInfoBar(context),
        _buildAddForm(context),
        if (_rows.isNotEmpty) _buildDistTool(context),
        Expanded(
          child: _rows.isEmpty
              ? Center(
                  child: Text(
                    'No geo members',
                    style: TextStyle(color: context.themeColors.textMuted),
                  ),
                )
              : ListView.builder(
                  itemCount: _rows.length,
                  itemBuilder: (context, i) =>
                      _buildMemberRow(context, _rows[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildInfoBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.mapPin,
            size: 18,
            color: context.themeColors.accentRed,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Text(
            'Members: ${_rows.length}',
            style: TextStyle(
              color: context.themeColors.textSecondary,
              fontSize: AppDesignSystem.fontSizeSm,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, size: 18),
            tooltip: 'Reload',
            onPressed: _isLoading ? null : _loadData,
          ),
        ],
      ),
    );
  }

  Widget _buildAddForm(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _lngCtrl,
              decoration: const InputDecoration(
                labelText: 'Longitude',
                isDense: true,
              ),
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontFamily: 'monospace',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: TextField(
              controller: _latCtrl,
              decoration: const InputDecoration(
                labelText: 'Latitude',
                isDense: true,
              ),
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontFamily: 'monospace',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name',
                isDense: true,
              ),
              style: TextStyle(color: context.themeColors.textPrimary),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          ElevatedButton.icon(
            onPressed: _adding ? null : _addMember,
            icon: const Icon(LucideIcons.plus, size: 18),
            label: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Widget _buildDistTool(BuildContext context) {
    final names = _rows.map((r) => r.name).toList();
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _distM1,
              decoration: const InputDecoration(
                labelText: 'From',
                isDense: true,
              ),
              items: names
                  .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                  .toList(),
              onChanged: (v) => setState(() {
                _distM1 = v;
                _distResult = null;
              }),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _distM2,
              decoration: const InputDecoration(labelText: 'To', isDense: true),
              items: names
                  .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                  .toList(),
              onChanged: (v) => setState(() {
                _distM2 = v;
                _distResult = null;
              }),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          SizedBox(
            width: 90,
            child: DropdownButtonFormField<String>(
              initialValue: _distUnit,
              decoration: const InputDecoration(
                labelText: 'Unit',
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'm', child: Text('m')),
                DropdownMenuItem(value: 'km', child: Text('km')),
                DropdownMenuItem(value: 'mi', child: Text('mi')),
                DropdownMenuItem(value: 'ft', child: Text('ft')),
              ],
              onChanged: (v) => setState(() => _distUnit = v ?? 'm'),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          ElevatedButton.icon(
            onPressed: (_distM1 == null || _distM2 == null) ? null : _calcDist,
            icon: const Icon(LucideIcons.ruler, size: 18),
            label: const Text('Dist'),
          ),
          if (_distResult != null) ...[
            const SizedBox(width: AppDesignSystem.space2),
            Text(
              '$_distResult $_distUnit',
              style: TextStyle(
                color: context.themeColors.accentGreen,
                fontWeight: FontWeight.bold,
                fontFamily: AppDesignSystem.monoFontFamily,

                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMemberRow(BuildContext context, _GeoRow row) {
    final lng = row.lng?.toStringAsFixed(6) ?? '—';
    final lat = row.lat?.toStringAsFixed(6) ?? '—';
    return ListTile(
      leading: Icon(
        LucideIcons.mapPin,
        size: 20,
        color: context.themeColors.accentRed,
      ),
      title: Text(
        row.name,
        style: TextStyle(
          color: context.themeColors.textPrimary,
          fontSize: AppDesignSystem.fontSizeSm,
        ),
      ),
      subtitle: Text(
        '$lng, $lat',
        style: TextStyle(
          color: context.themeColors.textMuted,
          fontSize: AppDesignSystem.fontSizeXs,
          fontFamily: AppDesignSystem.monoFontFamily,

          fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
        ),
      ),
      trailing: IconButton(
        icon: const Icon(LucideIcons.trash2, size: 18),
        tooltip: 'Remove',
        onPressed: () => _removeMember(row.name),
      ),
    );
  }
}
