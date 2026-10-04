const { test } = require('node:test');
const assert = require('node:assert/strict');
const { runTask, defaults } = require('../install/lib/run-codex');

function mock(code) { return { command: process.execPath, prefix: ['-e', code, '--'] }; }
test('preserves prompts verbatim, streams answer, and captures session ID', async () => {
  const prompt = 'quotes " and & | $() and spaces';
  const result = await runTask(mock(`
    const args=process.argv.slice(1);
    if(args[args.length-1] !== ${JSON.stringify(prompt)}) process.exit(2);
    console.log(JSON.stringify({type:'thread.started',thread_id:'session-one'}));
    console.log(JSON.stringify({type:'item.completed',item:{type:'agent_message',text:'OK'}}));
  `), [], null, prompt, false);
  assert.deepEqual(result, { code: 0, threadId: 'session-one' });
});
test('continues the explicit session, not whichever session happened to run last', async () => {
  const result = await runTask(mock(`
    const args=process.argv.slice(1);
    if(args[args.indexOf('resume')+1] !== 'session-one') process.exit(2);
    console.log(JSON.stringify({type:'item.completed',item:{type:'agent_message',text:'CONTINUED'}}));
  `), [], 'session-one', 'next', false);
  assert.equal(result.code, 0); assert.equal(result.threadId, 'session-one');
});
test('empty successful process is reported as a failed answer', async () => {
  assert.equal((await runTask(mock(''), [], null, 'hello', false)).code, 1);
});
test('propagates child failure and reported turn errors', async () => {
  assert.equal((await runTask(mock('process.exit(7)'), [], null, 'hello', false)).code, 7);
  assert.equal((await runTask(mock('console.log(JSON.stringify({type:"turn.failed",error:{message:"failed"}}))'), [], null, 'hello', false)).code, 1);
});
test('context override is bounded to positive integers', () => {
  const old = process.env.LMSTUDIO_CODEX_CONTEXT;
  try {
    process.env.LMSTUDIO_CODEX_CONTEXT = '8192'; assert.ok(defaults().includes('model_context_window=8192'));
    process.env.LMSTUDIO_CODEX_CONTEXT = 'NaN'; assert.ok(!defaults().some(x => x.startsWith('model_context_window=')));
  } finally { if (old === undefined) delete process.env.LMSTUDIO_CODEX_CONTEXT; else process.env.LMSTUDIO_CODEX_CONTEXT = old; }
});
