import { access } from 'node:fs/promises';
import { constants as fsConstants } from 'node:fs';
import { basename, join } from 'node:path';
import { homedir } from 'node:os';
import net from 'node:net';
import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function exists(path) {
  try {
    await access(path, fsConstants.F_OK);
    return true;
  } catch {
    return false;
  }
}

export async function findCodexApp(explicitPath) {
  const candidates = [
    explicitPath,
    process.env.CODEX_APP_PATH,
    '/Applications/Codex.app',
    join(homedir(), 'Applications', 'Codex.app'),
  ].filter(Boolean);

  for (const candidate of candidates) {
    if (await exists(candidate)) return candidate;
  }

  throw new Error(
    'Codex.app wurde nicht gefunden. Übergib den Pfad mit --app "/Pfad/zu/Codex.app" oder setze CODEX_APP_PATH.',
  );
}

export function appNameFromPath(appPath) {
  return basename(appPath).replace(/\.app$/i, '');
}

async function listProcesses() {
  const { stdout } = await execFileAsync('/bin/ps', ['-ax', '-o', 'command='], {
    maxBuffer: 10 * 1024 * 1024,
  });
  return stdout;
}

export async function isAppRunning(appPath) {
  const processList = await listProcesses();
  const executablePrefix = `${appPath}/Contents/MacOS/`;
  return processList.split('\n').some((line) => line.includes(executablePrefix));
}

function escapeAppleScriptString(value) {
  return value.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
}

export async function quitAppGracefully(appPath, timeoutMs = 12_000) {
  if (!(await isAppRunning(appPath))) return;

  const appName = appNameFromPath(appPath);
  const escaped = escapeAppleScriptString(appName);

  try {
    await execFileAsync('/usr/bin/osascript', [
      '-e',
      `tell application "${escaped}" to quit`,
    ]);
  } catch {
    // The app may still be shutting down even if AppleScript reports an error.
  }

  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (!(await isAppRunning(appPath))) return;
    await sleep(250);
  }

  throw new Error(
    'Codex konnte nicht automatisch beendet werden. Bitte Codex vollständig schließen und den Starter erneut ausführen.',
  );
}

export async function launchAppWithDebugging(appPath, port) {
  const child = spawn('/usr/bin/open', [
    '-na',
    appPath,
    '--args',
    `--remote-debugging-port=${port}`,
    '--remote-debugging-address=127.0.0.1',
  ], {
    detached: true,
    stdio: 'ignore',
  });
  child.unref();
}

export async function pickUnusedLoopbackPort() {
  const server = net.createServer();
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen({ host: '127.0.0.1', port: 0, exclusive: true }, resolve);
  });

  const address = server.address();
  const port = typeof address === 'object' && address ? address.port : null;
  await new Promise((resolve) => server.close(resolve));

  if (!port) throw new Error('Es konnte kein freier lokaler Debug-Port gefunden werden.');
  return port;
}

export async function fetchJson(url, timeoutMs = 1_500) {
  const response = await fetch(url, {
    signal: AbortSignal.timeout(timeoutMs),
    cache: 'no-store',
  });
  if (!response.ok) throw new Error(`HTTP ${response.status} von ${url}`);
  return response.json();
}

export async function waitForDebugEndpoint(port, timeoutMs = 35_000) {
  const deadline = Date.now() + timeoutMs;
  const url = `http://127.0.0.1:${port}/json/version`;
  let lastError;

  while (Date.now() < deadline) {
    try {
      return await fetchJson(url, 1_000);
    } catch (error) {
      lastError = error;
      await sleep(300);
    }
  }

  throw new Error(
    `Der lokale Codex-Debug-Port wurde nicht erreichbar. Letzter Fehler: ${lastError?.message ?? 'unbekannt'}`,
  );
}
