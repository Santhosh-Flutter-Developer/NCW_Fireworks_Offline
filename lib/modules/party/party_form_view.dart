import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/models/party_model.dart';
import '../../widgets/common_widgets.dart';
import 'party_controller.dart';

class PartyFormView extends GetView<PartyController> {
  const PartyFormView({super.key});

  @override
  Widget build(BuildContext context) {
    final isEditing = controller.editingParty != null;
    return Scaffold(
      backgroundColor: AppColors.midnight,
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Party' : 'Add Party'),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
            children: [
              const SectionLabel(text: 'Agent'),
              Obx(() => _dropdownField(
                    value: controller.formAgent.value,
                    hint: 'Select',
                    options: controller.agentOptions,
                    onChanged: (v) => controller.formAgent.value = v,
                  )),
              const SizedBox(height: 18),
              const SectionLabel(text: 'Party Details'),
              _field(
                'Party Name *',
                controller.nameCtrl,
                hint: 'e.g. Sri Lakshmi Traders',
                helper: 'Contains Text, Symbols &.,. Max Char: 60',
                maxLength: 60,
              ),
              _field(
                'Phone Number',
                controller.phoneCtrl,
                hint: '10-digit mobile number',
                helper: 'Numbers Only (only 10 digits)',
                keyboardType: TextInputType.phone,
                maxLength: 10,
              ),
              _field(
                'Email',
                controller.emailCtrl,
                hint: 'name@example.com',
                helper: 'Max Char: 50',
                keyboardType: TextInputType.emailAddress,
                maxLength: 50,
              ),
              _field(
                'Address',
                controller.addressCtrl,
                hint: 'Street, area',
                helper:
                    'Contains Text, Numbers, Symbols (Except <>?{}!*^%\$). Max character: 150',
                maxLines: 3,
                maxLength: 150,
              ),
              const SizedBox(height: 8),
              const SectionLabel(text: 'Location'),
              Text('State *', style: AppTextStyles.caption),
              const SizedBox(height: 8),
              Obx(() => _dropdownField(
                    value: controller.formState.value,
                    hint: 'Select',
                    options: controller.stateOptions,
                    onChanged: (v) {
                      if (v != null) controller.formState.value = v;
                      controller.formDistrict.value = null;
                      controller.formCity.value = null;
                    },
                  )),
              const SizedBox(height: 16),
              Text('District', style: AppTextStyles.caption),
              const SizedBox(height: 8),
              Obx(() => _dropdownField(
                    value: controller.formDistrict.value,
                    hint: 'Select',
                    options:
                        controller.districtOptions(controller.formState.value),
                    onChanged: (v) {
                      controller.formDistrict.value = v;
                      controller.formCity.value = null;
                    },
                  )),
              const SizedBox(height: 16),
              Text('City', style: AppTextStyles.caption),
              const SizedBox(height: 8),
              Obx(() => _dropdownField(
                    value: controller.formCity.value,
                    hint: 'Select',
                    options: controller.formDistrict.value == null
                        ? []
                        : controller
                            .cityOptions(controller.formDistrict.value!),
                    onChanged: (v) => controller.formCity.value = v,
                  )),
              const SizedBox(height: 16),
              _field(
                'Pincode',
                controller.pincodeCtrl,
                hint: '6-digit pincode',
                helper: 'Numbers only (only 6 digits)',
                keyboardType: TextInputType.number,
                maxLength: 6,
              ),
              const SizedBox(height: 8),
              const SectionLabel(text: 'Identification'),
              _field(
                'Identification',
                controller.identificationCtrl,
                hint: 'ID / license number',
                helper:
                    'Contains Text, Numbers, Symbols (Except <>?{}!*^%\$). Max character: 50',
                maxLength: 50,
              ),
              _field(
                'GST',
                controller.gstinCtrl,
                hint: '29GGGGG1314R9Z6',
                helper: 'Format: 29GGGGG1314R9Z6',
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 8),
              const SectionLabel(text: 'Opening Balance'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: _field(
                      'Amount',
                      controller.openingBalanceCtrl,
                      hint: '0.00',
                      helper: 'Upto Rs.50 Lakhs',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 23),
                      child: Obx(() => _balanceTypeDropdown()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => controller.save(asDraft: true),
                  child: const Text('Draft'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => controller.save(),
                  child: Text(isEditing ? 'Update' : 'Submit'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    String? hint,
    String? helper,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    int maxLines = 1,
    int? maxLength,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.caption),
          const SizedBox(height: 8),
          TextField(
            controller: ctrl,
            maxLines: maxLines,
            keyboardType: keyboardType,
            textCapitalization: textCapitalization,
            maxLength: maxLength,
            style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: hint,
              counterText: '',
            ),
          ),
          if (helper != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 2),
              child: Text(
                helper,
                style: AppTextStyles.caption.copyWith(fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dropdownField({
    required String? value,
    required String hint,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          hint: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(hint,
                style: AppTextStyles.body.copyWith(color: AppColors.textMuted)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          dropdownColor: AppColors.surfaceElevated,
          icon: Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.textMuted),
          style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
          items: options
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: options.isEmpty ? null : onChanged,
        ),
      ),
    );
  }

  Widget _balanceTypeDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<BalanceType>(
          value: controller.formBalanceType.value,
          isExpanded: true,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          dropdownColor: AppColors.surfaceElevated,
          icon: Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.textMuted),
          style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
          items: BalanceType.values
              .map((b) => DropdownMenuItem(value: b, child: Text(b.label)))
              .toList(),
          onChanged: (v) {
            if (v != null) controller.formBalanceType.value = v;
          },
        ),
      ),
    );
  }
}
