<script lang="ts">
  import { onMount } from "svelte";
  import { connect, deck, press, toggleMuteSystem } from "./lib/deck.svelte";
  import { formatShortcut } from "./lib/shortcut";
  import VolumeSlider from "./lib/VolumeSlider.svelte";
  import AppVolumeSlider from "./lib/AppVolumeSlider.svelte";

  let pageIndex = $state(0);
  let viewportW = $state(390);
  let viewportH = $state(700);
  const pages = $derived(deck.layout?.pages ?? []);
  const theme = $derived(deck.layout?.theme ?? null);
  const currentPage = $derived(pages[pageIndex] ?? null);
  const isVolumePage = $derived(currentPage?.id === "p4" ?? false);

  // Resolve the orientation we'll render for. An orientation lock
  // pinned to a page forces the layout (and the cell size cap) to
  // match that orientation even if the device is currently held the
  // other way. The page also exposes per-orientation column counts,
  // so the editor can set "3 columns portrait, 6 columns landscape"
  // and we pick the right one here.
  const renderOrientation = $derived.by((): "portrait" | "landscape" => {
    if (!currentPage) return viewportW > viewportH ? "landscape" : "portrait";
    if (currentPage.orientationLock) return currentPage.orientationLock;
    return viewportW > viewportH ? "landscape" : "portrait";
  });

  // When the editor's configured column count would be wrong for the
  // current orientation (the page only set `columns`, not the
  // portrait/landscape variants), phone landscape doubles it so the
  // page fits without scrolling.
  const effectiveColumns = $derived.by(() => {
    if (!currentPage) return 3;
    const perOrientation =
      renderOrientation === "portrait"
        ? currentPage.columnsPortrait
        : currentPage.columnsLandscape;
    if (perOrientation != null) return perOrientation;

    const isLandscape = renderOrientation === "landscape";
    const isPhoneSize = Math.max(viewportW, viewportH) < 900;
    if (isLandscape && isPhoneSize) {
      return Math.max(currentPage.columns, currentPage.columns * 2);
    }
    return currentPage.columns;
  });

  // True when the device is being held the wrong way relative to the
  // page's lock. We use this only to show a non-blocking hint when
  // the Screen Orientation API couldn't enforce the lock (older
  // Safari, missing permission). The actual lock attempt happens in
  // an effect below.
  const orientationMismatch = $derived.by(() => {
    if (!currentPage?.orientationLock) return false;
    return currentPage.orientationLock === "portrait"
      ? viewportW > viewportH
      : viewportW < viewportH;
  });

  // Per-cell size cap, in CSS pixels: the smaller of (column width,
  // available height / row count). Lets a 3-col 6-button page render
  // as 3x2 on any phone, regardless of orientation, without scrolling.
  // When the page pins a different orientation via orientationLock,
  // the cap uses that orientation's dimensions so the layout is
  // visually consistent (the user will see the same cell size once
  // they rotate the device to match).
  const cellMaxPx = $derived.by(() => {
    const cols = effectiveColumns;
    const buttons = currentPage?.buttons.length ?? 0;
    const rows = Math.max(1, Math.ceil(buttons / cols));
    // Swap width/height when the page is locked to the opposite
    // orientation from the device's current one.
    const locked = renderOrientation === "landscape";
    const widthAxis = locked ? viewportH : viewportW;
    const heightAxis = locked ? viewportW : viewportH;
    const widthFit = (widthAxis - 28 - (cols - 1) * 12) / cols;
    const heightAvailable = heightAxis - 40 - 16 - 30 - 40;
    const heightFit = heightAvailable / rows;
    return Math.max(40, Math.min(widthFit, heightFit));
  });

  function onResize() {
    viewportW = window.innerWidth;
    viewportH = window.innerHeight;
  }

  onMount(() => {
    onResize();
    window.addEventListener("resize", onResize);
    window.addEventListener("orientationchange", onResize);
    return () => {
      window.removeEventListener("resize", onResize);
      window.removeEventListener("orientationchange", onResize);
    };
  });

  // Keep the theme reflected onto CSS variables.
  $effect(() => {
    if (!theme) return;
    const root = document.documentElement.style;
    root.setProperty("--wd-bg", theme.background);
    root.setProperty("--wd-surface", theme.surface);
    root.setProperty("--wd-text", theme.text);
    root.setProperty("--wd-accent", theme.accent);
    root.setProperty("--wd-radius", `${theme.radius}px`);
  });

  // Enforce the page's orientation lock on the device itself. Safari
  // 16.4+ supports `screen.orientation.lock()` but it (a) requires a
  // user gesture in some contexts and (b) only takes effect if the
  // user grants the permission. We attempt it; on failure (older
  // Safari, denial) the `orientationMismatch` hint above tells the
  // user to rotate. We never rotate the content — the page renders
  // in the locked orientation and the user has to hold the device
  // the right way.
  $effect(() => {
    if (typeof screen === "undefined") return;
    const lock = currentPage?.orientationLock;
    const so = (screen as Screen & {
      orientation?: {
        lock?: (o: "portrait" | "landscape" | "any") => Promise<void>;
        unlock?: () => void;
      };
    }).orientation;
    if (!so) return;
    if (lock) {
      // Fire-and-forget; promise rejection (e.g. Safari pre-16.4, or
      // permission denied) just leaves the page in the device's
      // natural orientation and surfaces the hint.
      so.lock?.(lock).catch(() => {});
    } else {
      so.unlock?.();
    }
  });

  // Clamp the page index if the layout shrinks.
  $effect(() => {
    if (pageIndex > pages.length - 1) pageIndex = Math.max(0, pages.length - 1);
  });

  onMount(connect);

  function tap(id: string, button: import("./lib/types").Button) {
    if (button.action.kind === "volume" && button.id === "vol-mute") {
      toggleMuteSystem();
      if (navigator.vibrate) navigator.vibrate(8);
      return;
    }
    press(id);
    if (navigator.vibrate) navigator.vibrate(8);
  }

  // Horizontal swipe to switch pages.
  let touchStartX = 0;
  let touchStartY = 0;
  function onTouchStart(e: TouchEvent) {
    touchStartX = e.changedTouches[0].clientX;
    touchStartY = e.changedTouches[0].clientY;
  }
  function onTouchEnd(e: TouchEvent) {
    const dx = e.changedTouches[0].clientX - touchStartX;
    const dy = e.changedTouches[0].clientY - touchStartY;
    if (Math.abs(dx) < 60 || Math.abs(dx) < Math.abs(dy)) return;
    if (dx < 0 && pageIndex < pages.length - 1) pageIndex++;
    if (dx > 0 && pageIndex > 0) pageIndex--;
  }
</script>

<main
  class="deck"
  ontouchstart={onTouchStart}
  ontouchend={onTouchEnd}
>
  <header class="bar">
    <span class="dot" class:online={deck.status === "open"}></span>
    <span class="title">{currentPage?.name ?? "PoorDeck"}</span>
    <span class="status">
      {#if deck.status === "open"}connected
      {:else if deck.status === "connecting"}connecting…
      {:else}reconnecting…{/if}
    </span>
  </header>

  {#if currentPage}
    {#if orientationMismatch}
      <div class="rotate-overlay" role="status">
        <div class="rotate-card">
          <div class="rotate-icon">
            {#if currentPage.orientationLock === "portrait"}
              <span class="phone-portrait">📱</span>
              <span class="arrow">↻</span>
            {:else}
              <span class="phone-landscape">📱</span>
              <span class="arrow">↻</span>
            {/if}
          </div>
          <div class="rotate-text">
            Rotate to <b>{currentPage.orientationLock}</b>
          </div>
          <div class="rotate-sub">
            This page is locked to {currentPage.orientationLock}.
          </div>
        </div>
      </div>
    {/if}
    {#if isVolumePage}
      <!-- Custom render for the Volume page: master on top, then a
           live-updating list of apps. The list is dynamic (apps appear when
           they start playing, disappear when they stop) and lives entirely
           in the server-pushed `apps` state. -->
      <section class="volume-page">
        {#if deck.systemVolume != null}
          <div class="master-row">
            <VolumeSlider
              target="system"
              label="Master"
              symbol="speaker.wave.2.fill"
              orientation="horizontal"
            />
          </div>
        {/if}

        <div class="apps">
          <div class="apps-header">
            <span>Apps playing audio</span>
            <span class="apps-count">{deck.apps.length}</span>
          </div>
          {#if deck.apps.length === 0}
            <div class="apps-empty">
              Nothing playing right now. Start some audio on another app
              and it'll show up here.
            </div>
          {:else}
            <div class="apps-list">
              {#each deck.apps as app (app.id)}
                <AppVolumeSlider {app} />
              {/each}
            </div>
          {/if}
        </div>
      </section>
    {:else}
      <section
        class="grid"
        style="grid-template-columns: repeat({effectiveColumns}, 1fr); --wd-cell-max: {cellMaxPx}px;"
      >
        {#each currentPage.buttons as button (button.id)}
          <button
            class="key"
            class:acked={deck.lastAck?.buttonId === button.id && deck.lastAck?.ok}
            onclick={() => tap(button.id, button)}
          >
            {#if button.icon}
              <img class="icon" src={button.icon} alt={button.label} draggable="false" />
            {:else if button.action.kind === "keyShortcut" && button.action.shortcut}
              <span class="combo">{formatShortcut(button.action.shortcut)}</span>
            {:else}
              <span class="glyph">{button.label.slice(0, 1)}</span>
            {/if}
            <span class="label">{button.label}</span>
          </button>
        {/each}
      </section>
    {/if}

    {#if pages.length > 1}
      <footer class="dots">
        {#each pages as _, i}
          <span class="page-dot" class:active={i === pageIndex}></span>
        {/each}
      </footer>
    {/if}
  {:else}
    <div class="empty">
      {#if deck.status === "open"}Waiting for layout…{:else}Connecting to PoorDeck…{/if}
    </div>
  {/if}
</main>

<style>
  .deck {
    display: flex;
    flex-direction: column;
    height: 100%;
    padding: 14px;
    gap: 12px;
    transform-origin: center center;
  }

  .bar {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 15px;
  }
  .dot {
    width: 9px;
    height: 9px;
    border-radius: 50%;
    background: #d68a3a;
    transition: background 0.2s;
  }
  .dot.online {
    background: #48c774;
  }
  .title {
    font-weight: 600;
  }
  .status {
    margin-left: auto;
    color: color-mix(in srgb, var(--wd-text) 55%, transparent);
    font-size: 13px;
  }

  .grid {
    flex: 1;
    display: grid;
    gap: 12px;
    align-content: start;
  }

  .key {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 8px;
    border: none;
    border-radius: var(--wd-radius);
    width: 100%;
    aspect-ratio: 1;
    /* The grid's --wd-cell-max variable is set inline by App.svelte
       to min(viewportWidth/cols, viewportHeight/rows) so the cell
       can never grow large enough to push the row off-screen. */
    max-width: var(--wd-cell-max, 200px);
    max-height: var(--wd-cell-max, 200px);
    background: var(--wd-surface);
    color: var(--wd-text);
    cursor: pointer;
    transition: transform 0.08s ease, box-shadow 0.15s ease, background 0.15s;
    box-shadow: 0 1px 0 rgba(255, 255, 255, 0.04) inset;
  }
  .key:active {
    transform: scale(0.94);
    background: color-mix(in srgb, var(--wd-surface) 80%, var(--wd-accent));
  }
  .key.acked {
    box-shadow: 0 0 0 2px var(--wd-accent);
  }

  .icon {
    width: 46%;
    height: 46%;
    object-fit: contain;
    pointer-events: none;
  }
  .glyph {
    width: 46%;
    height: 46%;
    display: grid;
    place-items: center;
    font-size: 24px;
    font-weight: 700;
    border-radius: 12px;
    background: var(--wd-accent);
    color: #fff;
  }
  .combo {
    display: grid;
    place-items: center;
    min-width: 46%;
    padding: 8px 12px;
    font-size: 22px;
    font-weight: 600;
    border-radius: 12px;
    background: color-mix(in srgb, var(--wd-text) 10%, transparent);
    border: 1px solid color-mix(in srgb, var(--wd-text) 18%, transparent);
  }
  .label {
    font-size: 12px;
    opacity: 0.85;
    max-width: 100%;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .dots {
    display: flex;
    justify-content: center;
    gap: 7px;
    padding-bottom: 4px;
  }
  .page-dot {
    width: 7px;
    height: 7px;
    border-radius: 50%;
    background: color-mix(in srgb, var(--wd-text) 25%, transparent);
  }
  .page-dot.active {
    background: var(--wd-accent);
  }

  .empty {
    flex: 1;
    display: grid;
    place-items: center;
    color: color-mix(in srgb, var(--wd-text) 55%, transparent);
  }

  /* Shown when the page is locked to an orientation and the user
     is holding the device the other way. The screen-orientation
     lock attempt happens in an effect above; if it failed (older
     Safari, permission denied) this is the fallback. Non-blocking
     so the user can still see the deck behind it. */
  .rotate-overlay {
    position: fixed;
    inset: 0;
    display: grid;
    place-items: center;
    pointer-events: none;
    z-index: 100;
  }
  .rotate-card {
    pointer-events: auto;
    background: color-mix(in srgb, var(--wd-bg) 80%, transparent);
    backdrop-filter: blur(18px);
    -webkit-backdrop-filter: blur(18px);
    border: 1px solid color-mix(in srgb, var(--wd-text) 12%, transparent);
    border-radius: 18px;
    padding: 18px 22px;
    text-align: center;
    box-shadow: 0 12px 40px rgba(0, 0, 0, 0.35);
    max-width: 80%;
  }
  .rotate-icon {
    font-size: 36px;
    margin-bottom: 8px;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
  }
  .rotate-icon .arrow {
    color: var(--wd-accent);
    font-size: 28px;
  }
  .rotate-text {
    font-size: 18px;
    font-weight: 600;
    margin-bottom: 4px;
  }
  .rotate-sub {
    font-size: 12px;
    color: color-mix(in srgb, var(--wd-text) 60%, transparent);
  }

  /* ---- Volume page ---- */

  .volume-page {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 14px;
    overflow: hidden;
  }

  .master-row {
    display: flex;
    align-items: stretch;
  }

  .apps {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 8px;
    min-height: 0;
  }
  .apps-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    font-size: 12px;
    color: color-mix(in srgb, var(--wd-text) 60%, transparent);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }
  .apps-count {
    background: color-mix(in srgb, var(--wd-accent) 25%, transparent);
    color: var(--wd-text);
    padding: 2px 7px;
    border-radius: 999px;
    font-size: 11px;
    letter-spacing: 0;
  }
  .apps-list {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 8px;
    overflow-y: auto;
    padding-right: 2px;
  }
  .apps-empty {
    padding: 18px;
    border-radius: var(--wd-radius);
    background: color-mix(in srgb, var(--wd-surface) 60%, transparent);
    color: color-mix(in srgb, var(--wd-text) 55%, transparent);
    font-size: 13px;
    line-height: 1.4;
    text-align: center;
  }
</style>
