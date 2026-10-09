/** @param {unknown} data @returns {unknown[] | null} the parts of a batch message, else null */
export function batchParts(data) {
  if (!data || typeof data !== "object") return null;
  const message = /** @type {{ type?: unknown, messages?: unknown }} */ (data);
  if (message.type !== "batch" || !Array.isArray(message.messages)) return null;
  return message.messages;
}

/** Hands each part of a batch to the target's message listeners. @param {EventTarget} target */
export function installBatchDispatcher(target) {
  target.addEventListener("message", (event) => {
    const parts = batchParts(/** @type {MessageEvent<unknown>} */ (event).data);
    if (!parts) return;
    for (const part of parts) {
      target.dispatchEvent(new MessageEvent("message", { data: part }));
    }
  });
}
