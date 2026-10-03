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
      AE: s => {
        if (!/^\s*[+-]?(?:Infinity|NaN|(?:\.\d+|\d+(?:\.\d*)?)(?:[eE][+-]?\d+)?)\s*$/.test(s)) {
          return NaN;
        }
        return parseFloat(s);
      },
      AF: (x0,x1) => { x0.method = x1 },
      AG: x0 => x0.changedTouches,
      AH: x0 => x0.innerHeight,
      AI: () => Date.now(),
      AJ: x0 => x0.createRenderbuffer(),
      AK: x0 => x0.createVertexArray(),
      AL: x0 => x0.length,
      B: s => printToConsole(s),
      BB: (o, start, length) => new Uint8Array(o.buffer, o.byteOffset + start, length),
      BC: (t, s) => t.set(s),
      BD: (x0,x1) => x0.append(x1),
      BE: (x0,x1) => x0.removeProperty(x1),
      BF: (x0,x1) => { x0.noValidate = x1 },
      BG: x0 => x0.offsetY,
      BH: x0 => x0.height,
      BI: x0 => x0.close(),
      BJ: (x0,x1,x2) => x0.bindRenderbuffer(x1,x2),
      BK: (x0,x1) => x0.deleteVertexArray(x1),
      BL: x0 => x0.getReader(),
      C: Function.prototype.call.bind(Number.prototype.toString),
      CB: () => new TextDecoder("utf-8", {fatal: true}),
      CC: Function.prototype.call.bind(DataView.prototype.setFloat32),
      CD: (x0,x1) => { x0.textContent = x1 },
      CE: (x0,x1) => x0.appendChild(x1),
      CF: (x0,x1) => x0.removeAttribute(x1),
      CG: x0 => x0.offsetX,
      CH: x0 => x0.clientHeight,
      CI: x0 => new WeakRef(x0),
      CJ: (x0,x1,x2,x3,x4,x5) => x0.renderbufferStorageMultisample(x1,x2,x3,x4,x5),
      CK: (x0,x1,x2) => x0.vertexAttribDivisor(x1,x2),
      CL: x0 => x0.value,
      D: Function.prototype.call.bind(BigInt.prototype.toString),
      DB: () => new TextDecoder("utf-8", {fatal: false}),
      DC: Function.prototype.call.bind(DataView.prototype.getFloat32),
      DD: (ms, c) =>
      setTimeout(() => dartInstance.exports.$invokeCallback(c),ms),
      DE: x0 => x0.debugShowSemanticsNodes,
      DF: x0 => x0.isConnected,
      DG: x0 => x0.type,
      DH: x0 => x0.innerWidth,
      DI: x0 => x0.deref(),
      DJ: (a, i) => a.splice(i, 1)[0],
      DK: (x0,x1) => x0.enable(x1),
      DL: x0 => x0.done,
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
      EE: (o, c) => o instanceof c,
      EF: x0 => x0.click(),
      EG: x0 => x0.hasFocus(),
      EH: x0 => x0.width,
      EI: () => globalThis.WeakRef,
      EJ: x0 => x0.createFramebuffer(),
      EK: (x0,x1) => x0.cullFace(x1),
      EL: x0 => x0.read(),
      F: () => new Error().stack,
      FB: (l, r) => l === r,
      FC: Function.prototype.call.bind(DataView.prototype.getUint32),
      FD: (x0,x1) => x0.querySelectorAll(x1),
      FE: x0 => x0.vendor,
      FF: (x0,x1) => x0.getElementsByClassName(x1),
      FG: x0 => x0.shiftKey,
      FH: x0 => x0.clientWidth,
      FI: (o, offsetInBytes, lengthInBytes) => {
        var dst = new ArrayBuffer(lengthInBytes);
        new Uint8Array(dst).set(new Uint8Array(o, offsetInBytes, lengthInBytes));
        return new DataView(dst);
      },
      FJ: (x0,x1,x2) => x0.bindFramebuffer(x1,x2),
      FK: x0 => globalThis.WebAssembly.instantiate(x0),
      FL: x0 => x0.body,
      G: s => JSON.stringify(s),
      GB: x0 => x0.random(),
      GC: Function.prototype.call.bind(DataView.prototype.setUint32),
      GD: x0 => x0.length,
      GE: (x0,x1) => x0.createTextNode(x1),
      GF: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      GG: x0 => x0.visibilityState,
      GH: (x0,x1) => x0.removeChild(x1),
      GI: (a, s, e) => a.slice(s, e),
      GJ: (x0,x1,x2,x3,x4,x5) => x0.framebufferTexture2D(x1,x2,x3,x4,x5),
      GK: x0 => x0.exports,
      GL: x0 => x0.assetBase,
      H: Function.prototype.call.bind(Number.prototype.toString),
      HB: () => globalThis.Math,
      HC: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint32Array) return 1;
        return 2;
      },
      HD: (x0,x1) => x0.item(x1),
      HE: (x0,x1) => { x0.nonce = x1 },
      HF: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF64ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      HG: x0 => x0.disconnect(),
      HH: x0 => x0.firstChild,
      HI: x0 => x0.done(),
      HJ: (x0,x1,x2,x3,x4,x5,x6,x7,x8,x9,x10) => x0.blitFramebuffer(x1,x2,x3,x4,x5,x6,x7,x8,x9,x10),
      HK: x0 => x0.instance,
      HL: x0 => x0.loader,
      I: Function.prototype.call.bind(String.prototype.indexOf),
      IB: s => s.toUpperCase(),
      IC: Function.prototype.call.bind(DataView.prototype.getInt32),
      ID: x0 => x0.userAgent,
      IE: x0 => x0.nonce,
      IF: (x0,x1) => x0.contains(x1),
      IG: x0 => new Intl.Locale(x0),
      IH: x0 => x0.viewConstraints,
      II: () => globalThis.nameCityLoading,
      IJ: (x0,x1) => x0.deleteFramebuffer(x1),
      IK: x0 => globalThis.fetch(x0),
      IL: () => globalThis._flutter,
      J: (s, p, i) => s.lastIndexOf(p, i),
      JB: Object.is,
      JC: Function.prototype.call.bind(DataView.prototype.setInt32),
      JD: x0 => x0.maxTouchPoints,
      JE: () => globalThis.window.flutterConfiguration,
      JF: (s) => +s,
      JG: x0 => x0.region,
      JH: x0 => x0.hostElement,
      JI: (x0,x1) => x0.stage(x1),
      JJ: (x0,x1,x2,x3,x4,x5) => x0.bindBufferRange(x1,x2,x3,x4,x5),
      JK: x0 => x0.arrayBuffer(),
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
      KE: (x0,x1) => x0.attachShadow(x1),
      KF: x0 => x0.target,
      KG: x0 => x0.script,
      KH: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      KI: (x0,x1,x2) => x0.bindBuffer(x1,x2),
      KJ: (x0,x1,x2,x3,x4,x5) => x0.uniformMatrix4fv(x1,x2,x3,x4,x5),
      KK: x0 => x0.status,
      L: o => o === undefined,
      LB: x0 => x0.index,
      LC: o => o instanceof Uint16Array,
      LD: x0 => x0.navigator,
      LE: x0 => x0.preventDefault(),
      LF: (x0,x1) => x0.dispatchEvent(x1),
      LG: x0 => x0.language,
      LH: x0 => ({runApp: x0}),
      LI: (x0,x1,x2,x3) => x0.bufferSubData(x1,x2,x3),
      LJ: (x0,x1,x2,x3,x4,x5) => x0.uniformMatrix2fv(x1,x2,x3,x4,x5),
      LK: x0 => x0.ok,
      M: o => String(o),
      MB: (x0,x1) => x0[x1],
      MC: Function.prototype.call.bind(DataView.prototype.getUint16),
      MD: s => new Date(s * 1000).getTimezoneOffset() * 60,
      ME: (x0,x1) => x0.contains(x1),
      MF: (x0,x1) => x0.createEvent(x1),
      MG: x0 => x0.languages,
      MH: Function.prototype.call.bind(DataView.prototype.setBigInt64),
      MI: (x0,x1) => new OffscreenCanvas(x0,x1),
      MJ: (x0,x1,x2,x3,x4,x5) => x0.uniformMatrix3fv(x1,x2,x3,x4,x5),
      MK: (x0,x1) => x0.createShader(x1),
      N: (c) =>
      queueMicrotask(() => dartInstance.exports.$invokeCallback(c)),
      NB: x0 => x0.flags,
      NC: Function.prototype.call.bind(DataView.prototype.setUint16),
      ND: Date.now,
      NE: (x0,x1) => x0.focus(x1),
      NF: (x0,x1,x2,x3) => x0.initEvent(x1,x2,x3),
      NG: (x0,x1) => x0.observe(x1),
      NH: Function.prototype.call.bind(DataView.prototype.getBigInt64),
      NI: (x0,x1,x2,x3,x4) => ({alpha: x0,depth: x1,stencil: x2,antialias: x3,preserveDrawingBuffer: x4}),
      NJ: (x0,x1,x2,x3,x4) => x0.uniform1fv(x1,x2,x3,x4),
      NK: (x0,x1,x2) => x0.shaderSource(x1,x2),
      O: (x0,x1) => x0.didCreateEngineInitializer(x1),
      OB: (a, i, v) => a[i] = v,
      OC: o => o instanceof Int16Array,
      OD: (x0,x1,x2) => x0.setAttribute(x1,x2),
      OE: (x0,x1) => x0.closest(x1),
      OF: () => globalThis.window,
      OG: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      OH: (o, start, length) => new BigInt64Array(o.buffer, o.byteOffset + start, length),
      OI: (x0,x1,x2) => x0.getContext(x1,x2),
      OJ: (x0,x1,x2,x3,x4) => x0.uniform2fv(x1,x2,x3,x4),
      OK: (x0,x1) => x0.compileShader(x1),
      P: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      PB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI8ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      PC: Function.prototype.call.bind(DataView.prototype.getInt16),
      PD: (x0,x1,x2,x3) => x0.setProperty(x1,x2,x3),
      PE: (x0,x1) => x0.getAttribute(x1),
      PF: x0 => x0.readText(),
      PG: x0 => new ResizeObserver(x0),
      PH: () => typeof dartUseDateNowForTicks !== "undefined",
      PI: (x0,x1) => x0.getExtension(x1),
      PJ: (x0,x1,x2,x3,x4) => x0.uniform3fv(x1,x2,x3,x4),
      PK: (x0,x1,x2) => x0.getShaderParameter(x1,x2),
      Q: (wasmFunction,f) => finalizeWrapper(f, function() { return wasmFunction(f,arguments.length) }),
      QB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI16ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      QC: Function.prototype.call.bind(DataView.prototype.setInt16),
      QD: x0 => x0.style,
      QE: x0 => x0.activeElement,
      QF: x0 => x0.clipboard,
      QG: x0 => globalThis.parseFloat(x0),
      QH: () => Date.now(),
      QI: (x0,x1) => x0.getParameter(x1),
      QJ: (x0,x1,x2,x3,x4) => x0.uniform4fv(x1,x2,x3,x4),
      QK: (x0,x1) => x0.getShaderInfoLog(x1),
      R: (x0,x1) => ({initializeEngine: x0,autoStart: x1}),
      RB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      RC: o => o instanceof Uint8ClampedArray,
      RD: (x0,x1) => x0.createElement(x1),
      RE: (x0,x1) => x0.add(x1),
      RF: (x0,x1) => x0.writeText(x1),
      RG: (x0,x1) => x0.getComputedStyle(x1),
      RH: () => 1000 * performance.now(),
      RI: (x0,x1,x2,x3) => x0.putImageData(x1,x2,x3),
      RJ: x0 => x0.createBuffer(),
      RK: (x0,x1) => x0.deleteShader(x1),
      S: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      SB: Function.prototype.call.bind(String.prototype.toLowerCase),
      SC: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint8Array) return 1;
        return 2;
      },
      SD: x0 => x0.body,
      SE: x0 => x0.classList,
      SF: x0 => x0.unlock(),
      SG: x0 => x0.documentElement,
      SH: x0 => new Uint8Array(x0),
      SI: x0 => x0.arrayBuffer(),
      SJ: (x0,x1,x2,x3) => x0.bufferData(x1,x2,x3),
      SK: (x0,x1,x2) => x0.insertBefore(x1,x2),
      T: x0 => new Promise(x0),
      TB: (x0,x1,x2,x3) => x0.pushState(x1,x2,x3),
      TC: Function.prototype.call.bind(DataView.prototype.setInt8),
      TD: x0 => x0.remove(),
      TE: x0 => x0.data,
      TF: (x0,x1) => x0.lock(x1),
      TG: x0 => x0.computedStyleMap(),
      TH: (x0,x1,x2) => x0.slice(x1,x2),
      TI: (x0,x1) => x0.transferFromImageBitmap(x1),
      TJ: x0 => x0.pop(),
      TK: x0 => x0.id,
      U: (x0,x1,x2) => x0.call(x1,x2),
      UB: () => ({}),
      UC: Function.prototype.call.bind(DataView.prototype.getInt8),
      UD: (x0,x1) => x0.getPropertyValue(x1),
      UE: x0 => x0.scrollTop,
      UF: x0 => x0.orientation,
      UG: (x0,x1) => x0.get(x1),
      UH: (x0,x1) => x0.decode(x1),
      UI: x0 => x0.rasterEndMilliseconds,
      UJ: (x0,x1,x2,x3) => x0.texParameterf(x1,x2,x3),
      UK: x0 => x0.offsetHeight,
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
      VE: (handle) => clearTimeout(handle),
      VF: (x0,x1) => x0.querySelector(x1),
      VG: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      VH: (x0,x1) => x0.adoptText(x1),
      VI: x0 => x0.rasterStartMilliseconds,
      VJ: (x0,x1) => x0.useProgram(x1),
      VK: x0 => x0.offsetWidth,
      W: x0 => new Array(x0),
      WB: () => [],
      WC: (o, start, length) => new Float64Array(o.buffer, o.byteOffset + start, length),
      WD: x0 => x0.console,
      WE: (x0,x1) => { x0.scrollTop = x1 },
      WF: (x0,x1) => { x0.content = x1 },
      WG: x0 => x0.matches,
      WH: x0 => x0.first(),
      WI: x0 => x0.imageBitmaps,
      WJ: (x0,x1,x2,x3) => x0.bindBufferBase(x1,x2,x3),
      WK: x0 => x0.stopPropagation(),
      X: o => [o],
      XB: b => !!b,
      XC: (o, start, length) => new Float32Array(o.buffer, o.byteOffset + start, length),
      XD: (x0,x1) => { x0.id = x1 },
      XE: x0 => x0.tagName,
      XF: x0 => x0.head,
      XG: (x0,x1) => x0.matchMedia(x1),
      XH: x0 => x0.next(),
      XI: (x0,x1) => { x0.height = x1 },
      XJ: (x0,x1) => x0.deleteProgram(x1),
      XK: x0 => x0.disabled,
      Y: (o0, o1) => [o0, o1],
      YB: x0 => new Int8Array(x0),
      YC: (o, start, length) => new Uint32Array(o.buffer, o.byteOffset + start, length),
      YD: s => s.trimLeft(),
      YE: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      YF: (x0,x1) => { x0.name = x1 },
      YG: x0 => x0.matches,
      YH: x0 => x0.current(),
      YI: (x0,x1) => { x0.width = x1 },
      YJ: x0 => x0.createProgram(),
      YK: (x0,x1) => { x0.min = x1 },
      Z: (o0, o1, o2) => [o0, o1, o2],
      ZB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI8ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      ZC: (o, start, length) => new Int32Array(o.buffer, o.byteOffset + start, length),
      ZD: (o, p, r) => o.replace(p, () => r),
      ZE: (x0,x1) => { x0.value = x1 },
      ZF: (x0,x1) => { x0.title = x1 },
      ZG: x0 => x0.timeStamp,
      ZH: (x0,x1) => new Intl.v8BreakIterator(x0,x1),
      ZI: x0 => x0.convertToBlob(),
      ZJ: (x0,x1,x2) => x0.attachShader(x1,x2),
      ZK: (x0,x1) => { x0.max = x1 },
      a: (o0, o1, o2, o3) => [o0, o1, o2, o3],
      aB: x0 => new Uint8Array(x0),
      aC: (o, start, length) => new Uint16Array(o.buffer, o.byteOffset + start, length),
      aD: (o, p, r) => o.replaceAll(p, () => r),
      aE: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      aF: () => globalThis.document,
      aG: (x0,x1) => x0.hasAttribute(x1),
      aH: x0 => x0.v8BreakIterator,
      aI: (x0,x1,x2) => new ImageData(x0,x1,x2),
      aJ: (x0,x1,x2,x3) => x0.bindAttribLocation(x1,x2,x3),
      aK: (x0,x1) => { x0.disabled = x1 },
      b: (x0,x1,x2) => { x0[x1] = x2 },
      bB: x0 => new Uint8ClampedArray(x0),
      bC: (o, start, length) => new Int16Array(o.buffer, o.byteOffset + start, length),
      bD: s => s.trim(),
      bE: (x0,x1) => { x0.value = x1 },
      bF: (x0,x1) => x0.vibrate(x1),
      bG: x0 => x0.buttons,
      bH: () => globalThis.Intl,
      bI: (x0,x1) => x0.getContext(x1),
      bJ: (x0,x1) => x0.linkProgram(x1),
      bK: (x0,x1) => { x0.scrollLeft = x1 },
      c: o => o,
      cB: x0 => new Int16Array(x0),
      cC: (o, start, length) => new Uint8ClampedArray(o.buffer, o.byteOffset + start, length),
      cD: (a, s) => a.join(s),
      cE: x0 => x0.relatedTarget,
      cF: (o, p) => p in o,
      cG: x0 => x0.ctrlKey,
      cH: (x0,x1) => x0.segment(x1),
      cI: (x0,x1) => new OffscreenCanvas(x0,x1),
      cJ: (x0,x1,x2) => x0.getProgramParameter(x1,x2),
      cK: (x0,x1) => { x0.spellcheck = x1 },
      d: (o, p) => o[p],
      dB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI16ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      dC: (o, start, length) => new Int8Array(o.buffer, o.byteOffset + start, length),
      dD: (x0,x1) => x0.error(x1),
      dE: s => {
        if (/[[\]{}()*+?.\\^$|]/.test(s)) {
            s = s.replace(/[[\]{}()*+?.\\^$|]/g, '\\$&');
        }
        return s;
      },
      dF: x0 => x0.arrayBuffer(),
      dG: x0 => x0.y,
      dH: x0 => x0.index,
      dI: (x0,x1,x2,x3,x4) => x0.getImageData(x1,x2,x3,x4),
      dJ: (x0,x1) => x0.getProgramInfoLog(x1),
      dK: (x0,x1) => { x0.disabled = x1 },
      e: () => globalThis,
      eB: x0 => new Uint16Array(x0),
      eC: x0 => x0.history,
      eD: () => globalThis.console,
      eE: x0 => x0.value,
      eF: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof ArrayBuffer) return 1;
        if (globalThis.SharedArrayBuffer !== undefined &&
            o instanceof SharedArrayBuffer) {
          return 2;
        }
        return 3;
      },
      eG: x0 => x0.x,
      eH: x0 => x0.next(),
      eI: x0 => x0.data,
      eJ: (x0,x1,x2) => x0.getUniformLocation(x1,x2),
      eK: x0 => x0.canvasKitMaximumSurfaces,
      f: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      fB: x0 => new Int32Array(x0),
      fC: x0 => x0.search,
      fD: s => s.trimRight(),
      fE: x0 => x0.selectionDirection,
      fF: x0 => x0.status,
      fG: x0 => x0.offsetTop,
      fH: x0 => x0.value,
      fI: (x0,x1) => { x0.height = x1 },
      fJ: (x0,x1,x2) => x0.uniform1f(x1,x2),
      fK: x0 => x0.transferToImageBitmap(),
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
      gE: x0 => x0.selectionStart,
      gF: (x0,x1) => x0.fetch(x1),
      gG: x0 => x0.scrollLeft,
      gH: x0 => x0.done,
      gI: (x0,x1) => { x0.width = x1 },
      gJ: (x0,x1,x2) => x0.getUniformBlockIndex(x1,x2),
      gK: (x0,x1) => { x0.height = x1 },
      h: (x0,x1) => ({addView: x0,removeView: x1}),
      hB: x0 => new Uint32Array(x0),
      hC: x0 => x0.location,
      hD: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      hE: x0 => x0.selectionEnd,
      hF: x0 => x0.content,
      hG: x0 => x0.offsetLeft,
      hH: (o, m, a) => o[m].apply(o, a),
      hI: (x0,x1,x2,x3) => x0.drawImage(x1,x2,x3),
      hJ: (x0,x1,x2,x3) => x0.uniformBlockBinding(x1,x2,x3),
      hK: x0 => x0.height,
      i: (x0,x1) => x0.exec(x1),
      iB: x0 => new Float32Array(x0),
      iC: x0 => x0.pathname,
      iD: x0 => x0.now(),
      iE: x0 => x0.value,
      iF: x0 => x0.document,
      iG: x0 => x0.offsetParent,
      iH: x0 => x0.iterator,
      iI: (x0,x1) => x0.getContext(x1),
      iJ: (x0,x1,x2,x3) => x0.getActiveUniformBlockParameter(x1,x2,x3),
      iK: (x0,x1) => { x0.width = x1 },
      j: x0 => x0.length,
      jB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      jC: (x0,x1,x2,x3) => x0.replaceState(x1,x2,x3),
      jD: x0 => x0.performance,
      jE: x0 => x0.selectionDirection,
      jF: x0 => x0.language,
      jG: x0 => x0.deltaMode,
      jH: () => globalThis.Symbol,
      jI: (x0,x1) => x0.toDataURL(x1),
      jJ: (x0,x1,x2) => x0.uniform1i(x1,x2),
      jK: x0 => x0.width,
      k: o => o,
      kB: x0 => new Float64Array(x0),
      kC: o => {
        const proto = Object.getPrototypeOf(o);
        return proto === Object.prototype || proto === null;
      },
      kD: (a, l) => a.length = l,
      kE: x0 => x0.selectionStart,
      kF: (x0,x1,x2,x3) => x0.register(x1,x2,x3),
      kG: x0 => x0.deltaY,
      kH: (x0,x1) => new Intl.Segmenter(x0,x1),
      kI: x0 => x0.height,
      kJ: (x0,x1) => x0.disable(x1),
      kK: (x0,x1,x2,x3,x4,x5) => x0.drawElementsInstanced(x1,x2,x3,x4,x5),
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
      lD: (x0,x1) => x0.unregister(x1),
      lE: x0 => x0.selectionEnd,
      lF: (x0,x1) => x0.prepend(x1),
      lG: x0 => x0.deltaX,
      lH: x0 => x0.Segmenter,
      lI: x0 => x0.width,
      lJ: (x0,x1) => x0.frontFace(x1),
      lK: (x0,x1,x2,x3,x4) => x0.drawElements(x1,x2,x3,x4),
      m: (x0,x1) => { x0.lastIndex = x1 },
      mB: x0 => new ArrayBuffer(x0),
      mC: o => typeof o === 'function' && o[jsWrappedDartFunctionSymbol] === true,
      mD: () => globalThis.window.FinalizationRegistry,
      mE: x0 => x0.keyCode,
      mF: (x0,x1,x2,x3) => x0.addEventListener(x1,x2,x3),
      mG: x0 => x0.wheelDeltaY,
      mH: x0 => x0.buffer,
      mI: x0 => globalThis.BigInt(x0),
      mJ: (x0,x1,x2,x3,x4) => x0.clearColor(x1,x2,x3,x4),
      mK: (x0,x1) => x0.depthFunc(x1),
      n: (s, m) => {
        try {
          return new RegExp(s, m);
        } catch (e) {
          return String(e);
        }
      },
      nB: (x0,x1,x2) => new Uint8Array(x0,x1,x2),
      nC: f => f.dartFunction,
      nD: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      nE: (x0,x1) => x0.scrollIntoView(x1),
      nF: (x0,x1) => x0.querySelector(x1),
      nG: x0 => x0.wheelDeltaX,
      nH: x0 => x0.wasmMemory,
      nI: x0 => globalThis.Number(x0),
      nJ: (x0,x1) => x0.depthMask(x1),
      nK: (x0,x1,x2) => x0.blendEquationSeparate(x1,x2),
      o: o => o instanceof RegExp,
      oB: (x0,x1,x2) => new DataView(x0,x1,x2),
      oC: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      oD: x0 => new window.FinalizationRegistry(x0),
      oE: x0 => x0.multiViewEnabled,
      oF: (x0,x1) => x0.querySelectorAll(x1),
      oG: x0 => x0.key,
      oH: () => globalThis.window._flutter_skwasmInstance,
      oI: x0 => x0.buffer,
      oJ: (x0,x1) => x0.clearDepth(x1),
      oK: (x0,x1,x2,x3,x4) => x0.blendFuncSeparate(x1,x2,x3,x4),
      p: o => o,
      pB: (o, p) => o[p],
      pC: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      pD: x0 => x0.scale,
      pE: x0 => x0.parent,
      pF: x0 => x0.tabIndex,
      pG: x0 => x0.identifier,
      pH: () => new TextDecoder(),
      pI: x0 => x0.memory,
      pJ: (x0,x1) => x0.clearStencil(x1),
      pK: (x0,x1,x2) => x0.depthRange(x1,x2),
      q: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'boolean') return 1;
        return 2;
      },
      qB: (o) => new DataView(o.buffer, o.byteOffset, o.byteLength),
      qC: (p, s, f) => p.then(s, (e) => f(e, e === undefined)),
      qD: x0 => x0.visualViewport,
      qE: (x0,x1) => x0.replaceWith(x1),
      qF: x0 => x0.parentNode,
      qG: x0 => x0.touches,
      qH: (a, i) => a.splice(i, 1),
      qI: (x0,x1,x2) => x0.fsr_free(x1,x2),
      qJ: (x0,x1) => x0.clear(x1),
      qK: x0 => x0.hostElement,
      r: x0 => x0.dotAll,
      rB: Function.prototype.call.bind(Object.getOwnPropertyDescriptor(DataView.prototype, 'byteLength').get),
      rC: (o, i) => o[i],
      rD: x0 => x0.devicePixelRatio,
      rE: (x0,x1) => { x0.type = x1 },
      rF: x0 => x0.clientY,
      rG: x0 => x0.pressure,
      rH: a => a.pop(),
      rI: (x0,x1) => x0.fsr_alloc(x1),
      rJ: (x0,x1,x2,x3,x4) => x0.viewport(x1,x2,x3,x4),
      rK: x0 => x0.location,
      s: x0 => x0.unicode,
      sB: Function.prototype.call.bind(DataView.prototype.setFloat64),
      sC: o => o.length,
      sD: (d, digits) => d.toFixed(digits),
      sE: (x0,x1) => { x0.className = x1 },
      sF: x0 => x0.clientX,
      sG: x0 => x0.tiltY,
      sH: (map, o, v) => map.set(o, v),
      sI: (a, l) => a.length = l,
      sJ: (x0,x1,x2,x3,x4) => x0.framebufferRenderbuffer(x1,x2,x3,x4),
      sK: (x0,x1) => x0.getModifierState(x1),
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
      tD: x0 => x0.maxHeight,
      tE: (x0,x1) => { x0.tabIndex = x1 },
      tF: x0 => x0.getBoundingClientRect(),
      tG: x0 => x0.tiltX,
      tH: (map, o) => map.get(o),
      tI: (x0,x1,x2,x3,x4,x5,x6,x7,x8) => x0.compressedTexSubImage2D(x1,x2,x3,x4,x5,x6,x7,x8),
      tJ: (x0,x1) => x0.checkFramebufferStatus(x1),
      tK: x0 => x0.metaKey,
      u: x0 => x0.multiline,
      uB: o => o.buffer,
      uC: x0 => x0.state,
      uD: x0 => x0.maxWidth,
      uE: (x0,x1) => { x0.name = x1 },
      uF: x0 => x0.bottom,
      uG: x0 => x0.pointerType,
      uH: () => new WeakMap(),
      uI: (x0,x1,x2,x3,x4,x5,x6,x7,x8,x9) => x0.texSubImage2D(x1,x2,x3,x4,x5,x6,x7,x8,x9),
      uJ: (x0,x1,x2,x3,x4) => x0.drawArraysInstanced(x1,x2,x3,x4),
      uK: x0 => x0.altKey,
      v: (string, token) => string.split(token),
      vB: (b, o) => new DataView(b, o),
      vC: x0 => x0.hash,
      vD: x0 => x0.minHeight,
      vE: (x0,x1) => { x0.placeholder = x1 },
      vF: x0 => x0.top,
      vG: x0 => x0.pointerId,
      vH: x0 => x0.debugSkipFontRetryDelay,
      vI: (x0,x1) => x0.activeTexture(x1),
      vJ: (x0,x1,x2,x3) => x0.drawArrays(x1,x2,x3),
      vK: x0 => x0.ctrlKey,
      w: o => o instanceof Array,
      wB: (b, o, l) => new DataView(b, o, l),
      wC: (x0,x1,x2) => x0.removeEventListener(x1,x2),
      wD: x0 => x0.minWidth,
      wE: (x0,x1) => { x0.autocomplete = x1 },
      wF: x0 => x0.right,
      wG: x0 => x0.getCoalescedEvents(),
      wH: (x0,x1,x2) => x0.set(x1,x2),
      wI: (x0,x1,x2) => x0.bindTexture(x1,x2),
      wJ: (x0,x1,x2) => x0.getAttribLocation(x1,x2),
      wK: x0 => x0.isComposing,
      x: (a, i) => a[i],
      xB: Function.prototype.call.bind(DataView.prototype.getUint8),
      xC: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      xD: x0 => x0.height,
      xE: (x0,x1) => { x0.name = x1 },
      xF: x0 => x0.left,
      xG: (x0,x1) => x0.getModifierState(x1),
      xH: x0 => x0.fontFallbackBaseUrl,
      xI: x0 => x0.createTexture(),
      xJ: (x0,x1) => x0.enableVertexAttribArray(x1),
      xK: x0 => x0.code,
      y: a => a.length,
      yB: Function.prototype.call.bind(DataView.prototype.setUint8),
      yC: x0 => x0.state,
      yD: x0 => x0.width,
      yE: (x0,x1) => { x0.placeholder = x1 },
      yF: x0 => x0.clientY,
      yG: x0 => x0.blur(),
      yH: (handle) => clearInterval(handle),
      yI: (x0,x1,x2,x3,x4,x5) => x0.texStorage2D(x1,x2,x3,x4,x5),
      yJ: (x0,x1,x2,x3,x4,x5,x6) => x0.vertexAttribPointer(x1,x2,x3,x4,x5,x6),
      yK: x0 => x0.repeat,
      z: (string, times) => string.repeat(times),
      zB: Function.prototype.call.bind(DataView.prototype.getFloat64),
      zC: (x0,x1,x2) => x0.addEventListener(x1,x2),
      zD: x0 => x0.screen,
      zE: (x0,x1) => { x0.action = x1 },
      zF: x0 => x0.clientX,
      zG: x0 => x0.button,
      zH: (ms, c) =>
      setInterval(() => dartInstance.exports.$invokeCallback(c), ms),
      zI: (x0,x1,x2,x3) => x0.texParameteri(x1,x2,x3),
      zJ: (x0,x1) => x0.bindVertexArray(x1),
      zK: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),

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
