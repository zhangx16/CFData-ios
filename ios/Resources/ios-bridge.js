(() => {
    'use strict';
    const post = body => window.webkit.messageHandlers.cfdata.postMessage(body);
    const style = document.createElement('style');
    style.textContent = '#btnRunInBackground,#backgroundConfirmCard{display:none!important}';
    document.head.appendChild(style);
    const note = document.createElement('div');
    note.textContent = 'iOS 本机测速 · 切到后台或锁屏将停止任务，请先导出结果。测速会消耗当前网络流量。';
    note.style.cssText = 'padding:10px 14px;font-size:13px;line-height:1.6;background:#e8f0ff;color:#173f7a;border-radius:10px;margin:8px 0 16px';
    const start = document.getElementById('btnStart');
    if (start) start.parentNode.insertBefore(note, start);

    window.downloadFile = (content, nameBase, ext) => {
        const stamp = new Date().toISOString().replace(/[-:T]/g, '').split('.')[0];
        post({type: 'export', content: '\uFEFF' + content, name: `${nameBase}_${stamp}.${ext}`});
    };
    window.copyToClipboard = text => {
        post({type: 'copy', text: String(text)});
        if (typeof log === 'function') log('已复制到剪贴板');
    };
    window.cfdataDidForeground = () => {
        if (typeof resetStoppedTaskUI === 'function') resetStoppedTaskUI('已返回前台；后台期间任务已停止，请按需重新开始');
        if (typeof showNoticeCard === 'function') showNoticeCard('切到后台后测速已停止，已有表格可继续查看或导出。');
    };
    let lastRunning = false;
    setInterval(() => {
        const running = (typeof isTaskRunning !== 'undefined' && isTaskRunning) ||
            (typeof officialBatchSpeedRunning !== 'undefined' && officialBatchSpeedRunning) ||
            (typeof currentSpeedTestingIP !== 'undefined' && !!currentSpeedTestingIP);
        if (running !== lastRunning) {
            lastRunning = running;
            post({type: 'activity', running: !!running});
        }
    }, 1000);
})();
