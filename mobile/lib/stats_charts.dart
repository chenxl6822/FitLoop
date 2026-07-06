import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'api_client.dart';

const _primaryGreen = Color(0xFF1F8A70);
const _trendBlue = Color(0xFF2F80ED);
const _softGreen = Color(0xFFEAF7F2);
const _chartHeight = 176.0;

/// 基于真实历史数据的柱状图：本周每天运动次数。
class WorkoutCountChartCard extends StatelessWidget {
  const WorkoutCountChartCard({super.key, required this.history});

  final SportHistoryResponse history;

  @override
  Widget build(BuildContext context) {
    final days = _normaliseWeek(history.points);
    final values = days.map((day) => day.count).toList();
    final total = values.fold<int>(0, (sum, value) => sum + value);
    final maxValue = values.fold<int>(0, math.max);
    final maxY = _niceCeil(math.max(2, maxValue * 1.25).toDouble());
    final interval = _niceInterval(maxY, steps: 4);
    final bestIndex = _maxIndex(values);

    return _ChartCard(
      title: '本周运动次数',
      subtitle: '周一到周日打卡分布',
      icon: Icons.bar_chart_rounded,
      empty: total == 0,
      emptyMessage: '完成一次运动打卡后，会在这里看到本周节奏。',
      summaries: [
        _SummaryItem(
          label: '本周总次数',
          value: '$total 次',
          tone: _primaryGreen,
        ),
        _SummaryItem(
          label: '日均运动',
          value: '${_formatDecimal(total / 7, digits: 1)} 次',
          tone: _trendBlue,
        ),
        _SummaryItem(
          label: '最活跃',
          value: total == 0
              ? '暂无'
              : '${_weekdayNames[bestIndex]} ${values[bestIndex]} 次',
          tone: const Color(0xFF6B7280),
        ),
      ],
      child: BarChart(
        BarChartData(
          minY: 0,
          maxY: maxY,
          alignment: BarChartAlignment.spaceAround,
          groupsSpace: 10,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              tooltipRoundedRadius: 10,
              getTooltipColor: (_) => Colors.black.withValues(alpha: 0.78),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem(
                  '${_weekdayNames[group.x.toInt()]}\n${rod.toY.toInt()} 次',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                );
              },
            ),
          ),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: interval,
            getDrawingHorizontalLine: (value) => _gridLine(context),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: interval,
                getTitlesWidget: (value, meta) =>
                    _leftAxisTitle(context, value, integerOnly: true),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final index = value.round();
                  if ((value - index).abs() > 0.01 ||
                      index < 0 ||
                      index >= _weekdayNames.length) {
                    return const SizedBox.shrink();
                  }
                  return _bottomAxisTitle(context, _weekdayNames[index]);
                },
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
                    width: 18,
                    borderRadius: BorderRadius.circular(8),
                    color: values[i] > 0
                        ? _primaryGreen
                        : _primaryGreen.withValues(alpha: 0.18),
                    backDrawRodData: BackgroundBarChartRodData(
                      show: true,
                      toY: maxY,
                      color: _primaryGreen.withValues(alpha: 0.08),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// 基于真实历史数据的折线图：每日里程 + 热量趋势。
class DistanceCalorieChartCard extends StatelessWidget {
  const DistanceCalorieChartCard({super.key, required this.history});

  final SportHistoryResponse history;

  @override
  Widget build(BuildContext context) {
    final days = _normaliseWeek(history.points);
    final distances = days.map((day) => day.distanceKm).toList();
    final calories = days.map((day) => day.calorie).toList();
    final calorieScale = calories.map((value) => value / 100).toList();
    final latestIndex = _lastIndexWhere(
      days,
      (day) => day.distanceKm > 0 || day.calorie > 0,
    );
    final previousIndex = latestIndex == null
        ? null
        : _lastIndexWhere(
            days.take(latestIndex).toList(),
            (day) => day.distanceKm > 0 || day.calorie > 0,
          );
    final latest = latestIndex == null ? null : days[latestIndex];
    final previous = previousIndex == null ? null : days[previousIndex];
    final maxValue = <double>[
      ...distances,
      ...calorieScale,
    ].fold<double>(0, math.max);
    final hasData = maxValue > 0;
    final maxY = _niceCeil(math.max(1, maxValue * 1.25));
    final interval = _niceInterval(maxY, steps: 4);

    return _ChartCard(
      title: '里程 / 热量趋势',
      subtitle: '里程按 km，热量按 100 kcal/格',
      icon: Icons.show_chart_rounded,
      empty: !hasData,
      emptyMessage: '完成带里程或热量的打卡后，会生成趋势曲线。',
      summaries: [
        _SummaryItem(
          label: '最新里程',
          value: latest == null
              ? '0 km'
              : '${_formatDecimal(latest.distanceKm, digits: 1)} km',
          tone: _primaryGreen,
        ),
        _SummaryItem(
          label: '最新热量',
          value: latest == null
              ? '0 kcal'
              : '${latest.calorie.toStringAsFixed(0)} kcal',
          tone: _trendBlue,
        ),
        _SummaryItem(
          label: '较上次',
          value: _sportDistanceDelta(latest, previous),
          detail: _sportCalorieDelta(latest, previous),
          tone: const Color(0xFF6B7280),
        ),
      ],
      legend: const [
        _LegendItem(label: '里程 km', color: _primaryGreen),
        _LegendItem(label: '热量 100 kcal/格', color: _trendBlue),
      ],
      footer: '摘要显示真实数值；为了同图比较，热量曲线按 100 kcal = 1 格绘制。',
      child: LineChart(
        LineChartData(
          minX: -0.2,
          maxX: days.length - 0.8,
          minY: 0,
          maxY: maxY,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: interval,
            getDrawingHorizontalLine: (value) => _gridLine(context),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 34,
                interval: interval,
                getTitlesWidget: (value, meta) =>
                    _leftAxisTitle(context, value),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) =>
                    _weekBottomTitle(context, value),
              ),
            ),
          ),
          lineBarsData: [
            _lineBar(
              values: distances,
              color: _primaryGreen,
              highlightIndex: latestIndex,
            ),
            _lineBar(
              values: calorieScale,
              color: _trendBlue,
              highlightIndex: latestIndex,
            ),
          ],
        ),
      ),
    );
  }
}

/// 体重趋势折线图：来自后端历史数据。
class WeightTrendChartCard extends StatelessWidget {
  const WeightTrendChartCard({super.key, required this.history});

  final WeightHistoryResponse history;

  @override
  Widget build(BuildContext context) {
    final points = history.points
        .where((point) => point.weightKg != null)
        .toList()
      ..sort(_compareWeightPoint);
    final weights = points.map((point) => point.weightKg!).toList();

    if (weights.isEmpty) {
      return const _ChartCard(
        key: Key('weight-trend-chart-card'),
        title: '体重趋势',
        subtitle: '最近 30 天记录',
        icon: Icons.monitor_weight_outlined,
        empty: true,
        emptyMessage: '记录体重后，会在这里看到变化趋势。',
        child: SizedBox.shrink(),
      );
    }

    final latest = weights.last;
    final previous = weights.length >= 2 ? weights[weights.length - 2] : null;
    final range = _weightRange(weights);
    final interval = _niceInterval(range.max - range.min, steps: 4);

    return _ChartCard(
      key: const Key('weight-trend-chart-card'),
      title: '体重趋势',
      subtitle: '单位 kg，最新记录已高亮',
      icon: Icons.monitor_weight_outlined,
      empty: false,
      summaries: [
        _SummaryItem(
          label: '当前体重',
          value: '${_formatDecimal(latest, digits: 1)} kg',
          tone: _primaryGreen,
        ),
        _SummaryItem(
          label: '较上次',
          value:
              previous == null ? '暂无对比' : _signed(latest - previous, digits: 1),
          detail: previous == null ? null : 'kg',
          tone: _trendBlue,
        ),
        _SummaryItem(
          label: '最近趋势',
          value: _weightTrend(latest, previous),
          tone: const Color(0xFF6B7280),
        ),
      ],
      legend: const [
        _LegendItem(label: '体重 kg', color: _primaryGreen),
      ],
      child: LineChart(
        LineChartData(
          minX: weights.length == 1 ? -0.6 : -0.2,
          maxX: weights.length == 1 ? 0.6 : weights.length - 0.8,
          minY: range.min,
          maxY: range.max,
          borderData: FlBorderData(show: false),
          extraLinesData: ExtraLinesData(
            // 单点时用轻量参考线补足画面，不伪造趋势。
            horizontalLines: weights.length == 1
                ? [
                    HorizontalLine(
                      y: latest,
                      color: _primaryGreen.withValues(alpha: 0.18),
                      strokeWidth: 1,
                      dashArray: [6, 4],
                    ),
                  ]
                : [],
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: interval,
            getDrawingHorizontalLine: (value) => _gridLine(context),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (value, meta) =>
                    _dateBottomTitle(context, value, points),
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 42,
                interval: interval,
                getTitlesWidget: (value, meta) =>
                    _leftAxisTitle(context, value),
              ),
            ),
          ),
          lineBarsData: [
            _lineBar(
              values: weights,
              color: _primaryGreen,
              highlightIndex: weights.length - 1,
              curved: weights.length > 2,
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
    this.subtitle,
    this.summaries = const [],
    this.legend = const [],
    this.footer,
    this.emptyMessage = '完成记录后，会在这里看到趋势。',
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final bool empty;
  final Widget child;
  final List<_SummaryItem> summaries;
  final List<_LegendItem> legend;
  final String? footer;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 2,
      shadowColor: _primaryGreen.withValues(alpha: 0.10),
      surfaceTintColor: colorScheme.surfaceTint.withValues(alpha: 0.04),
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ChartHeader(icon: icon, title: title, subtitle: subtitle),
            if (summaries.isNotEmpty) ...[
              const SizedBox(height: 14),
              _SummaryWrap(items: summaries),
            ],
            if (legend.isNotEmpty) ...[
              const SizedBox(height: 12),
              _LegendWrap(items: legend),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: _chartHeight,
              child: empty
                  ? _EmptyChartState(message: emptyMessage)
                  : Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: child,
                    ),
            ),
            if (footer != null) ...[
              const SizedBox(height: 10),
              Text(
                footer!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChartHeader extends StatelessWidget {
  const _ChartHeader({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _softGreen,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 19, color: _primaryGreen),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.2,
                      ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryItem {
  const _SummaryItem({
    required this.label,
    required this.value,
    required this.tone,
    this.detail,
  });

  final String label;
  final String value;
  final String? detail;
  final Color tone;
}

class _SummaryWrap extends StatelessWidget {
  const _SummaryWrap({required this.items});

  final List<_SummaryItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth >= 330
            ? (constraints.maxWidth - 16) / 3
            : (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in items)
              SizedBox(
                width: itemWidth,
                child: _SummaryTile(item: item),
              ),
          ],
        );
      },
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.item});

  final _SummaryItem item;

  @override
  Widget build(BuildContext context) {
    final background = Color.alphaBlend(
      item.tone.withValues(alpha: 0.10),
      Theme.of(context).colorScheme.surface,
    );

    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: item.tone.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            item.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: item.tone,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
          ),
          if (item.detail != null) ...[
            const SizedBox(height: 2),
            Text(
              item.detail!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.1,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LegendItem {
  const _LegendItem({required this.label, required this.color});

  final String label;
  final Color color;
}

class _LegendWrap extends StatelessWidget {
  const _LegendWrap({required this.items});

  final List<_LegendItem> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        for (final item in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 18,
                height: 4,
                decoration: BoxDecoration(
                  color: item.color,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                item.label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
      ],
    );
  }
}

class _EmptyChartState extends StatelessWidget {
  const _EmptyChartState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.insights_rounded,
                size: 30,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
              ),
              const SizedBox(height: 8),
              Text(
                '暂无数据',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurface,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

LineChartBarData _lineBar({
  required List<double> values,
  required Color color,
  int? highlightIndex,
  bool curved = true,
}) {
  return LineChartBarData(
    spots: [
      for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i]),
    ],
    isCurved: curved && values.length > 2,
    color: color,
    barWidth: 3,
    isStrokeCapRound: true,
    belowBarData: BarAreaData(
      show: true,
      color: color.withValues(alpha: 0.08),
    ),
    dotData: FlDotData(
      show: true,
      getDotPainter: (spot, percent, barData, index) {
        final highlighted = index == highlightIndex;
        final isZero = spot.y.abs() < 0.001;
        return FlDotCirclePainter(
          radius: highlighted ? 5 : (isZero ? 2 : 3),
          color: highlighted ? color : Colors.white,
          strokeWidth: highlighted ? 3 : 2,
          strokeColor: color.withValues(alpha: highlighted ? 0.85 : 0.70),
        );
      },
    ),
  );
}

FlLine _gridLine(BuildContext context) {
  return FlLine(
    color: Theme.of(context).dividerColor.withValues(alpha: 0.28),
    strokeWidth: 0.8,
  );
}

Widget _leftAxisTitle(
  BuildContext context,
  double value, {
  bool integerOnly = false,
}) {
  if (value < 0) {
    return const SizedBox.shrink();
  }
  if (integerOnly && (value - value.round()).abs() > 0.01) {
    return const SizedBox.shrink();
  }
  return Text(
    integerOnly ? value.round().toString() : _formatAxisValue(value),
    style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
  );
}

Widget _weekBottomTitle(BuildContext context, double value) {
  final index = value.round();
  if ((value - index).abs() > 0.01 || index < 0 || index >= 7) {
    return const SizedBox.shrink();
  }
  return _bottomAxisTitle(context, _weekdayNames[index]);
}

Widget _dateBottomTitle(
  BuildContext context,
  double value,
  List<WeightHistoryPoint> points,
) {
  final index = value.round();
  if ((value - index).abs() > 0.01 || index < 0 || index >= points.length) {
    return const SizedBox.shrink();
  }
  if (points.length > 6 && index != 0 && index != points.length - 1) {
    final step = (points.length / 4).ceil();
    if (index % step != 0) {
      return const SizedBox.shrink();
    }
  }
  return _bottomAxisTitle(context, _shortDate(points[index].date));
}

Widget _bottomAxisTitle(BuildContext context, String text) {
  return Padding(
    padding: const EdgeInsets.only(top: 7),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
    ),
  );
}

List<_SportDay> _normaliseWeek(List<SportHistoryPoint> points) {
  final totals = <String, _SportDayBuilder>{};
  DateTime? anchor;

  for (final point in points) {
    final date = _tryParseDate(point.date);
    if (date == null) {
      continue;
    }
    anchor ??= date;
    final key = _dateKey(date);
    totals.putIfAbsent(key, () => _SportDayBuilder(date)).add(point);
  }

  final start = _startOfWeek(anchor ?? DateTime.now());
  // 统一补齐 7 天，避免单天数据导致柱图布局和横轴语义失衡。
  return [
    for (var i = 0; i < 7; i++)
      (totals[_dateKey(start.add(Duration(days: i)))] ??
              _SportDayBuilder(start.add(Duration(days: i))))
          .build(),
  ];
}

class _SportDay {
  const _SportDay({
    required this.date,
    required this.count,
    required this.distanceKm,
    required this.calorie,
  });

  final DateTime date;
  final int count;
  final double distanceKm;
  final double calorie;
}

class _SportDayBuilder {
  _SportDayBuilder(this.date);

  final DateTime date;
  int count = 0;
  double distanceKm = 0;
  double calorie = 0;

  void add(SportHistoryPoint point) {
    count += point.count;
    distanceKm += point.distanceKm;
    calorie += point.calorie;
  }

  _SportDay build() {
    return _SportDay(
      date: date,
      count: count,
      distanceKm: distanceKm,
      calorie: calorie,
    );
  }
}

class _WeightRange {
  const _WeightRange({required this.min, required this.max});

  final double min;
  final double max;
}

_WeightRange _weightRange(List<double> weights) {
  final minWeight = weights.reduce(math.min);
  final maxWeight = weights.reduce(math.max);
  final center = (minWeight + maxWeight) / 2;
  final rawSpan = maxWeight - minWeight;
  // 体重图的纵轴保留最小跨度，避免 0.1kg 的变化被放大成剧烈波动。
  final targetSpan = rawSpan == 0
      ? 3.0
      : rawSpan < 1.2
          ? 2.4
          : rawSpan < 3
              ? rawSpan + 1.4
              : rawSpan * 1.25;
  final minY = math.max(0.0, _floorHalf(center - targetSpan / 2));
  final maxY = _ceilHalf(center + targetSpan / 2);
  return _WeightRange(min: minY, max: math.max(maxY, minY + 1.0));
}

int _compareWeightPoint(WeightHistoryPoint a, WeightHistoryPoint b) {
  final left = _tryParseDate(a.date);
  final right = _tryParseDate(b.date);
  if (left == null || right == null) {
    return a.date.compareTo(b.date);
  }
  return left.compareTo(right);
}

int _maxIndex(List<int> values) {
  var index = 0;
  for (var i = 1; i < values.length; i++) {
    if (values[i] > values[index]) {
      index = i;
    }
  }
  return index;
}

int? _lastIndexWhere<T>(List<T> items, bool Function(T item) test) {
  for (var i = items.length - 1; i >= 0; i--) {
    if (test(items[i])) {
      return i;
    }
  }
  return null;
}

String _sportDistanceDelta(_SportDay? latest, _SportDay? previous) {
  if (latest == null || previous == null) {
    return '暂无对比';
  }
  return '${_signed(latest.distanceKm - previous.distanceKm, digits: 1)} km';
}

String? _sportCalorieDelta(_SportDay? latest, _SportDay? previous) {
  if (latest == null || previous == null) {
    return null;
  }
  return '${_signed(latest.calorie - previous.calorie, digits: 0)} kcal';
}

String _weightTrend(double latest, double? previous) {
  if (previous == null) {
    return '首次记录';
  }
  final delta = latest - previous;
  if (delta.abs() < 0.05) {
    return '持平';
  }
  return delta > 0 ? '上升' : '下降';
}

String _signed(double value, {required int digits}) {
  if (value.abs() < 0.05) {
    return digits == 0 ? '0' : value.toStringAsFixed(digits);
  }
  final prefix = value > 0 ? '+' : '';
  return '$prefix${value.toStringAsFixed(digits)}';
}

double _niceCeil(double value) {
  if (value <= 0) {
    return 1;
  }
  final exponent =
      math.pow(10, (math.log(value) / math.ln10).floor()).toDouble();
  final fraction = value / exponent;
  final niceFraction = fraction <= 1
      ? 1
      : fraction <= 2
          ? 2
          : fraction <= 5
              ? 5
              : 10;
  return niceFraction * exponent;
}

double _niceInterval(double span, {required int steps}) {
  if (span <= 0) {
    return 1;
  }
  return _niceCeil(span / steps);
}

double _floorHalf(double value) => (value * 2).floorToDouble() / 2;

double _ceilHalf(double value) => (value * 2).ceilToDouble() / 2;

String _formatAxisValue(double value) {
  if (value.abs() >= 10 || (value - value.round()).abs() < 0.05) {
    return value.round().toString();
  }
  return value.toStringAsFixed(1);
}

String _formatDecimal(double value, {required int digits}) {
  if ((value - value.round()).abs() < 0.05) {
    return value.round().toString();
  }
  return value.toStringAsFixed(digits);
}

DateTime _startOfWeek(DateTime date) {
  final normalised = DateTime(date.year, date.month, date.day);
  return normalised.subtract(Duration(days: normalised.weekday - 1));
}

DateTime? _tryParseDate(String value) {
  try {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return null;
    }
    return DateTime(parsed.year, parsed.month, parsed.day);
  } catch (_) {
    return null;
  }
}

String _dateKey(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String _shortDate(String isoDate) {
  final date = _tryParseDate(isoDate);
  if (date != null) {
    return '${date.month}/${date.day}';
  }
  return isoDate;
}

const _weekdayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
