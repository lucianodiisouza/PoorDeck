<script lang="ts">
  import { onMount } from "svelte";
  import { connect, deck, press } from "./lib/deck.svelte";

  let pageIndex = $state(0);
  const pages = $derived(deck.layout?.pages ?? []);
  const theme = $derived(deck.layout?.theme ?? null);
  const currentPage = $derived(pages[pageIndex] ?? null);

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

  // Clamp the page index if the layout shrinks.
  $effect(() => {
    if (pageIndex > pages.length - 1) pageIndex = Math.max(0, pages.length - 1);
  });

  onMount(connect);

  function tap(id: string) {
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
    <span class="title">{currentPage?.name ?? "WebDeck"}</span>
    <span class="status">
      {#if deck.status === "open"}connected
      {:else if deck.status === "connecting"}connecting…
      {:else}reconnecting…{/if}
    </span>
  </header>

  {#if currentPage}
    <section
      class="grid"
      style="grid-template-columns: repeat({currentPage.columns}, 1fr);"
    >
      {#each currentPage.buttons as button (button.id)}
        <button
          class="key"
          class:acked={deck.lastAck?.buttonId === button.id && deck.lastAck?.ok}
          onclick={() => tap(button.id)}
        >
          {#if button.icon}
            <img class="icon" src={button.icon} alt={button.label} draggable="false" />
          {:else}
            <span class="glyph">{button.label.slice(0, 1)}</span>
          {/if}
          <span class="label">{button.label}</span>
        </button>
      {/each}
    </section>

    {#if pages.length > 1}
      <footer class="dots">
        {#each pages as _, i}
          <span class="page-dot" class:active={i === pageIndex}></span>
        {/each}
      </footer>
    {/if}
  {:else}
    <div class="empty">
      {#if deck.status === "open"}Waiting for layout…{:else}Connecting to WebDeck…{/if}
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
    aspect-ratio: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 8px;
    border: none;
    border-radius: var(--wd-radius);
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
</style>
