const DEFAULT_TIMEOUT_MS = 5_000;

export class CdpClient {
  constructor(webSocket, label = 'renderer') {
    this.webSocket = webSocket;
    this.label = label;
    this.nextId = 1;
    this.pending = new Map();
    this.closed = false;

    webSocket.addEventListener('message', (event) => {
      let payload;
      try {
        const raw = typeof event.data === 'string'
          ? event.data
          : Buffer.from(event.data).toString('utf8');
        payload = JSON.parse(raw);
      } catch {
        return;
      }

      if (payload.id === undefined) return;
      const pending = this.pending.get(payload.id);
      if (!pending) return;

      this.pending.delete(payload.id);
      clearTimeout(pending.timer);

      if (payload.error) {
        const error = new Error(
          `${pending.method} failed for ${this.label}: ${payload.error.message ?? 'unknown CDP error'}`,
        );
        error.code = payload.error.code;
        pending.reject(error);
      } else {
        pending.resolve(payload.result ?? {});
      }
    });

    const closeHandler = () => {
      if (this.closed) return;
      this.closed = true;
      for (const pending of this.pending.values()) {
        clearTimeout(pending.timer);
        pending.reject(new Error(`CDP connection closed for ${this.label}`));
      }
      this.pending.clear();
    };

    webSocket.addEventListener('close', closeHandler, { once: true });
    webSocket.addEventListener('error', closeHandler, { once: true });
  }

  static async connect(webSocketUrl, label = 'renderer', timeoutMs = DEFAULT_TIMEOUT_MS) {
    const webSocket = new WebSocket(webSocketUrl);

    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        try { webSocket.close(); } catch {}
        reject(new Error(`Timed out connecting to ${label}`));
      }, timeoutMs);

      webSocket.addEventListener('open', () => {
        clearTimeout(timer);
        resolve();
      }, { once: true });

      webSocket.addEventListener('error', () => {
        clearTimeout(timer);
        reject(new Error(`Could not connect to ${label}`));
      }, { once: true });
    });

    return new CdpClient(webSocket, label);
  }

  async send(method, params = {}, timeoutMs = DEFAULT_TIMEOUT_MS) {
    if (this.closed || this.webSocket.readyState !== WebSocket.OPEN) {
      throw new Error(`CDP connection is not open for ${this.label}`);
    }

    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`${method} timed out for ${this.label}`));
      }, timeoutMs);

      this.pending.set(id, { method, resolve, reject, timer });
      try {
        this.webSocket.send(JSON.stringify({ id, method, params }));
      } catch (error) {
        clearTimeout(timer);
        this.pending.delete(id);
        reject(error);
      }
    });
  }

  close() {
    if (this.closed) return;
    this.closed = true;
    try { this.webSocket.close(); } catch {}
  }
}
