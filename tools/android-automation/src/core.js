/* Portable policy; no Android, network, or Personal OS authority. */
var VisualLoop = (function () {
    function normalize(s) { return String(s).replace(/\s+/g, '').toUpperCase(); }
    function fail(code) { throw new Error(code); }
    function target(frame, text, confidence) {
        var hits = frame.items.filter(function (v) {
            return normalize(v.text) === normalize(text) &&
                isFinite(v.confidence) && v.confidence >= confidence;
        });
        if (hits.length !== 1) fail(hits.length ? 'AMBIGUOUS_TARGET' : 'TARGET_NOT_FOUND');
        var b = hits[0].bounds;
        if (![b.left, b.top, b.right, b.bottom].every(isFinite) ||
            b.left < 0 || b.top < 0 || b.right > frame.width || b.bottom > frame.height ||
            b.right <= b.left || b.bottom <= b.top) fail('INVALID_BOUNDS');
        return {x: Math.round((b.left + b.right) / 2), y: Math.round((b.top + b.bottom) / 2)};
    }
    function expected(frame, labels, min, confidence) {
        return labels.filter(function (label) {
            return frame.items.some(function (v) {
                return isFinite(v.confidence) && v.confidence >= confidence &&
                    normalize(v.text).indexOf(normalize(label)) >= 0;
            });
        }).length >= min;
    }
    function run(io, spec) {
        var deadline = io.now() + spec.timeoutMs;
        function guard() {
            if (io.cancelled()) fail('CANCELLED');
            if (io.now() > deadline) fail('TIMEOUT');
            if (io.foreground() !== spec.packageName) fail('FOREGROUND_CHANGED');
        }
        function observe() {
            guard();
            var f = io.observe();
            guard();
            if (!(f.width > 0 && f.height > 0) || f.width !== f.displayWidth ||
                f.height !== f.displayHeight) fail('CAPTURE_GEOMETRY_MISMATCH');
            return f;
        }
        var a = observe();
        if (expected(a, spec.expected, spec.minExpected, spec.confidence)) fail('ALREADY_AT_RESULT');
        var p = target(a, spec.target, spec.confidence);
        io.sleep(400);
        var b = observe(), q = target(b, spec.target, spec.confidence);
        if (expected(b, spec.expected, spec.minExpected, spec.confidence)) fail('ALREADY_AT_RESULT');
        if (a.width !== b.width || a.height !== b.height || a.rotation !== b.rotation ||
            Math.abs(p.x - q.x) > 8 || Math.abs(p.y - q.y) > 8) fail('UNSTABLE_TARGET');
        guard();
        // Do not act on an OCR result that took too long to produce.
        if (io.now() - b.capturedAt > 2500) fail('STALE_FRAME');
        io.checkGeometry(b);
        guard();
        io.stage('action_requested');
        io.tap(q.x, q.y); // Never retry an uncertain or failed injection.
        io.stage('verifying');
        var consecutive = 0;
        for (var i = 0; i < 8; i++) {
            io.sleep(700);
            var after = observe();
            if (after.width !== b.width || after.height !== b.height || after.rotation !== b.rotation)
                fail('ROTATION_CHANGED');
            consecutive = expected(after, spec.expected, spec.minExpected, spec.confidence) ? consecutive + 1 : 0;
            if (consecutive >= 2) { io.stage('verified'); return {status: 'verified', taps: 1, verificationFrames: 2}; }
        }
        fail('POSTCONDITION_NOT_MET');
    }
    return {normalize: normalize, target: target, expected: expected, run: run};
})();
if (typeof module !== 'undefined') module.exports = VisualLoop;
