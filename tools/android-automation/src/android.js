/* AutoJs6 6.7.0 host. Generated deliverable starts with the ui directive. */
var busy = false, cancelled = false, lastReport = null, selectedMode = null;
var evidenceFile = String(context.getFilesDir()) + '/personal-os-visual-loop.json';
var nonce = String(Math.floor(100000 + Math.random() * 900000));
var clicked = false;
activity.setRequestedOrientation(android.content.pm.ActivityInfo.SCREEN_ORIENTATION_PORTRAIT);
ui.layout('<vertical padding="20" bg="#FFFFFF">' +
    '<text text="Personal OS · 视觉闭环 0.1" textSize="23sp" textColor="#14213D"/>' +
    '<text text="先运行自测。授权截图时选择整个屏幕。每次运行最多点击一次。" textSize="16sp" marginTop="12"/>' +
    '<button id="selftest" text="1. 开始本机闭环自测" marginTop="12"/>' +
    '<button id="game" text="2. 星铁设置入口单步测试"/>' +
    '<button id="stop" text="停止（也可从 AutoJs6 停止脚本）"/>' +
    '<text id="status" text="待运行：请先在 AutoJs6 抽屉授权 Shizuku" textSize="16sp" marginTop="12"/>' +
    '<button id="target" text="WAIT" textSize="30sp" h="96" marginTop="24"/>' +
    '<text id="outcome" text="READY" textSize="30sp" textColor="#14213D" gravity="center"/>' +
    '<button id="copy" text="复制最近的诊断报告" marginTop="24"/>' +
    '</vertical>');
function status(text) { ui.run(function () { ui.status.setText(text); }); }
function persist(report) {
    var tmp = evidenceFile + '.tmp';
    files.write(tmp, JSON.stringify(report, null, 2));
    if (!new java.io.File(tmp).renameTo(new java.io.File(evidenceFile))) throw new Error('EVIDENCE_WRITE_FAILED');
    lastReport = report;
}
try {
    if (files.exists(evidenceFile)) {
        lastReport = JSON.parse(files.read(evidenceFile));
        if (lastReport.status === 'running') {
            lastReport.status = 'interrupted'; lastReport.reason = 'PROCESS_INTERRUPTED'; persist(lastReport);
        }
        status('上次结果：' + lastReport.status + ' / ' + (lastReport.reason || lastReport.mode));
    }
} catch (_) { status('历史诊断不可读取；本次可重新测试。'); }
ui.target.on('click', function () {
    if (!busy || selectedMode !== 'fixture' || clicked) return;
    clicked = true;
    ui.target.setText('DONE'); ui.outcome.setText('PASS ' + nonce);
});
ui.stop.on('click', function () { cancelled = true; status('已请求停止；后续检查将拒绝触控。'); });
ui.copy.on('click', function () {
    if (busy) return;
    if (lastReport) { setClip(JSON.stringify(lastReport, null, 2)); toast('已复制诊断 JSON（不含截图或识别原文）'); }
});
function shellChecked(command) {
    var result = shizuku(command);
    if (Number(result.code) !== 0) throw new Error('SHIZUKU_COMMAND_FAILED');
    return String(result.result);
}
function geometry() {
    var display = context.getSystemService(android.content.Context.WINDOW_SERVICE).getDefaultDisplay();
    var metrics = new android.util.DisplayMetrics(); display.getRealMetrics(metrics);
    return {width: Number(metrics.widthPixels), height: Number(metrics.heightPixels), rotation: Number(display.getRotation())};
}
function start(mode) {
    if (busy) return;
    if (selectedMode !== null) { status('请退出并重新运行脚本后再测，确保截图方向与权限重新初始化。'); return; }
    busy = true; cancelled = false; selectedMode = mode;
    ui.selftest.setEnabled(false); ui.game.setEnabled(false);
    threads.start(function () {
        var report = {schema: 'personal-os.automation-run.v1', adapter: 'autojs6-shizuku',
            runtimeRequired: '6.7.0', mode: mode, runId: String(java.util.UUID.randomUUID()),
            startedAt: new Date().toISOString(), status: 'running', stage: 'preflight',
            actionCount: 0, frames: [], deviceValidation: 'not_established'};
        var captureGranted = false, started = Date.now();
        try {
            report.runtimeVersion = String(context.getPackageManager().getPackageInfo(context.getPackageName(), 0).versionName);
            persist(report);
            if (!shizuku.state.isOperational) throw new Error('SHIZUKU_NOT_AUTHORIZED');
            shellChecked('id'); // Binds the user service before currentPackage().
            if (mode === 'fixture') {
                ui.run(function () { ui.target.setText('TEST ' + nonce); ui.outcome.setText('READY'); });
            }
            status(mode === 'fixture' ? '允许整个屏幕截图，然后保持本页，不要手动点测试按钮。' :
                '允许整个屏幕截图。随后有 15 秒切到星铁手机菜单，保持“设置”入口可见。');
            if (!images.requestScreenCapture(mode === 'starrail')) throw new Error('CAPTURE_PERMISSION_DENIED');
            captureGranted = true;
            sleep(mode === 'fixture' ? 1500 : 15000);
            if (cancelled) throw new Error('CANCELLED');
            var pkg = mode === 'fixture' ? String(context.getPackageName()) : String(shizuku.currentPackage());
            if (mode === 'starrail' && ['com.miHoYo.hkrpg', 'com.miHoYo.hkrpg.bilibili', 'com.HoYoverse.hkrpgoversea'].indexOf(pkg) < 0)
                throw new Error('STAR_RAIL_NOT_FOREGROUND');
            var spec = {packageName: pkg, target: mode === 'fixture' ? 'TEST ' + nonce : '设置',
                expected: mode === 'fixture' ? ['PASS ' + nonce] : ['画面', '声音', '音量', '分辨率', '帧率'],
                minExpected: mode === 'fixture' ? 1 : 2, confidence: 0.65, timeoutMs: 45000};
            var io = {
                now: function () { return Date.now(); }, sleep: sleep,
                cancelled: function () { return cancelled; },
                foreground: function () { return String(shizuku.currentPackage()); },
                stage: function (s) { report.stage = s; persist(report); },
                checkGeometry: function (frame) {
                    var g = geometry();
                    if (g.width !== frame.width || g.height !== frame.height || g.rotation !== frame.rotation)
                        throw new Error('ROTATION_CHANGED');
                },
                tap: function (x, y) {
                    if (cancelled) throw new Error('CANCELLED');
                    report.actionCount = 1; persist(report); // Requested, not necessarily delivered.
                    shellChecked('input tap ' + x + ' ' + y);
                },
                observe: function () {
                    var at = Date.now(), g = geometry();
                    // captureScreen owns its cached image; only recycle our explicit copy.
                    var img = images.copy(images.captureScreen());
                    try {
                        var found = ocr.mlkit.detect(img), items = [];
                        for (var i = 0; i < found.length; i++) {
                            var r = found[i], b = r.bounds;
                            items.push({text: String(r.text), confidence: Number(r.confidence),
                                bounds: {left: Number(b.left), top: Number(b.top), right: Number(b.right), bottom: Number(b.bottom)}});
                        }
                        var frame = {width: Number(img.getWidth()), height: Number(img.getHeight()),
                            displayWidth: g.width, displayHeight: g.height, rotation: g.rotation,
                            capturedAt: at, items: items};
                        report.frames.push({width: frame.width, height: frame.height, rotation: g.rotation,
                            ocrCount: items.length, durationMs: Date.now() - at});
                        persist(report);
                        return frame;
                    } finally { img.recycle(); }
                }
            };
            var result = VisualLoop.run(io, spec);
            report.status = result.status; report.verificationFrames = result.verificationFrames;
            report.deviceValidation = mode === 'fixture' ? 'fixture_observed_only' : 'single_step_observed_only';
        } catch (e) {
            var message = String(e.message || e);
            report.status = cancelled ? 'cancelled' : 'blocked';
            report.reason = /^[A-Z_]+$/.test(message) ? message : 'RUNTIME_ERROR';
            // No raw platform exception, package list, screenshot, UID or OCR text in export.
        } finally {
            report.finishedAt = new Date().toISOString(); report.durationMs = Date.now() - started;
            try { persist(report); } catch (_) { report.status = 'blocked'; report.reason = 'EVIDENCE_WRITE_FAILED'; lastReport = report; }
            if (captureGranted) { try { images.stopScreenCapture(); } catch (_) {} }
            busy = false;
            status('结果：' + report.status + (report.reason ? ' / ' + report.reason : '') + '。可复制诊断；再次测试请重新运行脚本。');
        }
    });
}
ui.selftest.on('click', function () { start('fixture'); });
ui.game.on('click', function () { start('starrail'); });
