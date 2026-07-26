import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/services/data_sync_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/responsive.dart';
import '../../data/models/party_model.dart';
import '../../routes/app_routes.dart';
import '../../widgets/app_data_table.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/sync_action_button.dart';
import '../../widgets/view_mode_toggle.dart';
import 'party_controller.dart';

class PartyListView extends GetView<PartyController> {
  const PartyListView({super.key});

  @override
  Widget build(BuildContext context) {
    return _PartyListFreshVisit(
      controller: controller,
      child: AppScaffold(
        routeName: AppRoutes.partyList,
        title: 'Party',
        actions: [
          SyncActionButton(
            // syncAllData() runs the full global sync (Party → Price
            // Upload → Quotation → Estimation → Receipt), not just this
            // screen's own data — see DataSyncService.syncAllData. It
            // only pushes/pulls the cache though, so without reloading
            // here the "Pending sync" badges on this screen would just
            // sit there until something else (search, pagination,
            // re-entering the page) happened to call loadParties() next.
            onSync: () async {
              await Get.find<DataSyncService>().syncAllData();
              await controller.loadParties();
            },
          ),
        ],
        body: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: Responsive.horizontalPadding(context),
            vertical: 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
             
              SearchField(
                hint: 'Search by party name',
                onChanged: controller.setSearch,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  // _actionIcon(
                  //   icon: Icons.cloud_upload_rounded,
                  //   color: AppColors.success,
                  //   tooltip: 'Export',
                  //   onTap: () => _showComingSoon(context, 'Export'),
                  // ),
                  // const SizedBox(width: 5),
                  // _actionIcon(
                  //   icon: Icons.print_rounded,
                  //   color: AppColors.skyBlue,
                  //   tooltip: 'Print',
                  //   onTap: () => _showComingSoon(context, 'Print'),
                  // ),
                  // const SizedBox(width: 5),
                  // _actionIcon(
                  //   icon: Icons.download_rounded,
                  //   color: AppColors.skyBlue,
                  //   tooltip: 'Download',
                  //   onTap: () => _showComingSoon(context, 'Download'),
                  // ),
                  // const SizedBox(width: 5),
                  Obx(
                    () => ViewModeToggle(
                      isTableView: controller.isTableView.value,
                      onChanged: controller.toggleViewMode,
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () {
                      controller.startCreate();
                      Get.toNamed(AppRoutes.partyForm);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.ember,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    icon: const Icon(Icons.add_circle_rounded, size: 18),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Obx(() {
                  if (controller.isLoadingList.value &&
                      controller.paginated.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final list = controller.paginated;
                  if (list.isEmpty) {
                    return const EmptyState(
                      icon: Icons.groups_rounded,
                      title: 'No parties found',
                      subtitle: 'Try a different search or add a new party.',
                    );
                  }
                  final startIndex =
                      (controller.pageNo.value - 1) * controller.pageLimit.value;
                  if (controller.isTableView.value) {
                    return SingleChildScrollView(
                      child: AppDataTable(
                        columns: const [
                          'S.No',
                          'Party Name',
                          'State',
                          'Action',
                        ],
                        rows: List.generate(list.length, (i) {
                          final party = list[i];
                          return [
                            Text('${startIndex + i + 1}',
                                style: AppTextStyles.body),
                            
                            SizedBox(
                              width: 200,
                              child: Text(party.name,
                                  style: AppTextStyles.bodyStrong,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            Text(party.state, style: AppTextStyles.body),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Edit',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => controller.startEdit(party),
                                  icon: Icon(Icons.edit_rounded,
                                      color: AppColors.teal, size: 18),
                                ),
                                
                              ],
                            ),
                          ];
                        }),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final party = list[index];
                      return _PartyTile(
                        serial: startIndex + index + 1,
                        party: party,
                        onTap: () => controller.startEdit(party),
                        onDelete: () => controller.deleteParty(party),
                      );
                    },
                  );
                }),
              ),
              const SizedBox(height: 8),
              Obx(() => _paginationBar(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionIcon({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Icon(icon, color: color, size: 19),
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context, String feature) {
    Get.snackbar(
      feature,
      '$feature will be available once the backend is connected.',
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  Widget _paginationBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Text('Page Limit', style: AppTextStyles.caption),
          const SizedBox(width: 8),
          _pageLimitDropdown(context),
          const Spacer(),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: controller.pageNo.value > 1
                ? () => controller.setPageNo(controller.pageNo.value - 1)
                : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Text(
            '${controller.pageNo.value} / ${controller.totalPages}',
            style: AppTextStyles.bodyStrong,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: controller.pageNo.value < controller.totalPages
                ? () => controller.setPageNo(controller.pageNo.value + 1)
                : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }

  Widget _pageLimitDropdown(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        Get.bottomSheet(
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: PartyController.pageLimitOptions
                  .map(
                    (limit) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('$limit per page'),
                      onTap: () {
                        controller.setPageLimit(limit);
                        Get.back();
                      },
                    ),
                  )
                  .toList(),
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${controller.pageLimit.value}',
                style: AppTextStyles.bodyStrong),
            const Icon(Icons.arrow_drop_down_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}

/// Forces a reset to defaults (empty search, page limit 10, page 1, plus
/// a reload) exactly once every time the Party list screen is freshly
/// navigated to — see the comment in `PartyListView.build` for why this
/// can't just live in `PartyController.onInit()` alone. Being a
/// `StatefulWidget`, Flutter builds a brand-new `State` for it on every
/// fresh route push regardless of whether GetX handed back a reused
/// controller instance or a new one.
class _PartyListFreshVisit extends StatefulWidget {
  final PartyController controller;
  final Widget child;
  const _PartyListFreshVisit({
    required this.controller,
    required this.child,
  });

  @override
  State<_PartyListFreshVisit> createState() => _PartyListFreshVisitState();
}

class _PartyListFreshVisitState extends State<_PartyListFreshVisit> {
  @override
  void initState() {
    super.initState();
    // resetForFreshVisit() mutates Rx values (searchQuery, pageNo,
    // pageLimit, isLoadingList...), which makes every Obx watching them
    // ask to rebuild. Calling that synchronously here — inside
    // initState(), which itself runs as part of mounting this very
    // widget tree — asks Flutter to rebuild a widget while its own
    // ancestors (PartyListView) are still mid-build, which throws
    // "setState() or markNeedsBuild() called during build". Deferring
    // to right after this frame finishes avoids that entirely.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.resetForFreshVisit();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _PartyTile extends StatelessWidget {
  final int serial;
  final PartyModel party;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _PartyTile({
    required this.serial,
    required this.party,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: AppColors.skyGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$serial',
                  style: AppTextStyles.bodyStrong.copyWith(color: Colors.white),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            party.name,
                            style: AppTextStyles.bodyStrong,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (party.isDraft)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.gold.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Draft',
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.gold,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        if (party.isPending)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.skyBlue.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Pending sync',
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.skyBlue,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      party.state,
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}