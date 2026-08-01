import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../core/services/offline_credential_service.dart';
import '../core/services/session_service.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../routes/app_routes.dart';

/// The primary sidebar navigation, presented as a Drawer on mobile.
/// Mirrors the web sidebar: Dashboard, Creation (Party, Product),
/// Billing (Quotation, Estimation), Stock Adjustment.
class AppDrawer extends StatefulWidget {
  final String currentRoute;
  const AppDrawer({super.key, required this.currentRoute});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  bool _creationOpen = true;
  bool _billingOpen = true;
  bool _paymentOpen = true;
  String _versionLabel = '';

  @override
  void initState() {
    super.initState();
    _loadAppInfo();
  }

  Future<void> _loadAppInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _versionLabel = 'v${info.version} (${info.buildNumber})';
    });
  }

  void _go(String route) {
    Navigator.of(context).pop();
    if (widget.currentRoute == route) return;
    Get.toNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.midnightDeep,
      width: 280,
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _navTile(
                    icon: Icons.space_dashboard_rounded,
                    label: 'Dashboard',
                    route: AppRoutes.dashboard,
                  ),
                  const SizedBox(height: 4),
                  _sectionExpander(
                    icon: Icons.add_box_rounded,
                    label: 'Creation',
                    isOpen: _creationOpen,
                    onTap: () => setState(() => _creationOpen = !_creationOpen),
                    children: [
                      _subTile(
                        label: 'Party',
                        route: AppRoutes.partyList,
                      ),
                      // _subTile(
                      //   label: 'Product',
                      //   route: AppRoutes.productList,
                      // ),
                      _subTile(
                        label: 'Price Upload',
                        route: AppRoutes.priceUpload,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _sectionExpander(
                    icon: Icons.receipt_long_rounded,
                    label: 'Billing',
                    isOpen: _billingOpen,
                    onTap: () => setState(() => _billingOpen = !_billingOpen),
                    children: [
                      _subTile(
                        label: 'Quotation',
                        route: AppRoutes.quotationList,
                      ),
                      _subTile(
                        label: 'Estimation',
                        route: AppRoutes.estimationList,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _sectionExpander(
                    icon: Icons.currency_rupee_rounded,
                    label: 'Payment',
                    isOpen: _paymentOpen,
                    onTap: () => setState(() => _paymentOpen = !_paymentOpen),
                    children: [
                      _subTile(
                        label: 'Receipt',
                        route: AppRoutes.receiptList,
                      ),
                    ],
                  ),
                  // const SizedBox(height: 4),
                  // _navTile(
                  //   icon: Icons.tune_rounded,
                  //   label: 'Stock Adjustment',
                  //   route: AppRoutes.stockAdjustmentList,
                  // ),
                ],
              ),
            ),
            _buildFooter(),
            _buildVersion(),
          ],
        ),
      ),
    );
  }

  Widget _buildVersion() {
    if (_versionLabel.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Center(
        child: Text(
          _versionLabel,
          style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.surfaceElevated, AppColors.midnightDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: AppColors.goldGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppColors.gold.withOpacity(0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('NCW Fireworks', style: AppTextStyles.h3),
                const SizedBox(height: 2),
                Text('Retail Management', style: AppTextStyles.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final session = Get.find<SessionService>().currentSession;
    return Obx(() {
      final name = session.value?.displayName ?? 'Srisoftwarez';
      final phone = session.value?.displayPhone;
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.surfaceHigh,
              child: Icon(Icons.person,
                  color: AppColors.textSecondary, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: AppTextStyles.bodyStrong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(phone ?? 'Retail Admin', style: AppTextStyles.caption),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Logout',
              onPressed: () async {
                await Get.find<SessionService>().clearSession();
                // Clearing the offline credential is what actually
                // enforces "logout requires internet to log back in" —
                // without this, the salted password hash saved at last
                // online login would still let this user straight back
                // in offline.
                await Get.find<OfflineCredentialService>().clear();
                Get.offAllNamed(AppRoutes.login);
              },
              icon: Icon(Icons.logout_rounded,
                  color: AppColors.textMuted, size: 20),
            ),
          ],
        ),
      );
    });
  }

  Widget _navTile({
    required IconData icon,
    required String label,
    required String route,
  }) {
    final active = widget.currentRoute == route;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _go(route),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: active ? AppColors.surfaceElevated : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: active
                ? Border.all(color: AppColors.gold.withOpacity(0.4))
                : null,
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 20,
                  color: active ? AppColors.gold : AppColors.textSecondary),
              const SizedBox(width: 14),
              Text(
                label,
                style: AppTextStyles.bodyStrong.copyWith(
                  color: active ? AppColors.textPrimary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _subTile({required String label, required String route}) {
    final active = widget.currentRoute == route;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _go(route),
        child: Container(
          margin: const EdgeInsets.only(left: 30, top: 2, bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: active ? AppColors.surfaceElevated : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? AppColors.gold : AppColors.textMuted,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: AppTextStyles.body.copyWith(
                  color: active ? AppColors.textPrimary : AppColors.textSecondary,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionExpander({
    required IconData icon,
    required String label,
    required bool isOpen,
    required VoidCallback onTap,
    required List<Widget> children,
  }) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: AppColors.textSecondary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(label, style: AppTextStyles.bodyStrong),
                  ),
                  AnimatedRotation(
                    turns: isOpen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: Column(children: children),
          secondChild: const SizedBox(width: double.infinity),
          crossFadeState:
              isOpen ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }
}