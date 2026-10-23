// Compiles a dart2wasm-generated main module from `source` which can then
// be instantiated via the `instantiate` method.
//
// `source` needs to be a `Response` object (or promise thereof) e.g. created
// via the `fetch()` JS API.
export async function compileStreaming(source) {
  const builtins = {builtins: ['js-string']};
  return new CompiledApp(
      await WebAssembly.compileStreaming(source, builtins), builtins);
}

// Compiles a dart2wasm-generated wasm module from `bytes` which is then
// instantiable via the `instantiate` method.
export async function compile(bytes) {
  const builtins = {builtins: ['js-string']};
  return new CompiledApp(await WebAssembly.compile(bytes, builtins), builtins);
}

class CompiledApp {
  constructor(module, builtins) {
    this.module = module;
    this.builtins = builtins;
  }

  // The second argument is an options object containing:
  // `loadDeferredModules` is a JS function that takes an array of module names
  //   matching wasm files produced by the dart2wasm compiler. It also takes a
  //   callback that should be invoked for each loaded module with 2 arguments:
  //   (1) the module name, (2) the loaded module in a format supported by
  //   `WebAssembly.compile` or `WebAssembly.compileStreaming`. The callback
  //   returns a Promise that resolves when the module is instantiated.
  //   loadDeferredModules should return a Promise that resolves when all the
  //   modules have been loaded and the callback promises have resolved.
  // `loadDeferredId` is a JS function that takes load ID produced by the
  //   compiler when the `use-load-ids` option is passed. Each load ID maps to
  //   one or more wasm files as specified in the emitted JSON file. It also
  //   takes a callback that should be invoked for each loaded module with 2
  //   arguments: (1) the module name, (2) the loaded module in a format
  //   supported by `WebAssembly.compile` or `WebAssembly.compileStreaming`.
  //   The callback returns a Promise that resolves when the module is
  //   instantiated.
  //   loadDeferredId should return a Promise that resolves when all the
  //   modules have been loaded and the callback promises have resolved.
  async instantiate(additionalImports, {loadDeferredModules, loadDeferredId} = {}) {
    let dartInstance;

    // Prints to the console
    function printToConsole(value) {
      if (typeof dartPrint == "function") {
        dartPrint(value);
        return;
      }
      if (typeof console == "object" && typeof console.log != "undefined") {
        console.log(value);
        return;
      }
      if (typeof print == "function") {
        print(value);
        return;
      }

      throw "Unable to print message: " + value;
    }

    // A special symbol attached to functions that wrap Dart functions.
    const jsWrappedDartFunctionSymbol = Symbol("JSWrappedDartFunction");

    function finalizeWrapper(dartFunction, wrapped) {
      wrapped.dartFunction = dartFunction;
      wrapped[jsWrappedDartFunctionSymbol] = true;
      return wrapped;
    }

    // Imports
    const dart2wasm = {
            AB: (decoder, codeUnits) => decoder.decode(codeUnits),
      AC: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Float64Array) return 1;
        return 2;
      },
      AD: (x0,x1) => x0.go(x1),
      AE: (x0,x1) => x0.removeProperty(x1),
      AF: (x0,x1) => { x0.noValidate = x1 },
      AG: x0 => x0.offsetY,
      AH: x0 => x0.height,
      AI: (a, l) => a.length = l,
      AJ: x0 => x0.read(),
      B: s => printToConsole(s),
      BB: (o, start, length) => new Uint8Array(o.buffer, o.byteOffset + start, length),
      BC: (t, s) => t.set(s),
      BD: (x0,x1) => x0.append(x1),
      BE: (x0,x1) => x0.appendChild(x1),
      BF: (x0,x1) => x0.removeAttribute(x1),
      BG: x0 => x0.offsetX,
      BH: x0 => x0.clientHeight,
      BI: x0 => new WeakRef(x0),
      BJ: x0 => x0.body,
      C: Function.prototype.call.bind(Number.prototype.toString),
      CB: () => new TextDecoder("utf-8", {fatal: true}),
      CC: Function.prototype.call.bind(DataView.prototype.setFloat32),
      CD: (x0,x1) => { x0.textContent = x1 },
      CE: x0 => x0.debugShowSemanticsNodes,
      CF: x0 => x0.isConnected,
      CG: x0 => x0.type,
      CH: x0 => x0.innerWidth,
      CI: x0 => x0.deref(),
      CJ: x0 => x0.assetBase,
      D: Function.prototype.call.bind(BigInt.prototype.toString),
      DB: () => new TextDecoder("utf-8", {fatal: false}),
      DC: Function.prototype.call.bind(DataView.prototype.getFloat32),
      DD: (ms, c) =>
      setTimeout(() => dartInstance.exports.$invokeCallback(c),ms),
      DE: (o, c) => o instanceof c,
      DF: x0 => x0.click(),
      DG: x0 => x0.hasFocus(),
      DH: x0 => x0.width,
      DI: () => globalThis.WeakRef,
      DJ: x0 => x0.loader,
      E: (exn) => {
        let stackString = exn.toString();
        let frames = stackString.split('\n');
        let drop = 4;
        if (frames[0].startsWith('Error')) {
            drop += 1;
        }
        return frames.slice(drop).join('\n');
      },
      EB: (a, i) => a.push(i),
      EC: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Float32Array) return 1;
        return 2;
      },
      ED: x0 => x0.parentElement,
      EE: x0 => x0.vendor,
      EF: (x0,x1) => x0.getElementsByClassName(x1),
      EG: x0 => x0.shiftKey,
      EH: x0 => x0.clientWidth,
      EI: (o, offsetInBytes, lengthInBytes) => {
        var dst = new ArrayBuffer(lengthInBytes);
        new Uint8Array(dst).set(new Uint8Array(o, offsetInBytes, lengthInBytes));
        return new DataView(dst);
      },
      EJ: () => globalThis._flutter,
      F: () => new Error().stack,
      FB: (l, r) => l === r,
      FC: Function.prototype.call.bind(DataView.prototype.getUint32),
      FD: (x0,x1) => x0.querySelectorAll(x1),
      FE: (x0,x1) => x0.createTextNode(x1),
      FF: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      FG: x0 => x0.visibilityState,
      FH: (x0,x1) => x0.removeChild(x1),
      FI: (a, s, e) => a.slice(s, e),
      G: s => JSON.stringify(s),
      GB: x0 => x0.random(),
      GC: Function.prototype.call.bind(DataView.prototype.setUint32),
      GD: (x0,x1) => x0.item(x1),
      GE: (x0,x1) => { x0.nonce = x1 },
      GF: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF64ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      GG: x0 => x0.disconnect(),
      GH: x0 => x0.firstChild,
      GI: (x0,x1,x2,x3) => x0.putImageData(x1,x2,x3),
      H: Function.prototype.call.bind(Number.prototype.toString),
      HB: () => globalThis.Math,
      HC: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint32Array) return 1;
        return 2;
      },
      HD: x0 => x0.length,
      HE: x0 => x0.nonce,
      HF: (x0,x1) => x0.contains(x1),
      HG: x0 => new Intl.Locale(x0),
      HH: x0 => x0.viewConstraints,
      HI: x0 => x0.arrayBuffer(),
      I: Function.prototype.call.bind(String.prototype.indexOf),
      IB: s => s.toUpperCase(),
      IC: Function.prototype.call.bind(DataView.prototype.getInt32),
      ID: x0 => x0.userAgent,
      IE: () => globalThis.window.flutterConfiguration,
      IF: (s) => +s,
      IG: x0 => x0.region,
      IH: x0 => x0.hostElement,
      II: (x0,x1) => x0.transferFromImageBitmap(x1),
      J: (s, p, i) => s.lastIndexOf(p, i),
      JB: Object.is,
      JC: Function.prototype.call.bind(DataView.prototype.setInt32),
      JD: x0 => x0.maxTouchPoints,
      JE: (x0,x1) => x0.attachShadow(x1),
      JF: x0 => x0.target,
      JG: x0 => x0.script,
      JH: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      JI: x0 => x0.height,
      K: (exn) => {
        if (exn instanceof Error) {
          return exn.stack;
        } else {
          return null;
        }
      },
      KB: (x0,x1) => x0.test(x1),
      KC: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int32Array) return 1;
        return 2;
      },
      KD: x0 => x0.platform,
      KE: x0 => x0.preventDefault(),
      KF: (x0,x1) => x0.dispatchEvent(x1),
      KG: x0 => x0.language,
      KH: x0 => ({runApp: x0}),
      KI: x0 => x0.width,
      L: o => o === undefined,
      LB: x0 => x0.index,
      LC: o => o instanceof Uint16Array,
      LD: x0 => x0.navigator,
      LE: (x0,x1) => x0.contains(x1),
      LF: (x0,x1) => x0.createEvent(x1),
      LG: x0 => x0.languages,
      LH: Function.prototype.call.bind(DataView.prototype.setBigInt64),
      LI: x0 => x0.rasterEndMilliseconds,
      M: o => String(o),
      MB: (x0,x1) => x0[x1],
      MC: Function.prototype.call.bind(DataView.prototype.getUint16),
      MD: s => new Date(s * 1000).getTimezoneOffset() * 60,
      ME: (x0,x1) => x0.focus(x1),
      MF: (x0,x1,x2,x3) => x0.initEvent(x1,x2,x3),
      MG: (x0,x1) => x0.observe(x1),
      MH: Function.prototype.call.bind(DataView.prototype.getBigInt64),
      MI: x0 => x0.rasterStartMilliseconds,
      N: (c) =>
      queueMicrotask(() => dartInstance.exports.$invokeCallback(c)),
      NB: x0 => x0.flags,
      NC: Function.prototype.call.bind(DataView.prototype.setUint16),
      ND: Date.now,
      NE: (x0,x1) => x0.closest(x1),
      NF: () => globalThis.window,
      NG: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      NH: (o, start, length) => new BigInt64Array(o.buffer, o.byteOffset + start, length),
      NI: x0 => x0.imageBitmaps,
      O: (x0,x1) => x0.didCreateEngineInitializer(x1),
      OB: (a, i, v) => a[i] = v,
      OC: o => o instanceof Int16Array,
      OD: (x0,x1,x2) => x0.setAttribute(x1,x2),
      OE: (x0,x1) => x0.getAttribute(x1),
      OF: x0 => x0.readText(),
      OG: x0 => new ResizeObserver(x0),
      OH: () => typeof dartUseDateNowForTicks !== "undefined",
      OI: (x0,x1) => { x0.height = x1 },
      P: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      PB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI8ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      PC: Function.prototype.call.bind(DataView.prototype.getInt16),
      PD: (x0,x1,x2,x3) => x0.setProperty(x1,x2,x3),
      PE: x0 => x0.activeElement,
      PF: x0 => x0.clipboard,
      PG: x0 => globalThis.parseFloat(x0),
      PH: () => Date.now(),
      PI: (x0,x1) => { x0.width = x1 },
      Q: (wasmFunction,f) => finalizeWrapper(f, function() { return wasmFunction(f,arguments.length) }),
      QB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI16ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      QC: Function.prototype.call.bind(DataView.prototype.setInt16),
      QD: x0 => x0.style,
      QE: (x0,x1) => x0.add(x1),
      QF: (x0,x1) => x0.writeText(x1),
      QG: (x0,x1) => x0.getComputedStyle(x1),
      QH: () => 1000 * performance.now(),
      QI: x0 => x0.convertToBlob(),
      R: (x0,x1) => ({initializeEngine: x0,autoStart: x1}),
      RB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      RC: o => o instanceof Uint8ClampedArray,
      RD: (x0,x1) => x0.createElement(x1),
      RE: x0 => x0.classList,
      RF: x0 => x0.unlock(),
      RG: x0 => x0.documentElement,
      RH: x0 => new Uint8Array(x0),
      RI: (x0,x1,x2) => new ImageData(x0,x1,x2),
      S: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      SB: Function.prototype.call.bind(String.prototype.toLowerCase),
      SC: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint8Array) return 1;
        return 2;
      },
      SD: x0 => x0.body,
      SE: x0 => x0.data,
      SF: (x0,x1) => x0.lock(x1),
      SG: x0 => x0.computedStyleMap(),
      SH: (x0,x1,x2) => x0.slice(x1,x2),
      SI: (x0,x1) => x0.getContext(x1),
      T: x0 => new Promise(x0),
      TB: (x0,x1,x2,x3) => x0.pushState(x1,x2,x3),
      TC: Function.prototype.call.bind(DataView.prototype.setInt8),
      TD: x0 => x0.remove(),
      TE: x0 => x0.scrollTop,
      TF: x0 => x0.orientation,
      TG: (x0,x1) => x0.get(x1),
      TH: (x0,x1) => x0.decode(x1),
      TI: (x0,x1) => new OffscreenCanvas(x0,x1),
      U: (x0,x1,x2) => x0.call(x1,x2),
      UB: () => ({}),
      UC: Function.prototype.call.bind(DataView.prototype.getInt8),
      UD: (x0,x1) => x0.getPropertyValue(x1),
      UE: (handle) => clearTimeout(handle),
      UF: (x0,x1) => x0.querySelector(x1),
      UG: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      UH: (x0,x1) => x0.adoptText(x1),
      UI: (a, l) => a.length = l,
      V: (constructor, args) => {
        const factoryFunction = constructor.bind.apply(
            constructor, [null, ...args]);
        return new factoryFunction();
      },
      VB: (o, p, v) => o[p] = v,
      VC: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int8Array) return 1;
        return 2;
      },
      VD: (x0,x1) => x0.warn(x1),
      VE: (x0,x1) => { x0.scrollTop = x1 },
      VF: (x0,x1) => { x0.content = x1 },
      VG: x0 => x0.matches,
      VH: x0 => x0.first(),
      VI: (x0,x1,x2) => x0.insertBefore(x1,x2),
      W: x0 => new Array(x0),
      WB: () => [],
      WC: (o, start, length) => new Float64Array(o.buffer, o.byteOffset + start, length),
      WD: x0 => x0.console,
      WE: x0 => x0.tagName,
      WF: x0 => x0.head,
      WG: (x0,x1) => x0.matchMedia(x1),
      WH: x0 => x0.next(),
      WI: x0 => x0.id,
      X: o => [o],
      XB: b => !!b,
      XC: (o, start, length) => new Float32Array(o.buffer, o.byteOffset + start, length),
      XD: (x0,x1) => { x0.id = x1 },
      XE: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      XF: (x0,x1) => { x0.name = x1 },
      XG: x0 => x0.matches,
      XH: x0 => x0.current(),
      XI: x0 => x0.offsetHeight,
      Y: (o0, o1) => [o0, o1],
      YB: x0 => new Int8Array(x0),
      YC: (o, start, length) => new Uint32Array(o.buffer, o.byteOffset + start, length),
      YD: s => s.trimLeft(),
      YE: (x0,x1) => { x0.value = x1 },
      YF: (x0,x1) => { x0.title = x1 },
      YG: x0 => x0.timeStamp,
      YH: (x0,x1) => new Intl.v8BreakIterator(x0,x1),
      YI: x0 => x0.offsetWidth,
      Z: (o0, o1, o2) => [o0, o1, o2],
      ZB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI8ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      ZC: (o, start, length) => new Int32Array(o.buffer, o.byteOffset + start, length),
      ZD: (o, p, r) => o.replace(p, () => r),
      ZE: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      ZF: () => globalThis.document,
      ZG: (x0,x1) => x0.hasAttribute(x1),
      ZH: x0 => x0.v8BreakIterator,
      ZI: x0 => x0.stopPropagation(),
      a: (o0, o1, o2, o3) => [o0, o1, o2, o3],
      aB: x0 => new Uint8Array(x0),
      aC: (o, start, length) => new Uint16Array(o.buffer, o.byteOffset + start, length),
      aD: (o, p, r) => o.replaceAll(p, () => r),
      aE: (x0,x1) => { x0.value = x1 },
      aF: (x0,x1) => x0.vibrate(x1),
      aG: x0 => x0.buttons,
      aH: () => globalThis.Intl,
      aI: x0 => x0.disabled,
      b: (x0,x1,x2) => { x0[x1] = x2 },
      bB: x0 => new Uint8ClampedArray(x0),
      bC: (o, start, length) => new Int16Array(o.buffer, o.byteOffset + start, length),
      bD: s => s.trim(),
      bE: x0 => x0.relatedTarget,
      bF: (o, p) => p in o,
      bG: x0 => x0.ctrlKey,
      bH: (x0,x1) => x0.segment(x1),
      bI: (x0,x1) => { x0.min = x1 },
      c: o => o,
      cB: x0 => new Int16Array(x0),
      cC: (o, start, length) => new Uint8ClampedArray(o.buffer, o.byteOffset + start, length),
      cD: (a, s) => a.join(s),
      cE: s => {
        if (/[[\]{}()*+?.\\^$|]/.test(s)) {
            s = s.replace(/[[\]{}()*+?.\\^$|]/g, '\\$&');
        }
        return s;
      },
      cF: x0 => x0.arrayBuffer(),
      cG: x0 => x0.y,
      cH: x0 => x0.index,
      cI: (x0,x1) => { x0.max = x1 },
      d: (o, p) => o[p],
      dB: x0 => new Uint16Array(x0),
      dC: (o, start, length) => new Int8Array(o.buffer, o.byteOffset + start, length),
      dD: (x0,x1) => x0.error(x1),
      dE: x0 => x0.value,
      dF: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof ArrayBuffer) return 1;
        if (globalThis.SharedArrayBuffer !== undefined &&
            o instanceof SharedArrayBuffer) {
          return 2;
        }
        return 3;
      },
      dG: x0 => x0.x,
      dH: x0 => x0.next(),
      dI: (x0,x1) => { x0.disabled = x1 },
      e: () => globalThis,
      eB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI16ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      eC: x0 => x0.history,
      eD: () => globalThis.console,
      eE: x0 => x0.selectionDirection,
      eF: x0 => x0.status,
      eG: x0 => x0.offsetTop,
      eH: x0 => x0.value,
      eI: (x0,x1) => { x0.scrollLeft = x1 },
      f: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      fB: x0 => new Int32Array(x0),
      fC: x0 => x0.search,
      fD: s => s.trimRight(),
      fE: x0 => x0.selectionStart,
      fF: (x0,x1) => x0.fetch(x1),
      fG: x0 => x0.scrollLeft,
      fH: x0 => x0.done,
      fI: (x0,x1) => { x0.spellcheck = x1 },
      g: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      gB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      gC: o => {
        if (o === null || o === undefined) return 0;
        if (typeof(o) === 'string') return 1;
        return 2;
      },
      gD: (x0,x1) => x0.requestAnimationFrame(x1),
      gE: x0 => x0.selectionEnd,
      gF: x0 => x0.content,
      gG: x0 => x0.offsetLeft,
      gH: (o, m, a) => o[m].apply(o, a),
      gI: (x0,x1) => { x0.disabled = x1 },
      h: (x0,x1) => ({addView: x0,removeView: x1}),
      hB: x0 => new Uint32Array(x0),
      hC: x0 => x0.location,
      hD: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      hE: x0 => x0.value,
      hF: x0 => x0.document,
      hG: x0 => x0.offsetParent,
      hH: x0 => x0.iterator,
      hI: (x0,x1) => x0.getContext(x1),
      i: (x0,x1) => x0.exec(x1),
      iB: x0 => new Float32Array(x0),
      iC: x0 => x0.pathname,
      iD: x0 => x0.now(),
      iE: x0 => x0.selectionDirection,
      iF: x0 => x0.language,
      iG: x0 => x0.deltaMode,
      iH: () => globalThis.Symbol,
      iI: (x0,x1) => { x0.height = x1 },
      j: x0 => x0.length,
      jB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      jC: (x0,x1,x2,x3) => x0.replaceState(x1,x2,x3),
      jD: x0 => x0.performance,
      jE: x0 => x0.selectionStart,
      jF: (x0,x1,x2,x3) => x0.register(x1,x2,x3),
      jG: x0 => x0.deltaY,
      jH: (x0,x1) => new Intl.Segmenter(x0,x1),
      jI: (x0,x1) => { x0.width = x1 },
      k: o => o,
      kB: x0 => new Float64Array(x0),
      kC: o => {
        const proto = Object.getPrototypeOf(o);
        return proto === Object.prototype || proto === null;
      },
      kD: (x0,x1) => x0.unregister(x1),
      kE: x0 => x0.selectionEnd,
      kF: (x0,x1) => x0.prepend(x1),
      kG: x0 => x0.deltaX,
      kH: x0 => x0.Segmenter,
      kI: x0 => x0.canvasKitMaximumSurfaces,
      l: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'number') return 1;
        return 2;
      },
      lB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF64ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      lC: o => Object.keys(o),
      lD: () => globalThis.window.FinalizationRegistry,
      lE: x0 => x0.keyCode,
      lF: (x0,x1,x2,x3) => x0.addEventListener(x1,x2,x3),
      lG: x0 => x0.wheelDeltaY,
      lH: x0 => x0.buffer,
      lI: () => {
        // On browsers return `globalThis.location.href`
        if (globalThis.location != null) {
          return globalThis.location.href;
        }
        return null;
      },
      m: (x0,x1) => { x0.lastIndex = x1 },
      mB: x0 => new ArrayBuffer(x0),
      mC: o => typeof o === 'function' && o[jsWrappedDartFunctionSymbol] === true,
      mD: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      mE: (x0,x1) => x0.scrollIntoView(x1),
      mF: (x0,x1) => x0.querySelector(x1),
      mG: x0 => x0.wheelDeltaX,
      mH: x0 => x0.wasmMemory,
      mI: x0 => x0.hostElement,
      n: (s, m) => {
        try {
          return new RegExp(s, m);
        } catch (e) {
          return String(e);
        }
      },
      nB: (x0,x1,x2) => new Uint8Array(x0,x1,x2),
      nC: f => f.dartFunction,
      nD: x0 => new window.FinalizationRegistry(x0),
      nE: x0 => x0.multiViewEnabled,
      nF: (x0,x1) => x0.querySelectorAll(x1),
      nG: x0 => x0.key,
      nH: () => globalThis.window._flutter_skwasmInstance,
      nI: x0 => x0.location,
      o: o => o instanceof RegExp,
      oB: (x0,x1,x2) => new DataView(x0,x1,x2),
      oC: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      oD: x0 => x0.scale,
      oE: x0 => x0.parent,
      oF: x0 => x0.tabIndex,
      oG: x0 => x0.identifier,
      oH: () => new TextDecoder(),
      oI: (x0,x1) => x0.getModifierState(x1),
      p: o => o,
      pB: (o, p) => o[p],
      pC: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      pD: x0 => x0.visualViewport,
      pE: (x0,x1) => x0.replaceWith(x1),
      pF: x0 => x0.parentNode,
      pG: x0 => x0.touches,
      pH: (a, i) => a.splice(i, 1),
      pI: x0 => x0.metaKey,
      q: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'boolean') return 1;
        return 2;
      },
      qB: (o) => new DataView(o.buffer, o.byteOffset, o.byteLength),
      qC: (p, s, f) => p.then(s, (e) => f(e, e === undefined)),
      qD: x0 => x0.devicePixelRatio,
      qE: (x0,x1) => { x0.type = x1 },
      qF: x0 => x0.clientY,
      qG: x0 => x0.pressure,
      qH: a => a.pop(),
      qI: x0 => x0.altKey,
      r: x0 => x0.dotAll,
      rB: Function.prototype.call.bind(Object.getOwnPropertyDescriptor(DataView.prototype, 'byteLength').get),
      rC: (o, i) => o[i],
      rD: (d, digits) => d.toFixed(digits),
      rE: (x0,x1) => { x0.className = x1 },
      rF: x0 => x0.clientX,
      rG: x0 => x0.tiltY,
      rH: (map, o, v) => map.set(o, v),
      rI: x0 => x0.ctrlKey,
      s: x0 => x0.unicode,
      sB: Function.prototype.call.bind(DataView.prototype.setFloat64),
      sC: o => o.length,
      sD: x0 => x0.maxHeight,
      sE: (x0,x1) => { x0.tabIndex = x1 },
      sF: x0 => x0.getBoundingClientRect(),
      sG: x0 => x0.tiltX,
      sH: (map, o) => map.get(o),
      sI: x0 => x0.isComposing,
      t: x0 => x0.ignoreCase,
      tB: o => o.byteOffset,
      tC: o => {
        if (o === undefined) return 1;
        var type = typeof o;
        if (type === 'boolean') return 2;
        if (type === 'number') return 3;
        if (type === 'string') return 4;
        if (o instanceof Array) return 5;
        if (ArrayBuffer.isView(o)) {
          if (o instanceof Int8Array) return 6;
          if (o instanceof Uint8Array) return 7;
          if (o instanceof Uint8ClampedArray) return 8;
          if (o instanceof Int16Array) return 9;
          if (o instanceof Uint16Array) return 10;
          if (o instanceof Int32Array) return 11;
          if (o instanceof Uint32Array) return 12;
          if (o instanceof Float32Array) return 13;
          if (o instanceof Float64Array) return 14;
          if (o instanceof DataView) return 15;
        }
        if (o instanceof ArrayBuffer) return 16;
        // Feature check for `SharedArrayBuffer` before doing a type-check.
        if (globalThis.SharedArrayBuffer !== undefined &&
            o instanceof SharedArrayBuffer) {
            return 17;
        }
        if (o instanceof Promise) return 18;
        return 19;
      },
      tD: x0 => x0.maxWidth,
      tE: (x0,x1) => { x0.name = x1 },
      tF: x0 => x0.bottom,
      tG: x0 => x0.pointerType,
      tH: () => new WeakMap(),
      tI: x0 => x0.code,
      u: x0 => x0.multiline,
      uB: o => o.buffer,
      uC: x0 => x0.state,
      uD: x0 => x0.minHeight,
      uE: (x0,x1) => { x0.placeholder = x1 },
      uF: x0 => x0.top,
      uG: x0 => x0.pointerId,
      uH: x0 => x0.debugSkipFontRetryDelay,
      uI: x0 => x0.repeat,
      v: (string, token) => string.split(token),
      vB: (b, o) => new DataView(b, o),
      vC: x0 => x0.hash,
      vD: x0 => x0.minWidth,
      vE: (x0,x1) => { x0.autocomplete = x1 },
      vF: x0 => x0.right,
      vG: x0 => x0.getCoalescedEvents(),
      vH: (x0,x1,x2) => x0.set(x1,x2),
      vI: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      w: o => o instanceof Array,
      wB: (b, o, l) => new DataView(b, o, l),
      wC: (x0,x1,x2) => x0.removeEventListener(x1,x2),
      wD: x0 => x0.height,
      wE: (x0,x1) => { x0.name = x1 },
      wF: x0 => x0.left,
      wG: (x0,x1) => x0.getModifierState(x1),
      wH: x0 => x0.fontFallbackBaseUrl,
      wI: x0 => x0.length,
      x: (a, i) => a[i],
      xB: Function.prototype.call.bind(DataView.prototype.getUint8),
      xC: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      xD: x0 => x0.width,
      xE: (x0,x1) => { x0.placeholder = x1 },
      xF: x0 => x0.clientY,
      xG: x0 => x0.blur(),
      xH: (handle) => clearInterval(handle),
      xI: x0 => x0.getReader(),
      y: a => a.length,
      yB: Function.prototype.call.bind(DataView.prototype.setUint8),
      yC: x0 => x0.state,
      yD: x0 => x0.screen,
      yE: (x0,x1) => { x0.action = x1 },
      yF: x0 => x0.clientX,
      yG: x0 => x0.button,
      yH: (ms, c) =>
      setInterval(() => dartInstance.exports.$invokeCallback(c), ms),
      yI: x0 => x0.value,
      z: (string, times) => string.repeat(times),
      zB: Function.prototype.call.bind(DataView.prototype.getFloat64),
      zC: (x0,x1,x2) => x0.addEventListener(x1,x2),
      zD: s => {
        if (!/^\s*[+-]?(?:Infinity|NaN|(?:\.\d+|\d+(?:\.\d*)?)(?:[eE][+-]?\d+)?)\s*$/.test(s)) {
          return NaN;
        }
        return parseFloat(s);
      },
      zE: (x0,x1) => { x0.method = x1 },
      zF: x0 => x0.changedTouches,
      zG: x0 => x0.innerHeight,
      zH: () => Date.now(),
      zI: x0 => x0.done,

    };

    const baseImports = {
      _: dart2wasm,
      Math: Math,
      Date: Date,
      Object: Object,
      Array: Array,
      Reflect: Reflect,
      WebAssembly: {
        JSTag: WebAssembly.JSTag,
      },
      "": new Proxy({}, { get(_, prop) { return prop; } }),

    };

    const jsStringPolyfill = {
      "charCodeAt": (s, i) => s.charCodeAt(i),
      "compare": (s1, s2) => {
        if (s1 < s2) return -1;
        if (s1 > s2) return 1;
        return 0;
      },
      "concat": (s1, s2) => s1 + s2,
      "equals": (s1, s2) => s1 === s2,
      "fromCharCode": (i) => String.fromCharCode(i),
      "length": (s) => s.length,
      "substring": (s, a, b) => s.substring(a, b),
      "fromCharCodeArray": (a, start, end) => {
        if (end <= start) return '';

        const read = dartInstance.exports.$wasmI16ArrayGet;
        let result = '';
        let index = start;
        const chunkLength = Math.min(end - index, 500);
        let array = new Array(chunkLength);
        while (index < end) {
          const newChunkLength = Math.min(end - index, 500);
          for (let i = 0; i < newChunkLength; i++) {
            array[i] = read(a, index++);
          }
          if (newChunkLength < chunkLength) {
            array = array.slice(0, newChunkLength);
          }
          result += String.fromCharCode(...array);
        }
        return result;
      },
      "intoCharCodeArray": (s, a, start) => {
        if (s === '') return 0;

        const write = dartInstance.exports.$wasmI16ArraySet;
        for (var i = 0; i < s.length; ++i) {
          write(a, start++, s.charCodeAt(i));
        }
        return s.length;
      },
      "test": (s) => typeof s == "string",
    };


    

    dartInstance = await WebAssembly.instantiate(this.module, {
      ...baseImports,
      ...additionalImports,
      
      "wasm:js-string": jsStringPolyfill,
    });

    return new InstantiatedApp(this, dartInstance);
  }
}

class InstantiatedApp {
  constructor(compiledApp, instantiatedModule) {
    this.compiledApp = compiledApp;
    this.instantiatedModule = instantiatedModule;
  }

  // Call the main function with the given arguments.
  invokeMain(...args) {
    this.instantiatedModule.exports.$invokeMain(args);
  }
}
