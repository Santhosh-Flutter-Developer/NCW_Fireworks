import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:get/get.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/responsive.dart';
import '../../routes/app_routes.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/stat_card.dart';
import 'dashboard_controller.dart';

class DashboardView extends GetView<DashboardController> {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      routeName: AppRoutes.dashboard,
      title: 'Dashboard',
      body: Center(
  child: Padding(
    padding: const EdgeInsets.all(24.0),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Image.asset(
        'assets/images/ic_logo.png',
        fit: BoxFit.contain,
      ),
    ),
  ),
),
      /*body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: Responsive.horizontalPadding(context),
              vertical: 20,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: Responsive.maxContentWidth(context),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildGreeting(),
                    const SizedBox(height: 20),
                    _buildStatsGrid(context),
                    const SizedBox(height: 24),
                    _buildTrendChart(context),
                    const SizedBox(height: 24),
                    _buildStockOverview(context),
                    const SizedBox(height: 24),
                    _buildRecentActivity(context),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          );
        },
      ),*/
    );
  }

  Widget _buildGreeting() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Welcome back 👋', style: AppTextStyles.h1),
              const SizedBox(height: 4),
              Text(
                'Here\'s what\'s happening with your store today.',
                style: AppTextStyles.body,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsGrid(BuildContext context) {
    final cols = Responsive.gridColumns(context);
    final stats = [
      StatCard(
        label: 'Total Parties',
        value: '${controller.totalParties}',
        icon: Icons.groups_rounded,
        gradient: AppColors.skyGradient,
        onTap: () => Get.toNamed(AppRoutes.partyList),
      ),
      StatCard(
        label: 'Total Products',
        value: '${controller.totalProducts}',
        icon: Icons.inventory_2_rounded,
        gradient: AppColors.magentaGradient,
        onTap: () => Get.toNamed(AppRoutes.productList),
      ),
      StatCard(
        label: 'Quotation Value',
        value: '₹${controller.quotationsValue.toStringAsFixed(0)}',
        icon: Icons.request_quote_rounded,
        gradient: AppColors.goldGradient,
        trend: '+8%',
        onTap: () => Get.toNamed(AppRoutes.quotationList),
      ),
      StatCard(
        label: 'Low Stock Items',
        value: '${controller.lowStockCount}',
        icon: Icons.warning_amber_rounded,
        gradient: AppColors.emberGradient,
        trend: controller.lowStockCount > 0 ? 'Attention' : 'Good',
        trendUp: false,
        onTap: () => Get.toNamed(AppRoutes.stockAdjustmentList),
      ),
    ];

    return GridView.count(
      crossAxisCount: cols,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      childAspectRatio: cols == 2 ? 1.1 : 1.2,
      children: stats,
    );
  }

  Widget _buildTrendChart(BuildContext context) {
    final trend = controller.weeklyTrend;
    final labels = controller.weeklyLabels;
    final maxY = (trend.reduce((a, b) => a > b ? a : b)) + 6;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel(text: 'Weekly Billing Trend'),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= labels.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(labels[i], style: AppTextStyles.caption),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: List.generate(trend.length, (i) {
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: trend[i],
                        width: 18,
                        borderRadius: BorderRadius.circular(6),
                        gradient: AppColors.goldGradient,
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStockOverview(BuildContext context) {
    final byCategory = controller.stockByCategory;
    final colors = [
      AppColors.gold,
      AppColors.ember,
      AppColors.magenta,
      AppColors.teal,
      AppColors.skyBlue,
      AppColors.success,
    ];
    final entries = byCategory.entries.toList();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel(text: 'Products by Category'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                height: 140,
                width: 140,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 3,
                    centerSpaceRadius: 34,
                    sections: List.generate(entries.length, (i) {
                      return PieChartSectionData(
                        value: entries[i].value.toDouble(),
                        color: colors[i % colors.length],
                        showTitle: false,
                        radius: 26,
                      );
                    }),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: List.generate(entries.length, (i) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: colors[i % colors.length],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${entries[i].key} (${entries[i].value})',
                            style: AppTextStyles.caption,
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivity(BuildContext context) {
    final recentQuotations = controller.quotations.take(3).toList();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(
            text: 'Recent Quotations',
            trailing: TextButton(
              onPressed: () => Get.toNamed(AppRoutes.quotationList),
              child: const Text('View all'),
            ),
          ),
          ...recentQuotations.map((q) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.description_rounded,
                        color: AppColors.gold, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(q.quotationNo, style: AppTextStyles.bodyStrong),
                        Text(q.partyName, style: AppTextStyles.caption),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('₹${q.total.toStringAsFixed(0)}',
                          style: AppTextStyles.bodyStrong),
                      const SizedBox(height: 4),
                      StatusBadge(status: q.status),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
