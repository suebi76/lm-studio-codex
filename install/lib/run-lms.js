const { spawn } = require('node:child_process');
const child = spawn(process.platform === 'win32' ? 'lms.exe' : 'lms', process.argv.slice(2), {
  stdio: 'inherit', windowsHide: true,
});
const timer = setTimeout(() => {
  console.error('[lm-studio] lms did not respond within 45 seconds. Open LM Studio manually, check its local server, then retry.');
  if (process.platform === 'win32') spawn('taskkill.exe', ['/PID', String(child.pid), '/T', '/F'], { stdio: 'ignore', windowsHide: true });
  else child.kill('SIGKILL');
  process.exitCode = 124;
}, 45000);
child.on('error', error => { clearTimeout(timer); console.error(`[lm-studio] Cannot start lms: ${error.message}`); process.exitCode = 1; });
child.on('close', code => { clearTimeout(timer); process.exitCode = process.exitCode || code || 0; });
