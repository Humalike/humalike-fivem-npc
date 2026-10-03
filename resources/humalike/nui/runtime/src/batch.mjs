/**
 * The game sends the messages of one pulse as `{ type: "batch", messages: [...] }`:
 * one cross-process call instead of one per message.
 * @param {unknown} data
 * @returns {unknown[] | null} the parts, or null when `data` is not a batch
 */
export function batchParts(data) {
  if (!data || typeof data !== "object") return null;
  const message = /** @type {{ type?: unknown, messages?: unknown }} */ (data);
  if (message.type !== "batch" || !Array.isArray(message.messages)) return null;
  return message.messages;
}

/**
 * Each part of a batch reaches the target's message listeners as if the game
 * had sent it on its own, in the order the game queued them.
 * @param {EventTarget} target
 */
export function installBatchDispatcher(target) {
  target.addEventListener("message", (event) => {
    const parts = batchParts(/** @type {MessageEvent<unknown>} */ (event).data);
    if (!parts) return;
    for (const part of parts) {
      target.dispatchEvent(new MessageEvent("message", { data: part }));
    }
  });
}
