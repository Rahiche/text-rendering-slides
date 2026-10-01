import 'dart:js_interop';

/// The page's loading screen (web/index.html): `window.nameCityLoading`.
extension type _PageLoading._(JSObject _) implements JSObject {
  external void stage(String text);
  external void done();
}

@JS('nameCityLoading')
external _PageLoading? get _page;

/// Shows [text] as what's being got ready, under the page's loading screen.
void pageLoadingStage(String text) => _page?.stage(text);

/// Lifts the page's loading screen.
void pageLoadingDone() => _page?.done();
