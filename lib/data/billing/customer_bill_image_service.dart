import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/money.dart';
import '../database/app_database.dart';

typedef BillOutputDirectoryProvider = Future<Directory> Function();

/// 一张客户账单长图的生成结果。
final class CustomerBillImageResult {
  const CustomerBillImageResult({
    required this.file,
    required this.width,
    required this.height,
    required this.entryCount,
    required this.balanceCents,
    required this.generatedAt,
  });

  final File file;
  final int width;
  final int height;
  final int entryCount;
  final int balanceCents;
  final DateTime generatedAt;
}

/// 经过客户隔离、排序与结清周期截取后的账单数据。
///
/// 公开这个不可变结果，便于在不解码 PNG 的情况下核对隐私边界与
/// 结清周期口径。
final class CustomerBillStatement {
  CustomerBillStatement._({
    required this.customer,
    required this.entries,
    required this.balanceCents,
    required this.shopName,
    required this.generatedAt,
  });

  factory CustomerBillStatement.build({
    required CustomerRow customer,
    required Iterable<LedgerEntryRow> effectiveEntries,
    required DateTime generatedAt,
    String? shopName,
  }) {
    if (customer.deletedAt != null) {
      throw StateError('已进入回收站的客户不能生成账单');
    }

    final ordered =
        effectiveEntries
            .where(
              (entry) =>
                  entry.customerId == customer.id && entry.deletedAt == null,
            )
            .toList(growable: false)
          ..sort(_compareEntries);

    var balance = 0;
    final runningBalances = <int>[];
    for (final entry in ordered) {
      balance += _signedAmount(entry);
      runningBalances.add(balance);
    }

    var startIndex = 0;
    if (ordered.isNotEmpty) {
      // 未结清：从最后一次归零的下一笔开始。
      // 已结清：忽略末尾这个归零点，回溯到前一个归零点，
      // 从而保留“最近一个刚结清周期”。
      final searchEnd = balance == 0
          ? runningBalances.length - 1
          : runningBalances.length;
      for (var index = 0; index < searchEnd; index++) {
        if (runningBalances[index] == 0) startIndex = index + 1;
      }
    }

    return CustomerBillStatement._(
      customer: customer,
      entries: List.unmodifiable(ordered.sublist(startIndex)),
      balanceCents: balance,
      shopName: shopName?.trim() ?? '',
      generatedAt: generatedAt.toLocal(),
    );
  }

  final CustomerRow customer;
  final List<LedgerEntryRow> entries;
  final int balanceCents;
  final String shopName;
  final DateTime generatedAt;

  static int _compareEntries(LedgerEntryRow left, LedgerEntryRow right) {
    final byDate = left.bizDate.compareTo(right.bizDate);
    if (byDate != 0) return byDate;
    final byCreation = left.createdAt.compareTo(right.createdAt);
    if (byCreation != 0) return byCreation;
    return left.id.compareTo(right.id);
  }

  static int _signedAmount(LedgerEntryRow entry) => switch (entry.kind) {
    'initial' || 'debt' => entry.amountCents,
    'payment' || 'discount' => -entry.amountCents,
    _ => throw FormatException('未知流水类型：${entry.kind}'),
  };
}

/// 用 [Canvas] 与 [TextPainter] 直接生成 750px 宽的客户账单 PNG。
///
/// 不依赖页面 Widget，因此也不需要在分享前把账单预览挂入 Widget 树。
final class CustomerBillImageService {
  CustomerBillImageService(
    this.database, {
    DateTime Function()? clock,
    BillOutputDirectoryProvider? outputDirectoryProvider,
  }) : _clock = clock ?? DateTime.now,
       _outputDirectoryProvider =
           outputDirectoryProvider ?? _defaultOutputDirectory;

  static const int logicalWidth = 750;

  final AppDatabase database;
  final DateTime Function() _clock;
  final BillOutputDirectoryProvider _outputDirectoryProvider;

  /// 生成账单并写入 App 私有缓存下的分享目录。
  ///
  /// [effectiveEntries] 可传入页面已加载的有效流水；省略时直接从
  /// [database] 查询该客户未删除流水。即使传入了混合多客户的列表，
  /// 服务也会再次按客户 ID 和 deleted_at 隔离。
  Future<CustomerBillImageResult> generate({
    required CustomerRow customer,
    Iterable<LedgerEntryRow>? effectiveEntries,
    String? shopName,
  }) async {
    final generatedAt = _clock().toLocal();
    final sourceEntries =
        effectiveEntries?.toList(growable: false) ??
        await _loadEffectiveEntries(customer.id);
    final statement = CustomerBillStatement.build(
      customer: customer,
      effectiveEntries: sourceEntries,
      shopName: shopName,
      generatedAt: generatedAt,
    );

    final renderer = _CustomerBillCanvasRenderer(statement);
    final rendered = await renderer.render();
    final directory = await _outputDirectoryProvider();
    await directory.create(recursive: true);
    final file = await _nextAvailableFile(directory, customer.id, generatedAt);
    await file.writeAsBytes(rendered.bytes, flush: true);

    return CustomerBillImageResult(
      file: file,
      width: logicalWidth,
      height: rendered.height,
      entryCount: statement.entries.length,
      balanceCents: statement.balanceCents,
      generatedAt: generatedAt,
    );
  }

  Future<List<LedgerEntryRow>> _loadEffectiveEntries(int customerId) {
    return (database.select(database.ledgerEntries)
          ..where(
            (entry) =>
                entry.customerId.equals(customerId) & entry.deletedAt.isNull(),
          )
          ..orderBy([
            (entry) => OrderingTerm.asc(entry.bizDate),
            (entry) => OrderingTerm.asc(entry.createdAt),
            (entry) => OrderingTerm.asc(entry.id),
          ]))
        .get();
  }

  static Future<Directory> _defaultOutputDirectory() async {
    final cache = await getTemporaryDirectory();
    return Directory(
      '${cache.path}${Platform.pathSeparator}exports'
      '${Platform.pathSeparator}customer_bills',
    );
  }

  static Future<File> _nextAvailableFile(
    Directory directory,
    int customerId,
    DateTime generatedAt,
  ) async {
    final timestamp = _fileTimestamp(generatedAt);
    var suffix = 0;
    while (true) {
      final suffixText = suffix == 0 ? '' : '-$suffix';
      final file = File(
        '${directory.path}${Platform.pathSeparator}'
        'customer-bill-$customerId-$timestamp$suffixText.png',
      );
      if (!await file.exists()) return file;
      suffix++;
    }
  }

  static String _fileTimestamp(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}${two(value.month)}${two(value.day)}-'
        '${two(value.hour)}${two(value.minute)}${two(value.second)}';
  }
}

final class CustomerBillImageTooTallException implements Exception {
  const CustomerBillImageTooTallException({
    required this.requiredHeight,
    required this.maximumHeight,
  });

  final int requiredHeight;
  final int maximumHeight;

  @override
  String toString() =>
      '账单明细过多，生成图片需要 $requiredHeight px 高，'
      '超过安全上限 $maximumHeight px';
}

final class _RenderedBill {
  const _RenderedBill({required this.bytes, required this.height});

  final Uint8List bytes;
  final int height;
}

final class _CustomerBillCanvasRenderer {
  const _CustomerBillCanvasRenderer(this.statement);

  // 750 * 24000 * 4 约 69 MiB 原始像素。先测量再分配，避免极端
  // 历史流水导致进程被 OOM 杀掉；绝不会为压高度而静默丢明细。
  static const int _maximumHeight = 24000;
  static const double _pageWidth = CustomerBillImageService.logicalWidth * 1.0;
  static const double _left = 54;
  static const double _contentWidth = _pageWidth - _left * 2;

  static const Color _white = Color(0xFFFFFFFF);
  static const Color _ink = Color(0xFF2B2922);
  static const Color _muted = Color(0xFF6E6A5B);
  static const Color _line = Color(0xFFE7E4DA);
  static const Color _lineSoft = Color(0xFFEFEDE5);
  static const Color _greenInk = Color(0xFF14493A);
  static const Color _greenBackground = Color(0xFFE9F1ED);
  static const Color _red = Color(0xFFB5382A);
  static const Color _amberInk = Color(0xFF8A6A1F);
  static const Color _disabled = Color(0xFFA7A392);

  static const List<String> _fontFallback = [
    'PingFang SC',
    'HarmonyOS Sans SC',
    'MiSans',
    'Noto Sans CJK SC',
    'Microsoft YaHei',
  ];

  final CustomerBillStatement statement;

  Future<_RenderedBill> render() async {
    final requiredHeight = _layout(null).ceil();
    if (requiredHeight > _maximumHeight) {
      throw CustomerBillImageTooTallException(
        requiredHeight: requiredHeight,
        maximumHeight: _maximumHeight,
      );
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, _pageWidth, requiredHeight.toDouble()),
      Paint()..color = _white,
    );
    _layout(canvas);

    final picture = recorder.endRecording();
    ui.Image? image;
    try {
      image = await picture.toImage(
        CustomerBillImageService.logicalWidth,
        requiredHeight,
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('账单 PNG 编码失败');
      return _RenderedBill(
        bytes: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        height: requiredHeight,
      );
    } finally {
      image?.dispose();
      picture.dispose();
    }
  }

  double _layout(Canvas? canvas) {
    var y = 54.0;

    if (statement.shopName.isNotEmpty) {
      y += _text(
        canvas,
        statement.shopName,
        x: _left,
        y: y,
        width: _contentWidth,
        style: _style(27, _muted, weight: FontWeight.w600),
        align: TextAlign.center,
      );
      y += 12;
    }

    y += _text(
      canvas,
      '欠款对账单',
      x: _left,
      y: y,
      width: _contentWidth,
      style: _style(42, _ink, weight: FontWeight.w800, letterSpacing: 8),
      align: TextAlign.center,
      maxLines: 1,
    );
    y += 20;

    final customerName = statement.customer.note.trim().isEmpty
        ? statement.customer.name
        : '${statement.customer.name}（${statement.customer.note.trim()}）';
    y += _text(
      canvas,
      customerName,
      x: _left,
      y: y,
      width: _contentWidth,
      style: _style(32, _ink, weight: FontWeight.w700),
      align: TextAlign.center,
    );
    y += 8;

    y += _text(
      canvas,
      '截至 ${_chineseDate(statement.generatedAt)}',
      x: _left,
      y: y,
      width: _contentWidth,
      style: _style(24, _muted),
      align: TextAlign.center,
      maxLines: 1,
    );
    y += 30;
    _dashedLine(canvas, y);
    y += 30;

    final balanceLabel = switch (statement.balanceCents) {
      > 0 => '现在共欠',
      < 0 => '多付了',
      _ => '当前状态',
    };
    y += _text(
      canvas,
      balanceLabel,
      x: _left,
      y: y,
      width: _contentWidth,
      style: _style(26, _muted),
      align: TextAlign.center,
      maxLines: 1,
    );
    y += 6;

    final balanceText = statement.balanceCents == 0
        ? '已结清'
        : '¥ ${Money.formatCents(statement.balanceCents.abs())}';
    final balanceColor = switch (statement.balanceCents) {
      > 0 => _red,
      < 0 => _greenInk,
      _ => _muted,
    };
    y += _text(
      canvas,
      balanceText,
      x: _left,
      y: y,
      width: _contentWidth,
      style: _style(
        statement.balanceCents == 0 ? 42 : 62,
        balanceColor,
        weight: FontWeight.w800,
      ),
      align: TextAlign.center,
      maxLines: 1,
      fitSingleLine: true,
    );
    y += 34;
    _dashedLine(canvas, y);
    y += 28;

    y = _table(canvas, y);
    y += 30;
    _dashedLine(canvas, y);
    y += 28;

    y += _text(
      canvas,
      '本单由记账本生成 · 如有疑问请当面对账',
      x: _left,
      y: y,
      width: _contentWidth,
      style: _style(22, _disabled),
      align: TextAlign.center,
    );
    y += 8;
    y += _text(
      canvas,
      '生成于 ${_generatedTime(statement.generatedAt)}',
      x: _left,
      y: y,
      width: _contentWidth,
      style: _style(22, _disabled),
      align: TextAlign.center,
      maxLines: 1,
    );
    return y + 54;
  }

  double _table(Canvas? canvas, double y) {
    const headerHeight = 52.0;
    if (canvas != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(_left, y, _contentWidth, headerHeight),
          const Radius.circular(8),
        ),
        Paint()..color = _greenBackground,
      );
    }
    final headerStyle = _style(22, _greenInk, weight: FontWeight.w700);
    _tableCells(
      canvas,
      y + 10,
      date: '日期',
      kind: '类型',
      business: '业务',
      amount: '金额',
      style: headerStyle,
      amountColor: _greenInk,
    );
    y += headerHeight;

    if (statement.entries.isEmpty) {
      y += 24;
      y += _text(
        canvas,
        '本周期暂无流水',
        x: _left,
        y: y,
        width: _contentWidth,
        style: _style(25, _muted),
        align: TextAlign.center,
        maxLines: 1,
      );
      return y + 24;
    }

    for (final entry in statement.entries) {
      final business = entry.business.trim().isEmpty
          ? '—'
          : entry.business.trim();
      final businessHeight = _measureText(
        business,
        width: 224,
        style: _style(24, _ink),
      );
      final rowHeight = businessHeight < 34 ? 58.0 : businessHeight + 24;
      final positive = entry.kind == 'initial' || entry.kind == 'debt';
      final amount =
          '${positive ? '+' : '−'}'
          '¥${Money.formatCents(entry.amountCents)}';
      _tableCells(
        canvas,
        y + 12,
        date: _displayDate(entry.bizDate),
        kind: _kindLabel(entry.kind),
        business: business,
        amount: amount,
        style: _style(24, _ink),
        amountColor: switch (entry.kind) {
          'initial' => _muted,
          'debt' => _red,
          'payment' => _greenInk,
          'discount' => _amberInk,
          _ => _ink,
        },
      );
      y += rowHeight;
      if (canvas != null) {
        canvas.drawLine(
          Offset(_left, y),
          Offset(_left + _contentWidth, y),
          Paint()
            ..color = _lineSoft
            ..strokeWidth = 1.5,
        );
      }
    }
    return y;
  }

  void _tableCells(
    Canvas? canvas,
    double y, {
    required String date,
    required String kind,
    required String business,
    required String amount,
    required TextStyle style,
    required Color amountColor,
  }) {
    _text(
      canvas,
      date,
      x: _left,
      y: y,
      width: 144,
      style: style.copyWith(fontSize: 21, color: _muted),
      maxLines: 1,
      fitSingleLine: true,
    );
    _text(
      canvas,
      kind,
      x: _left + 150,
      y: y,
      width: 82,
      style: style,
      maxLines: 1,
      fitSingleLine: true,
    );
    _text(canvas, business, x: _left + 240, y: y, width: 224, style: style);
    _text(
      canvas,
      amount,
      x: _left + 474,
      y: y,
      width: 168,
      style: style.copyWith(color: amountColor, fontWeight: FontWeight.w700),
      align: TextAlign.right,
      maxLines: 1,
      fitSingleLine: true,
    );
  }

  static TextStyle _style(
    double size,
    Color color, {
    FontWeight weight = FontWeight.w400,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontSize: size,
      color: color,
      fontWeight: weight,
      height: 1.3,
      letterSpacing: letterSpacing,
      fontFamilyFallback: _fontFallback,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );
  }

  static double _text(
    Canvas? canvas,
    String value, {
    required double x,
    required double y,
    required double width,
    required TextStyle style,
    TextAlign align = TextAlign.left,
    int? maxLines,
    bool fitSingleLine = false,
  }) {
    var fittedStyle = style;
    TextPainter painter;
    while (true) {
      painter = TextPainter(
        text: TextSpan(text: value, style: fittedStyle),
        textDirection: ui.TextDirection.ltr,
        textAlign: align,
        maxLines: maxLines,
      )..layout(minWidth: width, maxWidth: width);
      if (!fitSingleLine ||
          !painter.didExceedMaxLines ||
          (fittedStyle.fontSize ?? 0) <= 16) {
        break;
      }
      painter.dispose();
      fittedStyle = fittedStyle.copyWith(
        fontSize: (fittedStyle.fontSize ?? 16) - 1,
      );
    }
    if (canvas != null) painter.paint(canvas, Offset(x, y));
    final height = painter.height;
    painter.dispose();
    return height;
  }

  static double _measureText(
    String value, {
    required double width,
    required TextStyle style,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: ui.TextDirection.ltr,
    )..layout(maxWidth: width);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  static void _dashedLine(Canvas? canvas, double y) {
    if (canvas == null) return;
    final paint = Paint()
      ..color = _line
      ..strokeWidth = 2;
    const dash = 12.0;
    const gap = 9.0;
    var x = _left;
    while (x < _left + _contentWidth) {
      canvas.drawLine(
        Offset(x, y),
        Offset((x + dash).clamp(_left, _left + _contentWidth).toDouble(), y),
        paint,
      );
      x += dash + gap;
    }
  }

  static String _kindLabel(String kind) => switch (kind) {
    'initial' => '期初',
    'debt' => '记账',
    'payment' => '收款',
    'discount' => '抹零',
    _ => throw FormatException('未知流水类型：$kind'),
  };

  static String _displayDate(String value) {
    final parts = value.split('-');
    if (parts.length != 3) return value;
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (month == null || day == null) return value;
    return '${parts[0]}/$month/$day';
  }

  static String _chineseDate(DateTime value) =>
      '${value.year}年${value.month}月${value.day}日';

  static String _generatedTime(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${_chineseDate(value)} ${two(value.hour)}:${two(value.minute)}';
  }
}
