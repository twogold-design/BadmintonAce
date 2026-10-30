// Local-file startup uses bundled data, without requesting file:// via fetch.
// HTTP/HTTPS exports retain the normal Godot loading path.
(() => {
  if (location.protocol !== 'file:') return;
  window.ACE_SERVER ||= 'ws://127.0.0.1:8766/ws';
  window.ACE_LOCAL_READY = new Promise((resolve, reject) => {
    if (typeof DecompressionStream === 'undefined') {
      reject(new Error('当前浏览器不支持本地资源解压。请使用新版 Chrome / Edge，或运行“开始游戏.cmd”。'));
      return;
    }
    const script = document.createElement('script');
    script.src = new URL('local-data.js', document.baseURI).href;
    script.onerror = () => reject(new Error('未找到本地游戏资源 local-data.js，请完整解压游戏压缩包后再打开 index.html。'));
    script.onload = () => {
      try {
        const data = window.ACE_LOCAL_DATA;
        if (!data?.files || !data?.worklets) throw new Error('本地游戏资源损坏，请重新解压。');
        const resources = new Map(Object.entries(data.files).map(([name, value]) => [new URL(name, document.baseURI).href, value]));
        const originalFetch = window.fetch.bind(window);
        window.fetch = (input, options) => {
          const url = new URL(input instanceof Request ? input.url : String(input), document.baseURI).href;
          const entry = resources.get(url);
          if (!entry) return originalFetch(input, options);
          if (!entry.bytes) {
            const binary = atob(entry.gzip);
            entry.bytes = Uint8Array.from(binary, c => c.charCodeAt(0));
            delete entry.gzip;
          }
          const stream = new Blob([entry.bytes]).stream().pipeThrough(new DecompressionStream('gzip'));
          return Promise.resolve(new Response(stream, {status:200, headers:{'Content-Type':entry.mime,'Content-Length':String(entry.size)}}));
        };
        const worklets = new Map(Object.entries(data.worklets).map(([name, source]) => [new URL(name, document.baseURI).href, 'data:text/javascript;charset=utf-8,' + encodeURIComponent(source)]));
        if (typeof Worklet !== 'undefined') {
          const originalAddModule = Worklet.prototype.addModule;
          Worklet.prototype.addModule = function (url, options) {
            const resolved = new URL(String(url), document.baseURI).href;
            return originalAddModule.call(this, worklets.get(resolved) || url, options);
          };
        }
        delete window.ACE_LOCAL_DATA;
        resolve();
      } catch (error) { reject(error); }
    };
    document.head.appendChild(script);
  });
})();
