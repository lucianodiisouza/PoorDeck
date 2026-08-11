<script lang="ts">
  import { onMount } from "svelte";
  import {
    activateApp,
    connect,
    deck,
    press,
    toggleMuteSystem,
  } from "./lib/deck.svelte";
  import { formatShortcut } from "./lib/shortcut";
  import { symbolGlyph } from "./lib/symbols";
  import VolumeSlider from "./lib/VolumeSlider.svelte";
  import AppVolumeSlider from "./lib/AppVolumeSlider.svelte";

  let pageIndex = $state(0);
  // Device orientation, from matchMedia (re-fires on rotation on its
  // own). Only used for the orientation-lock hint and to pick an
  // explicit per-orientation column count if the editor set one.
  let deviceLandscape = $state(false);
  // The grid's real measured content box, from a ResizeObserver. This
  // is what drives the auto-fit packing below — measuring the actual
  // box means no magic numbers and it re-solves on rotation for free.
  let gridEl = $state<HTMLElement | null>(null);
  let gridW = $state(0);
  let gridH = $state(0);
  const GAP = 12;
  const KEY_MAX = 220; // don't let keys get comical on iPad / desktop

  // How keys use the space:
  //  • "square" — keys stay square, sized to the biggest square that
  //    fits; the block is centered (a thin margin on the non-binding
  //    axis is unavoidable for squares).
  //  • "fill"  — keys stretch to fill every cell edge-to-edge, so there
  //    is zero empty space; keys become rectangular.
  // Persisted per-device so the choice sticks across reloads / PWA.
  type FitMode = "square" | "fill";
  const loadFit = (): FitMode => {
    try {
      return localStorage.getItem("poordeck.fit") === "fill"
        ? "fill"
        : "square";
    } catch {
      return "square";
    }
  };
  let fitMode = $state<FitMode>(loadFit());
  function setFit(mode: FitMode) {
    fitMode = mode;
    try {
      localStorage.setItem("poordeck.fit", mode);
    } catch {
      /* private mode / storage disabled — just don't persist */
    }
  }

  // Running as an installed PWA (no browser chrome). When true we
  // reclaim the chrome we no longer need: tighter padding and a larger
  // key cap, so the deck uses the roomier canvas.
  let standalone = $state(false);
  // Roomier cap once installed — there's no URL bar eating the screen.
  const keyMax = $derived(standalone ? 280 : KEY_MAX);

  // "Add to Home Screen" CTA. On Android/Chrome we capture the
  // `beforeinstallprompt` event and drive a native prompt; iOS has no
  // such API, so we show a short "Share → Add to Home Screen" hint.
  // Never shown once installed, and dismissible (persisted).
  let installEvt = $state<{
    prompt: () => void;
    userChoice: Promise<unknown>;
  } | null>(null);
  let installDismissed = $state(false);
  const isIOS =
    typeof navigator !== "undefined" &&
    (/iphone|ipad|ipod/.test(navigator.userAgent.toLowerCase()) ||
      (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1));
  const showInstall = $derived(
    !standalone && !installDismissed && (installEvt != null || isIOS),
  );
  function dismissInstall() {
    installDismissed = true;
    try {
      localStorage.setItem("poordeck.installDismissed", "1");
    } catch {
      /* ignore */
    }
  }
  async function doInstall() {
    if (!installEvt) return;
    installEvt.prompt();
    try {
      await installEvt.userChoice;
    } finally {
      installEvt = null;
    }
  }

  const pages = $derived(deck.layout?.pages ?? []);
  const theme = $derived(deck.layout?.theme ?? null);
  const currentPage = $derived(pages[pageIndex] ?? null);
  // The Volume page gets a bespoke render (master + live app list). Detect
  // it by content, not a hardcoded id — inserting the Media page shifted
  // ids once already and left this pointing at the wrong page.
  const isVolumePage = $derived(
    currentPage?.buttons.some((b) => b.action.kind === "volume") ?? false,
  );
  // The Dock page (stable id "dock") renders the live running-apps list the
  // server pushes, not static buttons.
  const isDockPage = $derived(currentPage?.id === "dock");
  // How many tiles the grid lays out — dock apps on the Dock page,
  // otherwise the page's buttons. Feeds the auto-fit packing below.
  const itemCount = $derived(
    isDockPage ? deck.dock.length : (currentPage?.buttons.length ?? 0),
  );

  // Resolve the orientation we'll render for. An orientation lock
  // pinned to a page forces the layout to match that orientation even
  // if the device is currently held the other way.
  const renderOrientation = $derived.by((): "portrait" | "landscape" => {
    if (currentPage?.orientationLock) return currentPage.orientationLock;
    return deviceLandscape ? "landscape" : "portrait";
  });

  // Pick the column count that best uses the measured grid box, given
  // the fit mode, and adapts to orientation for free. An explicit
  // per-orientation column count from the editor still wins, if set.
  //   • square — maximize the fitting square edge (biggest keys).
  //   • fill   — minimize the cell's aspect distortion, so full-bleed
  //     cells stay as close to square as the screen allows.
  const effectiveColumns = $derived.by(() => {
    if (!currentPage) return 3;
    const explicit =
      renderOrientation === "portrait"
        ? currentPage.columnsPortrait
        : currentPage.columnsLandscape;
    if (explicit != null) return explicit;

    const n = itemCount;
    if (n <= 1) return 1;
    // Before the first measurement, fall back to the page's hint.
    if (gridW === 0 || gridH === 0) return currentPage.columns;

    let bestCols = 1;
    let bestScore = -Infinity;
    for (let cols = 1; cols <= n; cols++) {
      const rows = Math.ceil(n / cols);
      const cellW = (gridW - (cols - 1) * GAP) / cols;
      const cellH = (gridH - (rows - 1) * GAP) / rows;
      if (cellW <= 0 || cellH <= 0) continue;
      // Higher is better.
      //   square — the fitting square edge (biggest keys).
      //   fill   — closest to 1:1 cells, but penalize empty trailing
      //     cells so we don't pick a shape that strands a near-empty
      //     last row (which would just be dead space again).
      let score: number;
      if (fitMode === "fill") {
        const aspect = Math.max(cellW, cellH) / Math.min(cellW, cellH);
        const empties = cols * rows - n;
        score = -(aspect + 0.6 * empties);
      } else {
        score = Math.min(cellW, cellH);
      }
      // Strictly-greater keeps the fewest columns among ties, which
      // reads calmer (fuller rows over a tall stack of near-equal size).
      if (score > bestScore + 1e-6) {
        bestScore = score;
        bestCols = cols;
      }
    }
    return bestCols;
  });

  // Row count for the chosen columns. Feeds the CSS grid template.
  const rowCount = $derived.by(() =>
    Math.max(1, Math.ceil(itemCount / effectiveColumns)),
  );

  // The square key edge, in px, for the chosen grid on the measured
  // box. Capped so keys stay sane on large screens. Computed here (not
  // in CSS) because we already have the exact numbers from the
  // ResizeObserver — no container-query rounding to reason about.
  const keyPx = $derived.by(() => {
    const cols = effectiveColumns;
    const rows = rowCount;
    if (gridW === 0 || gridH === 0) return keyMax;
    const cellW = (gridW - (cols - 1) * GAP) / cols;
    const cellH = (gridH - (rows - 1) * GAP) / rows;
    return Math.max(40, Math.min(cellW, cellH, keyMax));
  });

  // True when the device is being held the wrong way relative to the
  // page's lock. We use this only to show a non-blocking hint when
  // the Screen Orientation API couldn't enforce the lock (older
  // Safari, missing permission). The actual lock attempt happens in
  // an effect below.
  const orientationMismatch = $derived.by(() => {
    if (!currentPage?.orientationLock) return false;
    return currentPage.orientationLock === "portrait"
      ? deviceLandscape
      : !deviceLandscape;
  });

  onMount(() => {
    const landscapeMq = window.matchMedia("(orientation: landscape)");
    const standaloneMq = window.matchMedia("(display-mode: standalone)");
    const sync = () => {
      deviceLandscape = landscapeMq.matches;
      // iOS reports install state via navigator.standalone, not the
      // display-mode media query.
      standalone =
        standaloneMq.matches ||
        (navigator as Navigator & { standalone?: boolean }).standalone ===
          true;
    };
    sync();
    try {
      installDismissed =
        localStorage.getItem("poordeck.installDismissed") === "1";
    } catch {
      /* ignore */
    }

    // Android/Chrome: intercept the browser's install prompt so we can
    // offer it from our own CTA at a better moment.
    const onBIP = (e: Event) => {
      e.preventDefault();
      installEvt = e as unknown as typeof installEvt;
    };
    const onInstalled = () => {
      installEvt = null;
      standalone = true;
    };
    window.addEventListener("beforeinstallprompt", onBIP);
    window.addEventListener("appinstalled", onInstalled);
    landscapeMq.addEventListener("change", sync);
    standaloneMq.addEventListener("change", sync);
    return () => {
      window.removeEventListener("beforeinstallprompt", onBIP);
      window.removeEventListener("appinstalled", onInstalled);
      landscapeMq.removeEventListener("change", sync);
      standaloneMq.removeEventListener("change", sync);
    };
  });

  // Measure the grid box and keep gridW/gridH in sync. A ResizeObserver
  // catches rotation, the Safari toolbar collapsing, and font-size
  // changes — everything that alters the available area — without any
  // resize listeners or viewport math.
  $effect(() => {
    if (!gridEl) return;
    const ro = new ResizeObserver((entries) => {
      const box = entries[0].contentRect;
      gridW = box.width;
      gridH = box.height;
    });
    ro.observe(gridEl);
    return () => ro.disconnect();
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
  class:standalone
  ontouchstart={onTouchStart}
  ontouchend={onTouchEnd}
>
  <header class="bar">
    <span class="dot" class:online={deck.status === "open"}></span>
    <span class="title">{currentPage?.name ?? "PoorDeck"}</span>
    <div class="fit-toggle" role="group" aria-label="Button fit">
      <button
        type="button"
        class:active={fitMode === "square"}
        onclick={() => setFit("square")}
        aria-label="Square keys"
        aria-pressed={fitMode === "square"}
        title="Square — biggest square keys, centered"
      >
        <svg viewBox="0 0 16 16" aria-hidden="true">
          <rect x="1.5" y="1.5" width="5.5" height="5.5" rx="1.2" />
          <rect x="9" y="1.5" width="5.5" height="5.5" rx="1.2" />
          <rect x="1.5" y="9" width="5.5" height="5.5" rx="1.2" />
          <rect x="9" y="9" width="5.5" height="5.5" rx="1.2" />
        </svg>
      </button>
      <button
        type="button"
        class:active={fitMode === "fill"}
        onclick={() => setFit("fill")}
        aria-label="Fill keys"
        aria-pressed={fitMode === "fill"}
        title="Fill — keys stretch to fill the screen"
      >
        <svg viewBox="0 0 16 16" aria-hidden="true">
          <rect x="1.5" y="1.5" width="13" height="13" rx="1.8" />
        </svg>
      </button>
    </div>
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
    {#if isDockPage}
      <!-- Dock page: a live grid of the Mac's running apps. Tapping one
           brings it to the front. The frontmost app gets the accent ring.
           The list is server-pushed (`deck.dock`) and updates as apps
           launch, quit, or change focus. -->
      {#if deck.dock.length === 0}
        <div class="empty">No apps running.</div>
      {:else}
        <section
          class="grid"
          class:fill={fitMode === "fill"}
          bind:this={gridEl}
          style="--cols: {effectiveColumns}; --rows: {rowCount}; --key: {keyPx}px;"
        >
          {#each deck.dock as app (app.id)}
            <button
              class="key"
              class:acked={app.active}
              onclick={() => {
                activateApp(app.id);
                if (navigator.vibrate) navigator.vibrate(8);
              }}
            >
              {#if app.icon}
                <img class="icon" src={app.icon} alt={app.name} draggable="false" />
              {:else}
                <span class="glyph">{app.name.slice(0, 1)}</span>
              {/if}
              <span class="label">{app.name}</span>
            </button>
          {/each}
        </section>
      {/if}
    {:else if isVolumePage}
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
        class:fill={fitMode === "fill"}
        bind:this={gridEl}
        style="--cols: {effectiveColumns}; --rows: {rowCount}; --key: {keyPx}px;"
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
            {:else if symbolGlyph(button.symbol)}
              <span class="glyph symbol-glyph">{symbolGlyph(button.symbol)}</span>
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

  {#if showInstall}
    <aside class="install" role="note">
      <img class="install-icon" src="./icons/icon-192.png" alt="" />
      <div class="install-text">
        {#if installEvt}
          <b>Install PoorDeck</b>
          <span>Full-screen, one tap from your home screen.</span>
        {:else}
          <b>Add to Home Screen</b>
          <span>Tap Share, then “Add to Home Screen”.</span>
        {/if}
      </div>
      {#if installEvt}
        <button class="install-add" onclick={doInstall}>Add</button>
      {/if}
      <button
        class="install-x"
        onclick={dismissInstall}
        aria-label="Dismiss">✕</button
      >
    </aside>
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
  /* Installed PWA: no browser chrome, so tighten our own padding and
     let keys breathe into the reclaimed space. */
  .deck.standalone {
    padding: 8px 10px;
    gap: 8px;
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
    color: color-mix(in srgb, var(--wd-text) 55%, transparent);
    font-size: 13px;
  }

  /* Segmented square / fill toggle. Pushed to the right; status trails it. */
  .fit-toggle {
    margin-left: auto;
    display: inline-flex;
    padding: 2px;
    gap: 2px;
    border-radius: 999px;
    background: color-mix(in srgb, var(--wd-text) 8%, transparent);
  }
  .fit-toggle button {
    display: grid;
    place-items: center;
    width: 30px;
    height: 26px;
    padding: 0;
    border: none;
    border-radius: 999px;
    background: transparent;
    color: color-mix(in srgb, var(--wd-text) 55%, transparent);
    cursor: pointer;
    transition: background 0.15s, color 0.15s;
  }
  .fit-toggle button svg {
    width: 15px;
    height: 15px;
    fill: currentColor;
  }
  .fit-toggle button.active {
    background: var(--wd-accent);
    color: #fff;
  }

  .grid {
    flex: 1;
    min-height: 0;
    display: grid;
    gap: 12px;
  }
  /* Square mode: --cols / --rows / --key are set inline from the
     auto-fit packing. Tracks are sized to the square key so keys stay
     packed with a uniform gap; the block is centered in the leftover
     space rather than spread out with holes between rows. */
  .grid:not(.fill) {
    grid-template-columns: repeat(var(--cols), var(--key, 180px));
    grid-template-rows: repeat(var(--rows), var(--key, 180px));
    place-content: center;
  }
  /* Fill mode: cells stretch to consume every pixel — zero margin,
     rectangular keys. */
  .grid.fill {
    grid-template-columns: repeat(var(--cols), 1fr);
    grid-template-rows: repeat(var(--rows), 1fr);
  }

  .key {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 6%;
    border: none;
    border-radius: var(--wd-radius);
    /* Square mode: fixed square edge. Fill mode overrides to 100%. */
    width: var(--key, 180px);
    height: var(--key, 180px);
    /* Query container so icon + label scale with the button's real
       size (cqmin = the shorter edge) — works in both square and fill
       mode with no JS. */
    container-type: size;
    background: var(--wd-surface);
    color: var(--wd-text);
    cursor: pointer;
    transition: transform 0.08s ease, box-shadow 0.15s ease, background 0.15s;
    box-shadow: 0 1px 0 rgba(255, 255, 255, 0.04) inset;
  }
  .grid.fill .key {
    width: 100%;
    height: 100%;
  }
  .key:active {
    transform: scale(0.94);
    background: color-mix(in srgb, var(--wd-surface) 80%, var(--wd-accent));
  }
  .key.acked {
    box-shadow: 0 0 0 2px var(--wd-accent);
  }

  /* Sizes are in cqmin (% of the button's shorter edge) so art + text
     scale with the key, in both square and fill mode. */
  .icon {
    width: 56cqmin;
    height: 56cqmin;
    object-fit: contain;
    pointer-events: none;
  }
  .glyph {
    width: 54cqmin;
    height: 54cqmin;
    display: grid;
    place-items: center;
    font-size: 30cqmin;
    font-weight: 700;
    border-radius: 14%;
    background: var(--wd-accent);
    color: #fff;
  }
  /* Media / transport glyphs: no tile, just a big glyph filling the key. */
  .symbol-glyph {
    width: auto;
    height: auto;
    background: none;
    color: var(--wd-text);
    font-size: 64cqmin;
    line-height: 1;
  }
  .combo {
    display: grid;
    place-items: center;
    min-width: 46%;
    padding: 0.4em 0.6em;
    font-size: 22cqmin;
    font-weight: 600;
    border-radius: 12px;
    background: color-mix(in srgb, var(--wd-text) 10%, transparent);
    border: 1px solid color-mix(in srgb, var(--wd-text) 18%, transparent);
  }
  .label {
    font-size: clamp(11px, 15cqmin, 20px);
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

  /* ---- Install (Add to Home Screen) CTA ---- */

  .install {
    position: fixed;
    left: max(12px, env(safe-area-inset-left));
    right: max(12px, env(safe-area-inset-right));
    bottom: max(12px, env(safe-area-inset-bottom));
    z-index: 90;
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 10px 12px;
    border-radius: 16px;
    background: color-mix(in srgb, var(--wd-surface) 92%, var(--wd-bg));
    border: 1px solid color-mix(in srgb, var(--wd-text) 12%, transparent);
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.4);
    animation: install-in 0.25s ease;
  }
  @keyframes install-in {
    from {
      opacity: 0;
      transform: translateY(8px);
    }
  }
  .install-icon {
    width: 38px;
    height: 38px;
    border-radius: 9px;
    flex: none;
  }
  .install-text {
    display: flex;
    flex-direction: column;
    gap: 1px;
    min-width: 0;
    font-size: 13px;
  }
  .install-text b {
    font-weight: 600;
  }
  .install-text span {
    color: color-mix(in srgb, var(--wd-text) 60%, transparent);
    font-size: 12px;
  }
  .install-add {
    margin-left: auto;
    flex: none;
    padding: 8px 16px;
    border: none;
    border-radius: 999px;
    background: var(--wd-accent);
    color: #fff;
    font-size: 14px;
    font-weight: 600;
    cursor: pointer;
  }
  .install-x {
    flex: none;
    margin-left: auto;
    width: 30px;
    height: 30px;
    display: grid;
    place-items: center;
    border: none;
    border-radius: 999px;
    background: color-mix(in srgb, var(--wd-text) 10%, transparent);
    color: color-mix(in srgb, var(--wd-text) 70%, transparent);
    font-size: 13px;
    cursor: pointer;
  }
  /* When the Add button is present it owns the right side; the ✕ then
     sits snug next to it rather than pushing to the far edge. */
  .install-add ~ .install-x {
    margin-left: 0;
  }
</style>
