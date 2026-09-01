export type AnimationFrameHandler = (now: number) => void;

const frameHandlers = new Set<AnimationFrameHandler>();
let running = false;

function frame(now: number): void {
  for (const handler of frameHandlers) {
    try {
      handler(now);
    } catch (error) {
      // Isolate labels, voice and future frame-driven features.
      console.error("[humalike:nui] animation frame handler failed", error);
    }
  }
  if (frameHandlers.size > 0) requestAnimationFrame(frame);
  else running = false;
}

export function onAnimationFrame(handler: AnimationFrameHandler): () => void {
  frameHandlers.add(handler);
  if (!running) {
    running = true;
    requestAnimationFrame(frame);
  }
  return () => frameHandlers.delete(handler);
}
