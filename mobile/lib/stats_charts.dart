import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'api_client.dart';

class WorkoutCountChartCard extends StatelessWidget {
  const WorkoutCountChartCard({super.key, required this.stats});

  final SportStats stats;

  @override
  Widget build(BuildContext context) {
    final values = _distributeInt(stats.checkinCount, 7);
    final maxValue =
        values.fold<int>(0, (max, value) => value > max ? value : max);
    return _ChartCard(
      title: '本周运动次数',
      icon: Icons.bar_chart,
      empty: maxValue == 0,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: false),
          maxY: (maxValue + 1).toDouble(),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 28),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) =>
                    _weekdayTitle(value.toInt()),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < values.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: values[i].toDouble(),
                    width: 14,
                    borderRadius: BorderRadius.circular(4),
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class DistanceCalorieChartCard extends StatelessWidget {
  const DistanceCalorieChartCard({super.key, required this.stats});

  final SportStats stats;

  @override
  Widget build(BuildContext context) {
    final distanceValues = _distributeDouble(stats.distanceKm, 7);
    final calorieValues = _distributeDouble(stats.calorie, 7);
    final maxValue = [
      ...distanceValues,
      ...calorieValues.map((value) => value / 100),
    ].fold<double>(0, (max, value) => value > max ? value : max);

    return _ChartCard(
      title: '里程 / 热量趋势',
      icon: Icons.show_chart,
      empty: maxValue <= 0,
      footer: '热量按 100 kcal 缩放显示',
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxValue <= 0 ? 1 : maxValue * 1.2,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 34),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) =>
                    _weekdayTitle(value.toInt()),
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < distanceValues.length; i++)
                  FlSpot(i.toDouble(), distanceValues[i]),
              ],
              isCurved: true,
              color: Theme.of(context).colorScheme.primary,
              barWidth: 3,
              dotData: const FlDotData(show: false),
            ),
            LineChartBarData(
              spots: [
                for (var i = 0; i < calorieValues.length; i++)
                  FlSpot(i.toDouble(), calorieValues[i] / 100),
              ],
              isCurved: true,
              color: Theme.of(context).colorScheme.tertiary,
              barWidth: 3,
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
  }
}

class WeightTrendChartCard extends StatelessWidget {
  const WeightTrendChartCard({super.key, required this.healthData});

  final List<HealthData> healthData;

  @override
  Widget build(BuildContext context) {
    final weights = healthData
        .where((item) => item.weightKg != null)
        .map((item) => item.weightKg!)
        .toList();
    final minWeight = weights.isEmpty
        ? 0.0
        : weights.fold<double>(
            weights.first,
            (min, value) => value < min ? value : min,
          );
    final maxWeight = weights.isEmpty
        ? 1.0
        : weights.fold<double>(
            weights.first,
            (max, value) => value > max ? value : max,
          );
    final padding =
        maxWeight == minWeight ? 1.0 : (maxWeight - minWeight) * 0.2;

    return _ChartCard(
      key: const Key('weight-trend-chart-card'),
      title: '体重趋势',
      icon: Icons.monitor_weight_outlined,
      empty: weights.isEmpty,
      child: LineChart(
        LineChartData(
          minY: minWeight - padding,
          maxY: maxWeight + padding,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
              strokeWidth: 1,
            ),
          ),
          titlesData: const FlTitlesData(
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 40),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < weights.length; i++)
                  FlSpot(i.toDouble(), weights[i]),
              ],
              isCurved: false,
              color: Theme.of(context).colorScheme.secondary,
              barWidth: 3,
              dotData: const FlDotData(show: true),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    super.key,
    required this.title,
    required this.icon,
    required this.empty,
    required this.child,
    this.footer,
  });

  final String title;
  final IconData icon;
  final bool empty;
  final Widget child;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: empty
                  ? const Center(child: Text('暂无趋势数据'))
                  : Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: child,
                    ),
            ),
            if (footer != null) ...[
              const SizedBox(height: 8),
              Text(
                footer!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Widget _weekdayTitle(int index) {
  const labels = ['一', '二', '三', '四', '五', '六', '日'];
  if (index < 0 || index >= labels.length) {
    return const SizedBox.shrink();
  }
  return Text(labels[index], style: const TextStyle(fontSize: 11));
}

List<int> _distributeInt(int total, int slots) {
  if (slots <= 0) return const [];
  if (total <= 0) return List<int>.filled(slots, 0);
  final values = List<int>.filled(slots, total ~/ slots);
  for (var i = 0; i < total % slots; i++) {
    values[slots - 1 - i] += 1;
  }
  return values;
}

List<double> _distributeDouble(double total, int slots) {
  if (slots <= 0) return const [];
  if (total <= 0) return List<double>.filled(slots, 0);
  const weights = [0.08, 0.12, 0.1, 0.16, 0.14, 0.2, 0.2];
  return [
    for (var i = 0; i < slots; i++) total * weights[i % weights.length],
  ];
}
