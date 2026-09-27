import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/services.dart';

import 'chars.dart';

/// A [SelectionArea] whose copy (keyboard shortcut and context menu) removes
/// the U+2060 WORD JOINERs that [KumihanText] inserts.
///
/// Text fields inside the area keep their own copy behaviour.
class KumihanSelectionArea extends StatefulWidget {
  const KumihanSelectionArea({
    super.key,
    required this.child,
    this.focusNode,
    this.selectionControls,
    this.magnifierConfiguration,
    this.onSelectionChanged,
  });

  final Widget child;
  final FocusNode? focusNode;
  final TextSelectionControls? selectionControls;
  final TextMagnifierConfiguration? magnifierConfiguration;
  final ValueChanged<SelectedContent?>? onSelectionChanged;

  @override
  State<KumihanSelectionArea> createState() => _KumihanSelectionAreaState();
}

class _KumihanSelectionAreaState extends State<KumihanSelectionArea> {
  SelectedContent? _content;

  Future<void> _copy() async {
    final text = _content?.plainText;
    if (text == null || text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: stripWordJoiners(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: {CopySelectionTextIntent: _StrippingCopyAction(this)},
      child: SelectionArea(
        focusNode: widget.focusNode,
        selectionControls: widget.selectionControls,
        magnifierConfiguration: widget.magnifierConfiguration,
        onSelectionChanged: (content) {
          _content = content;
          widget.onSelectionChanged?.call(content);
        },
        contextMenuBuilder: (context, state) {
          final items = [
            for (final item in state.contextMenuButtonItems)
              if (item.type == ContextMenuButtonType.copy)
                item.copyWith(
                  onPressed: () {
                    _copy();
                    state.hideToolbar();
                  },
                )
              else
                item,
          ];
          return AdaptiveTextSelectionToolbar.buttonItems(
            anchors: state.contextMenuAnchors,
            buttonItems: items,
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// Overrides the [SelectableRegion]'s copy shortcut; defers to the default
/// action (e.g. an [EditableText]'s) when a text field has focus.
class _StrippingCopyAction extends Action<CopySelectionTextIntent> {
  _StrippingCopyAction(this._state);

  final _KumihanSelectionAreaState _state;

  @override
  Object? invoke(CopySelectionTextIntent intent) {
    final focus = FocusManager.instance.primaryFocus?.context;
    final inField = focus != null &&
        (focus.widget is EditableText || focus.findAncestorWidgetOfExactType<EditableText>() != null);
    if (inField || _state._content == null) {
      return callingAction?.invoke(intent);
    }
    return _state._copy();
  }
}
