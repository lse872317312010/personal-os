const {test} = require('node:test');
const assert = require('node:assert/strict');
const core = require('../src/core.js');
function frame(text, extra = {}) {
    return {width:1080, height:2400, displayWidth:1080, displayHeight:2400,
        rotation:0, capturedAt:0, items:[{text, confidence:0.95,
            bounds:{left:100, top:200, right:400, bottom:300}}], ...extra};
}
function setup(frames) {
    let time=0, taps=0, index=0, cancelled=false, foreground='fixture';
    const stages=[];
    const io={now:()=>time, sleep:ms=>{time+=ms;}, cancelled:()=>cancelled,
        foreground:()=>foreground, checkGeometry:()=>{}, stage:s=>stages.push(s),
        tap:(x,y)=>{assert.equal(x,250);assert.equal(y,250);taps++;},
        observe:()=>{const f=frames[Math.min(index++,frames.length-1)]; return {...f, capturedAt:time};}};
    return {io, stages, taps:()=>taps, cancel:()=>{cancelled=true;},
        foreground:p=>{foreground=p;}, spec:{packageName:'fixture', target:'TEST 123456',
            expected:['PASS 123456'], minExpected:1, confidence:0.65,timeoutMs:15000}};
}
const before=()=>frame('TEST 123456'), after=()=>frame('PASS 123456');
test('verified only after one tap and two consecutive expected frames',()=>{
    const t=setup([before(),before(),after(),frame('loading'),after(),after()]);
    assert.equal(core.run(t.io,t.spec).status,'verified');assert.equal(t.taps(),1);
    assert.deepEqual(t.stages,['action_requested','verifying','verified']);
});
test('never taps an ambiguous target',()=>{
    const f=before();f.items.push(f.items[0]);const t=setup([f]);
    assert.throws(()=>core.run(t.io,t.spec),/AMBIGUOUS_TARGET/);assert.equal(t.taps(),0);
});
for (const [name,frames,reason] of [
    ['low confidence',[frame('TEST 123456',{items:[{text:'TEST 123456',confidence:0.2,bounds:{}}]})],'TARGET_NOT_FOUND'],
    ['already completed',[after()],'ALREADY_AT_RESULT'],
    ['cropped capture',[frame('TEST 123456',{displayWidth:1200})],'CAPTURE_GEOMETRY_MISMATCH'],
    ['rotation before action',[before(),frame('TEST 123456',{rotation:1})],'UNSTABLE_TARGET'],
    ['no result transition',[before()],'POSTCONDITION_NOT_MET'],
    ['different run nonce',[before(),before(),frame('PASS 999999')],'POSTCONDITION_NOT_MET'],
    ['rotation after action',[before(),before(),frame('PASS 123456',{rotation:1})],'ROTATION_CHANGED'],
]) test(name,()=>{const t=setup(frames);assert.throws(()=>core.run(t.io,t.spec),new RegExp(reason));
    assert.equal(t.taps(),/POSTCONDITION|after action/.test(reason+' '+name)?1:0);});
test('foreground change blocks injection',()=>{
    const t=setup([before()]);t.io.sleep=()=>t.foreground('other');
    assert.throws(()=>core.run(t.io,t.spec),/FOREGROUND_CHANGED/);assert.equal(t.taps(),0);
});
test('cancel during OCR blocks injection',()=>{
    const t=setup([before()]);const observe=t.io.observe;t.io.observe=()=>{t.cancel();return observe();};
    assert.throws(()=>core.run(t.io,t.spec),/CANCELLED/);assert.equal(t.taps(),0);
});
test('stale OCR output blocks action',()=>{
    const t=setup([before()]);t.io.observe=()=>({...before(),capturedAt:-10000});
    assert.throws(()=>core.run(t.io,t.spec),/STALE_FRAME/);assert.equal(t.taps(),0);
});
test('injection failure is not retried',()=>{
    const t=setup([before()]);let attempts=0;t.io.tap=()=>{attempts++;throw new Error('INJECT_FAILED');};
    assert.throws(()=>core.run(t.io,t.spec),/INJECT_FAILED/);assert.equal(attempts,1);
});
test('timeout after slow capture blocks action',()=>{
    const t=setup([before()]);const observe=t.io.observe;
    t.io.observe=()=>{t.io.sleep(16000);return observe();};
    assert.throws(()=>core.run(t.io,t.spec),/TIMEOUT/);assert.equal(t.taps(),0);
});
test('out of screen bounds blocks action',()=>{
    const f=before();f.items[0].bounds.right=9999;const t=setup([f]);
    assert.throws(()=>core.run(t.io,t.spec),/INVALID_BOUNDS/);assert.equal(t.taps(),0);
});
