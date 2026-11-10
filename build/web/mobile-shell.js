// Keep the desktop game unchanged; touch devices get a clear orientation prompt.
(() => {
  if (!(navigator.maxTouchPoints > 0)) return;
  const install = () => {
    const viewport = document.querySelector('meta[name="viewport"]');
    if (viewport && !viewport.content.includes('viewport-fit')) viewport.content += ', viewport-fit=cover';
    const style = document.createElement('style');
    style.textContent = `
      html,body { overscroll-behavior:none; }
      #canvas { touch-action:none; -webkit-user-select:none; user-select:none; -webkit-touch-callout:none; }
      #ace-rotate { display:none; position:fixed; inset:0; z-index:10000; background:#0b1721;
        color:#edf3e9; font:18px system-ui; text-align:center; align-items:center; justify-content:center;
        flex-direction:column; padding:32px; box-sizing:border-box; gap:16px; }
      #ace-rotate strong { color:#cdf578; font-size:26px; }
      #ace-rotate small { color:#abc1ba; line-height:1.7; }
      @media (orientation:portrait) { #ace-rotate { display:flex; } }
    `;
    document.head.append(style);
    const notice = document.createElement('div');
    notice.id = 'ace-rotate'; notice.setAttribute('role','status');
    const title = document.createElement('strong'); title.textContent = '请横屏游玩';
    const hint = document.createElement('div'); hint.textContent = '把手机横过来，展开完整球场';
    const detail = document.createElement('small'); detail.textContent = '左手摇杆移动 · 右手选择球路\n按住蓄力，松手击球';detail.style.whiteSpace='pre-line';
    notice.append(title,hint,detail); document.body.append(notice);
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded',install,{once:true}); else install();
})();
