// Maps the SF-Symbol-style names the desktop sends to plain Unicode glyphs the
// client can draw on a tile. The desktop is the source of truth for symbols;
// this is only the client's best-effort rendering of the ones we care about —
// chiefly the standard media / transport controls. Unknown names fall back to
// the button's first letter (handled by the caller).

const GLYPHS: Record<string, string> = {
  "playpause.fill": "⏯", // ⏯
  "play.fill": "▶", // ▶
  "pause.fill": "⏸", // ⏸
  "stop.fill": "⏹", // ⏹
  "forward.end.fill": "⏭", // ⏭
  "backward.end.fill": "⏮", // ⏮
  "forward.fill": "⏩", // ⏩
  "backward.fill": "⏪", // ⏪
  "speaker.slash.fill": "🔇", // 🔇
  "speaker.wave.1.fill": "🔈", // 🔈
  "speaker.wave.2.fill": "🔉", // 🔉
  "speaker.wave.3.fill": "🔊", // 🔊
};

/** The Unicode glyph for an SF-Symbol name, or null when we don't map it. */
export function symbolGlyph(symbol?: string | null): string | null {
  if (!symbol) return null;
  return GLYPHS[symbol] ?? null;
}
