<script lang="ts" module>
  // Tiny SF-symbol-flavored glyph map. Mirrors the few glyphs the desktop
  // emits on the volume page; falls back to a dot so we never render empty.
  export function symbolFor(name: string, muted: boolean): string {
    if (name === "speaker.wave.2.fill" || name === "speaker.wave.2") {
      return muted ? "🔇" : "🔊";
    }
    if (name === "speaker.slash.fill" || name === "speaker.slash") return "🔇";
    return "•";
  }
</script>

<script lang="ts">
  import { deck, setVolume } from "./deck.svelte";
  import type { VolumeTarget } from "./types";

  type Props = {
    target: VolumeTarget;
    label: string;
    symbol: string;
  };

  let { target, label, symbol }: Props = $props();

  // Local mirror of the system volume. We mirror so dragging feels instant;
  // the server pushes back the same value (suppressed via `adjustingUntil`).
  let local = $state(0.6);
  let isDragging = $state(false);
  let trackEl: HTMLDivElement | null = $state(null);

  // Pull the latest server value into `local` whenever the deck is not being
  // dragged. This catches menu-bar / keyboard changes.
  $effect(() => {
    if (isDragging) return;
    if (deck.systemVolume == null) return;
    local = deck.systemVolume;
  });

  function setFromClientY(clientY: number) {
    if (!trackEl) return;
    const rect = trackEl.getBoundingClientRect();
    // Top of track = 1.0, bottom = 0.0.
    const ratio = 1 - (clientY - rect.top) / rect.height;
    const clamped = Math.max(0, Math.min(1, ratio));
    local = clamped;
    setVolume(target, clamped);
  }

  function onPointerDown(e: PointerEvent) {
    isDragging = true;
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    setFromClientY(e.clientY);
  }
  function onPointerMove(e: PointerEvent) {
    if (!isDragging) return;
    setFromClientY(e.clientY);
  }
  function onPointerUp(e: PointerEvent) {
    isDragging = false;
    (e.currentTarget as HTMLElement).releasePointerCapture(e.pointerId);
  }

  function onKey(e: KeyboardEvent) {
    // Arrow up/right bumps up, down/left bumps down. Shift = 5%, page = 10%.
    const step = e.shiftKey ? 0.05 : 0.02;
    let next = local;
    if (e.key === "ArrowUp" || e.key === "ArrowRight") next = local + step;
    else if (e.key === "ArrowDown" || e.key === "ArrowLeft") next = local - step;
    else if (e.key === "PageUp") next = local + 0.1;
    else if (e.key === "PageDown") next = local - 0.1;
    else if (e.key === "Home") next = 1;
    else if (e.key === "End") next = 0;
    else return;
    e.preventDefault();
    next = Math.max(0, Math.min(1, next));
    local = next;
    setVolume(target, next);
  }

  const percent = $derived(Math.round(local * 100));
  const muted = $derived(local < 0.005);
</script>

<div class="vol" class:dragging={isDragging}>
  <div class="header">
    <span class="symbol" aria-hidden="true">{symbolFor(symbol, muted)}</span>
    <span class="label">{label}</span>
  </div>

  <div
    class="track"
    bind:this={trackEl}
    role="slider"
    tabindex="0"
    aria-label="{label} volume"
    aria-valuemin="0"
    aria-valuemax="100"
    aria-valuenow={percent}
    onpointerdown={onPointerDown}
    onpointermove={onPointerMove}
    onpointerup={onPointerUp}
    onpointercancel={onPointerUp}
    onkeydown={onKey}
  >
    <div class="fill" style="height: {percent}%"></div>
    <div class="thumb" style="bottom: calc({percent}% - 12px)"></div>
  </div>

  <div class="readout">{percent}%</div>
</div>

<style>
  .vol {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 10px;
    padding: 12px;
    border-radius: var(--wd-radius);
    background: var(--wd-surface);
    box-shadow: 0 1px 0 rgba(255, 255, 255, 0.04) inset;
    user-select: none;
    -webkit-user-select: none;
    touch-action: none;
  }

  .header {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: 13px;
    color: color-mix(in srgb, var(--wd-text) 80%, transparent);
  }
  .symbol {
    font-size: 18px;
  }
  .label {
    font-weight: 600;
  }

  .track {
    position: relative;
    width: 56px;
    flex: 1;
    min-height: 140px;
    border-radius: 999px;
    background: color-mix(in srgb, var(--wd-text) 8%, transparent);
    overflow: visible;
    cursor: pointer;
    outline: none;
  }
  .track:focus-visible {
    box-shadow: 0 0 0 2px var(--wd-accent);
  }

  .fill {
    position: absolute;
    left: 0;
    right: 0;
    bottom: 0;
    border-radius: 999px;
    background: linear-gradient(
      to top,
      var(--wd-accent),
      color-mix(in srgb, var(--wd-accent) 70%, var(--wd-text))
    );
    transition: height 0.05s linear;
  }

  .thumb {
    position: absolute;
    left: 50%;
    transform: translateX(-50%);
    width: 28px;
    height: 28px;
    border-radius: 50%;
    background: var(--wd-text);
    box-shadow:
      0 2px 6px rgba(0, 0, 0, 0.35),
      0 0 0 2px color-mix(in srgb, var(--wd-accent) 40%, transparent);
    transition: bottom 0.05s linear;
  }

  .dragging .thumb {
    transform: translateX(-50%) scale(1.1);
  }

  .readout {
    font-size: 12px;
    color: color-mix(in srgb, var(--wd-text) 55%, transparent);
    font-variant-numeric: tabular-nums;
  }
</style>
