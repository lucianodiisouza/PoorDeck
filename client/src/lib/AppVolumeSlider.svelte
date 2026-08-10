<script lang="ts">
  import { setAppVolume, toggleAppMute } from "./deck.svelte";
  import type { AudioApp } from "./types";

  type Props = { app: AudioApp };
  let { app }: Props = $props();

  // Local mirror so dragging feels instant; server echoes the same value
  // and we drop them via lastAppSent on the deck module.
  let local = $state(app.volume);
  let muted = $state(app.muted);
  let isDragging = $state(false);
  let trackEl: HTMLDivElement | null = $state(null);

  // Pull server changes in only when not actively dragging — that way a
  // second client moving the same slider doesn't fight the finger.
  $effect(() => {
    if (isDragging) return;
    local = app.volume;
    muted = app.muted;
  });

  function setFromClientX(clientX: number) {
    if (!trackEl) return;
    const rect = trackEl.getBoundingClientRect();
    // 0..1 across the track width. 0 = mute end (left), 1 = boost end (right).
    const ratio = (clientX - rect.left) / rect.width;
    const clamped = Math.max(0, Math.min(1, ratio)) * 2; // 0..2 (boost)
    // Unmuting happens implicitly when value > 0; the server will set muted=false.
    const nextMuted = clamped < 0.005;
    local = clamped;
    muted = nextMuted;
    setAppVolume(app.id, clamped, nextMuted);
  }

  function onPointerDown(e: PointerEvent) {
    isDragging = true;
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    setFromClientX(e.clientX);
  }
  function onPointerMove(e: PointerEvent) {
    if (!isDragging) return;
    setFromClientX(e.clientX);
  }
  function onPointerUp(e: PointerEvent) {
    isDragging = false;
    (e.currentTarget as HTMLElement).releasePointerCapture(e.pointerId);
  }

  function onKey(e: KeyboardEvent) {
    const step = e.shiftKey ? 0.1 : 0.05;
    let next = local;
    if (e.key === "ArrowRight" || e.key === "ArrowUp") next = local + step;
    else if (e.key === "ArrowLeft" || e.key === "ArrowDown") next = local - step;
    else if (e.key === "Home") next = 0;
    else if (e.key === "End") next = 1;
    else return;
    e.preventDefault();
    next = Math.max(0, Math.min(2, next));
    const nextMuted = next < 0.005;
    local = next;
    muted = nextMuted;
    setAppVolume(app.id, next, nextMuted);
  }

  function onMuteTap(e: MouseEvent) {
    e.stopPropagation();
    toggleAppMute(app.id);
  }

  // Fill percent of the visual 0..1 bar (capped at 100% even when boosting).
  const fillPercent = $derived(Math.min(100, (local / 1) * 100));
  const thumbLeft = $derived(Math.min(100, (local / 2) * 100));
  const effective = $derived(muted ? 0 : local);
  const percentLabel = $derived(Math.round(effective * 100));
</script>

<div class="row" class:muted class:paused={!app.playing}>
  {#if app.icon}
    <img class="icon" src={app.icon} alt="" />
  {:else}
    <div class="icon placeholder" aria-hidden="true">
      {app.name.slice(0, 1).toUpperCase()}
    </div>
  {/if}

  <div class="meta">
    <div class="name" title={app.name}>{app.name}</div>
    <div
      class="track"
      bind:this={trackEl}
      role="slider"
      tabindex="0"
      aria-label="{app.name} volume"
      aria-valuemin="0"
      aria-valuemax="200"
      aria-valuenow={Math.round(local * 100)}
      onpointerdown={onPointerDown}
      onpointermove={onPointerMove}
      onpointerup={onPointerUp}
      onpointercancel={onPointerUp}
      onkeydown={onKey}
    >
      <div class="fill" style="width: {fillPercent}%"></div>
      <div class="thumb" style="left: calc({thumbLeft}% - 9px)"></div>
    </div>
  </div>

  <button
    class="mute"
    class:on={muted}
    type="button"
    aria-label={muted ? "Unmute" : "Mute"}
    onclick={onMuteTap}
  >
    {#if muted}
      <span aria-hidden="true">🔇</span>
    {:else if app.playing}
      <span aria-hidden="true">🔊</span>
    {:else}
      <span aria-hidden="true">⏸</span>
    {/if}
  </button>
</div>

<style>
  .row {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 10px 12px;
    border-radius: var(--wd-radius);
    background: var(--wd-surface);
    box-shadow: 0 1px 0 rgba(255, 255, 255, 0.04) inset;
    user-select: none;
    -webkit-user-select: none;
    touch-action: none;
  }
  .row.muted {
    opacity: 0.7;
  }
  .row.paused {
    opacity: 0.55;
  }

  .icon {
    width: 30px;
    height: 30px;
    border-radius: 7px;
    object-fit: contain;
    flex-shrink: 0;
  }
  .icon.placeholder {
    display: grid;
    place-items: center;
    background: color-mix(in srgb, var(--wd-text) 12%, transparent);
    color: var(--wd-text);
    font-weight: 700;
    font-size: 14px;
  }

  .meta {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }
  .name {
    font-size: 12px;
    color: color-mix(in srgb, var(--wd-text) 80%, transparent);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .track {
    position: relative;
    height: 22px;
    border-radius: 999px;
    background: color-mix(in srgb, var(--wd-text) 8%, transparent);
    outline: none;
    cursor: pointer;
  }
  .track:focus-visible {
    box-shadow: 0 0 0 2px var(--wd-accent);
  }

  .fill {
    position: absolute;
    top: 0;
    bottom: 0;
    left: 0;
    border-radius: 999px;
    background: linear-gradient(
      to right,
      var(--wd-accent),
      color-mix(in srgb, var(--wd-accent) 70%, var(--wd-text))
    );
    transition: width 0.05s linear;
  }

  .thumb {
    position: absolute;
    top: 50%;
    transform: translateY(-50%);
    width: 18px;
    height: 18px;
    border-radius: 50%;
    background: var(--wd-text);
    box-shadow: 0 1px 4px rgba(0, 0, 0, 0.35);
    transition: left 0.05s linear;
  }

  .mute {
    width: 36px;
    height: 36px;
    border: none;
    border-radius: 50%;
    background: color-mix(in srgb, var(--wd-text) 8%, transparent);
    color: var(--wd-text);
    font-size: 16px;
    cursor: pointer;
    flex-shrink: 0;
    display: grid;
    place-items: center;
    transition: transform 0.08s ease, background 0.15s;
  }
  .mute:active {
    transform: scale(0.92);
  }
  .mute.on {
    background: var(--wd-accent);
    color: #fff;
  }
</style>
