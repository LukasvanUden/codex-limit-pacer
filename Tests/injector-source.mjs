import { readFileSync } from 'node:fs';

export function buildInjectorSource() {
  return readFileSync(new URL('../Resources/injector.js', import.meta.url), 'utf8');
}
