import 'package:flutter/material.dart';

import '../../deck/theme.dart';
import '../model.dart';

/// Top-left: the factory's name sign, what's being built, and who's next.
class BoothBoard extends StatelessWidget {
  const BoothBoard({super.key, required this.model});

  final BoothModel model;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final j = model.job;
        final p = j == null ? 0.0 : (j.total == 0 ? 0.0 : j.laid(model.t) / j.total);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '名前工場 · Name Factory',
              style: BT.sample(40, weight: 600).copyWith(locale: const Locale('ja')),
            ),
            const SizedBox(height: 10),
            if (j != null) ...[
              Text(
                j.sample ? 'Building · 建設中' : 'Now building for · 建設中',
                style: BT.mono(18, color: BP.inkDim),
              ),
              Text(
                j.name,
                style: BT
                    .sample(48, color: BP.amber, weight: 600)
                    .copyWith(locale: const Locale('ja')),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 420,
                child: LinearProgressIndicator(
                  value: p,
                  color: BP.amber,
                  backgroundColor: BP.lineFaint,
                  minHeight: 6,
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (model.queue.isNotEmpty)
              Text(
                'Next · 次: ${model.queue.take(4).map((q) => q.name).join(' · ')}${model.queue.length > 4 ? ' +${model.queue.length - 4}' : ''}',
                style: BT.sample(22, color: BP.inkDim).copyWith(locale: const Locale('ja')),
              ),
          ],
        );
      },
    );
  }
}
