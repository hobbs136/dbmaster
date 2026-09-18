import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../services/ai/ai_client.dart';
import '../../models/ai_models.dart';
import '../connection/error_boundary.dart';
import '../../theme/app_colors.dart';

class AiSettingsDialog extends StatefulWidget {
  final List<Map<String, dynamic>> providers;
  final String selectedProvider;

  const AiSettingsDialog({
    super.key,
    required this.providers,
    required this.selectedProvider,
  });

  @override
  State<AiSettingsDialog> createState() => AiSettingsDialogState();
}

class AiSettingsDialogState extends State<AiSettingsDialog> {
  final Map<String, TextEditingController> _apiKeyControllers = {};
  final Map<String, TextEditingController> _baseUrlControllers = {};
  final TextEditingController _customModelInputController =
      TextEditingController();
  String? _selectedProvider;
  String? _selectedModel;
  final Map<String, List<String>> _fetchedModels = {};
  bool _isLoadingModels = false;
  String? _modelsError;
  final AiClient _aiClient = AiClient();

  @override
  void initState() {
    super.initState();
    final provider = context.read<AppProvider>();
    _selectedProvider = provider.selectedAiProvider;
    _selectedModel = provider.selectedAiModel;

    for (final p in widget.providers) {
      final name = p['name'] as String;
      _apiKeyControllers[name] = TextEditingController(
        text: provider.getAiApiKey(name) ?? '',
      );
      _baseUrlControllers[name] = TextEditingController(
        text: provider.getAiBaseUrl(name) ?? '',
      );
    }

    if (_selectedProvider == AiApiProviders.customModelKey) {
      final savedModel = provider.selectedAiModel;
      if (savedModel.isNotEmpty && savedModel != 'custom-model') {
        _fetchedModels[AiApiProviders.customModelKey] = [savedModel];
        _selectedModel = savedModel;
      }
    }

    // 加载持久化的模型列表
    final persistedLists = provider.fetchedModelLists;
    if (persistedLists.isNotEmpty) {
      _fetchedModels.addAll(persistedLists);
    }
  }

  @override
  void dispose() {
    for (final controller in _apiKeyControllers.values) {
      controller.dispose();
    }
    for (final controller in _baseUrlControllers.values) {
      controller.dispose();
    }
    _customModelInputController.dispose();
    _aiClient.dispose();
    super.dispose();
  }

  List<String> _getModelsForProvider(String providerName) {
    final fetched = _fetchedModels[providerName];
    if (fetched != null && fetched.isNotEmpty) {
      return fetched;
    }
    try {
      final provider = widget.providers.firstWhere(
        (p) => p['name'] == providerName,
      );
      return (provider['models'] as List<dynamic>?)?.cast<String>() ?? [];
    } catch (e) {
      return [];
    }
  }

  String? _getBaseUrlForProvider(String providerName) {
    final userUrl = _baseUrlControllers[providerName]?.text.trim();
    if (userUrl != null && userUrl.isNotEmpty) {
      return userUrl;
    }
    return AiApiProviders.getByName(providerName)?.defaultBaseUrl;
  }

  Future<void> _fetchModelsForProvider(String providerName) async {
    final apiKey = _apiKeyControllers[providerName]?.text.trim() ?? '';
    final baseUrl = _getBaseUrlForProvider(providerName);

    final l10n = AppLocalizations.of(context)!;
    if (apiKey.isEmpty) {
      setState(() {
        _modelsError = l10n.errorApiKeyRequired;
      });
      return;
    }

    if (baseUrl == null || baseUrl.isEmpty) {
      setState(() {
        _modelsError = l10n.errorBaseUrlRequired;
      });
      return;
    }

    setState(() {
      _isLoadingModels = true;
      _modelsError = null;
    });

    try {
      final models = await _aiClient.fetchModels(
        baseUrl: baseUrl,
        apiKey: apiKey,
      );

      setState(() {
        _fetchedModels[providerName] = models;
        _isLoadingModels = false;
        if (models.isNotEmpty &&
            !_fetchedModels[providerName]!.contains(_selectedModel)) {
          _selectedModel = models.first;
        }
      });
    } catch (e) {
      setState(() {
        _isLoadingModels = false;
        _modelsError = l10n.errorFetchModelsFailed(e.toString());
      });
    }
  }

  void _addCustomModel() {
    final modelName = _customModelInputController.text.trim();
    if (modelName.isEmpty) return;

    final providerName = AiApiProviders.customModelKey;
    if (!_fetchedModels.containsKey(providerName)) {
      _fetchedModels[providerName] = [];
    }

    if (!_fetchedModels[providerName]!.contains(modelName)) {
      setState(() {
        _fetchedModels[providerName]!.add(modelName);
        _selectedModel = modelName;
      });
    } else {
      setState(() {
        _selectedModel = modelName;
      });
    }
    _customModelInputController.clear();
  }

  void _removeCustomModel(String modelName) {
    final providerName = AiApiProviders.customModelKey;
    if (!_fetchedModels.containsKey(providerName)) return;

    setState(() {
      _fetchedModels[providerName]!.remove(modelName);
      if (_fetchedModels[providerName]!.isEmpty) {
        _fetchedModels.remove(providerName);
      }
      if (_selectedModel == modelName) {
        final remaining = _getModelsForProvider(providerName);
        _selectedModel = remaining.isNotEmpty ? remaining.first : null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currentProvider = _selectedProvider ?? widget.providers.first['name'];
    final models = _getModelsForProvider(currentProvider);
    final isCustomProvider = _selectedProvider == AiApiProviders.customModelKey;

    return AlertDialog(
      backgroundColor: context.themeColors.bgSecondary,
      title: Row(
        children: [
          Icon(
            LucideIcons.keyRound,
            color: context.themeColors.accentPurple,
            size: 20,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Text(
            l10n.aiPanelApiSettings,
            style: TextStyle(color: context.themeColors.textPrimary),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 580,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppDesignSystem.space3),
              decoration: BoxDecoration(
                color: context.themeColors.accentPurple.withOpacity(0.08),
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
                border: Border.all(
                  color: context.themeColors.accentPurple.withOpacity(0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        LucideIcons.info,
                        size: 16,
                        color: context.themeColors.accentPurple,
                      ),
                      const SizedBox(width: AppDesignSystem.space2),
                      Text(
                        l10n.aiSettingsDisclosureTitle,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.themeColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppDesignSystem.space2),
                  Text(
                    l10n.aiSettingsDisclosureBody,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.themeColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDesignSystem.space3),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.aiPanelSelectProvider,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.themeColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppDesignSystem.space2),
                  Expanded(
                    child: ListView.builder(
                      itemCount: widget.providers.length,
                      itemBuilder: (context, index) {
                        final provider = widget.providers[index];
                        final name = provider['name'] as String;
                        final icon = provider['icon'] as IconData;
                        final isSelected = _selectedProvider == name;

                        final displayName =
                            name == AiApiProviders.customModelKey
                            ? l10n.aiPanelCustomModel
                            : name;
                        return CheckboxListTile(
                          title: Row(
                            children: [
                              // emoji Text→Icon 组件+品牌色（F-37）
                              Icon(
                                icon,
                                size: 16,
                                color: provider['color'] as Color,
                              ),
                              const SizedBox(width: AppDesignSystem.space2),
                              Text(
                                displayName,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: context.themeColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          value: isSelected,
                          onChanged: (value) {
                            if (value == true) {
                              setState(() {
                                _selectedProvider = name;
                                _modelsError = null;
                                final newModels = _getModelsForProvider(name);
                                if (newModels.isNotEmpty) {
                                  _selectedModel = newModels.first;
                                } else {
                                  _selectedModel = null;
                                }
                              });
                            }
                          },
                          activeColor: context.themeColors.accentPurple,
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              flex: isCustomProvider ? 3 : 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        l10n.aiPanelSelectModelCurrent(_selectedProvider ?? ''),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.themeColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _isLoadingModels
                            ? null
                            : () => _fetchModelsForProvider(currentProvider),
                        icon: _isLoadingModels
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(LucideIcons.refreshCw, size: 18),
                        tooltip: l10n.tooltipRefreshModels,
                        color: context.themeColors.accentPurple,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppDesignSystem.space1),
                  if (isCustomProvider) ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _customModelInputController,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.themeColors.textPrimary,
                            ),
                            decoration: InputDecoration(
                              labelText: l10n.labelCustomModelInput,
                              labelStyle: TextStyle(
                                fontSize: 11,
                                color: context.themeColors.textMuted,
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: AppDesignSystem.space2,
                                vertical: AppDesignSystem.space2_5,
                              ),
                            ),
                            onSubmitted: (_) => _addCustomModel(),
                          ),
                        ),
                        const SizedBox(width: AppDesignSystem.space2),
                        IconButton(
                          onPressed: _addCustomModel,
                          icon: const Icon(LucideIcons.plus, size: 18),
                          tooltip: l10n.tooltipAddModel,
                          color: context.themeColors.accentPurple,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppDesignSystem.space2),
                  ],
                  if (_modelsError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        _modelsError!,
                        style: const TextStyle(fontSize: 11, color: Colors.red),
                      ),
                    ),
                  Expanded(
                    child: models.isEmpty
                        ? Center(
                            child: Text(
                              isCustomProvider
                                  ? l10n.hintFetchOrInputModel
                                  : l10n.hintFetchModels,
                              style: TextStyle(
                                fontSize: 12,
                                color: context.themeColors.textMuted,
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: models.length,
                            itemBuilder: (context, index) {
                              final model = models[index];

                              return RadioListTile<String>(
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        model,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color:
                                              context.themeColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                    if (isCustomProvider &&
                                        model != 'custom-model')
                                      IconButton(
                                        icon: const Icon(
                                          LucideIcons.trash2,
                                          size: 16,
                                        ),
                                        color: Colors.redAccent,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 32,
                                          minHeight: 32,
                                        ),
                                        tooltip: AppLocalizations.of(
                                          context,
                                        )!.commonDelete,
                                        onPressed: () =>
                                            _removeCustomModel(model),
                                      ),
                                  ],
                                ),
                                value: model,
                                groupValue: _selectedModel,
                                onChanged: (value) {
                                  setState(() {
                                    _selectedModel = value;
                                  });
                                },
                                activeColor: context.themeColors.accentPurple,
                                dense: true,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.aiPanelApiConfigCurrent(_selectedProvider ?? ''),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.themeColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppDesignSystem.space2),
                  Expanded(
                    child: ListView.builder(
                      itemCount: widget.providers.length,
                      itemBuilder: (context, index) {
                        final provider = widget.providers[index];
                        final name = provider['name'] as String;

                        final expansionDisplayName =
                            name == AiApiProviders.customModelKey
                            ? l10n.aiPanelCustomModel
                            : name;
                        return ExpansionTile(
                          // emoji Text→Icon 组件+品牌色（F-37）
                          leading: Icon(
                            provider['icon'] as IconData,
                            size: 16,
                            color: provider['color'] as Color,
                          ),
                          title: Text(
                            expansionDisplayName,
                            style: TextStyle(
                              fontSize: 13,
                              color: context.themeColors.textPrimary,
                            ),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppDesignSystem.space4,
                                vertical: AppDesignSystem.space2,
                              ),
                              child: Column(
                                children: [
                                  TextField(
                                    controller: _apiKeyControllers[name],
                                    obscureText: true,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: context.themeColors.textPrimary,
                                    ),
                                    decoration: InputDecoration(
                                      labelText: l10n.aiPanelApiKey,
                                      labelStyle: TextStyle(
                                        fontSize: 11,
                                        color: context.themeColors.textMuted,
                                      ),
                                      hintText: l10n.aiPanelEnterApiKey,
                                      hintStyle: TextStyle(
                                        fontSize: 11,
                                        color: context.themeColors.textMuted,
                                      ),
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: AppDesignSystem.space2,
                                        vertical: AppDesignSystem.space2_5,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(
                                    height: AppDesignSystem.space2,
                                  ),
                                  TextField(
                                    controller: _baseUrlControllers[name],
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: context.themeColors.textPrimary,
                                    ),
                                    decoration: InputDecoration(
                                      labelText: l10n.aiPanelApiBaseUrl,
                                      labelStyle: TextStyle(
                                        fontSize: 11,
                                        color: context.themeColors.textMuted,
                                      ),
                                      hintText: l10n.aiPanelCustomApiUrl,
                                      hintStyle: TextStyle(
                                        fontSize: 11,
                                        color: context.themeColors.textMuted,
                                      ),
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: AppDesignSystem.space2,
                                        vertical: AppDesignSystem.space2_5,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(
                                    height: AppDesignSystem.space2,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text(l10n.commonCancel),
        ),
        ElevatedButton(
          onPressed: () async {
            try {
              final appProvider = context.read<AppProvider>();

              final effectiveProvider =
                  _selectedProvider ?? appProvider.selectedAiProvider;
              final effectiveModel =
                  _selectedModel ?? appProvider.selectedAiModel;

              if (effectiveModel.isEmpty) {
                AppErrorHandler.showErrorSnackBar(
                  context,
                  l10n.errorSelectModelRequired,
                );
                return;
              }

              final apiConfigs = <String, Map<String, String>>{};
              for (final p in widget.providers) {
                final name = p['name'] as String;
                final apiKey = _apiKeyControllers[name]?.text.trim() ?? '';
                final baseUrl = _baseUrlControllers[name]?.text.trim() ?? '';

                apiConfigs[name] = {'apiKey': apiKey, 'baseUrl': baseUrl};
              }

              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              final successColor = context.themeColors.success;

              await appProvider.saveAiConfig(
                effectiveProvider,
                effectiveModel,
                apiConfigs,
              );

              // 持久化模型列表
              if (_fetchedModels.isNotEmpty) {
                appProvider.saveFetchedModelLists(_fetchedModels);
              }

              if (mounted) {
                navigator.pop(_fetchedModels);
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(l10n.apiSettingsSavedMsg),
                    backgroundColor: successColor,
                  ),
                );
              }
            } catch (e) {
              if (mounted) {
                AppErrorHandler.showErrorSnackBar(
                  context,
                  l10n.errorSaveFailed(e.toString()),
                );
              }
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: context.themeColors.accentBlue,
          ),
          child: Text(l10n.aiPanelSave),
        ),
      ],
    );
  }
}
