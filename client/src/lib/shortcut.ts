import type { Modifier, Shortcut } from "./types";

const MODIFIER_SYMBOL: Record<Modifier, string> = {
  control: "⌃",
  option: "⌥",
  shift: "⇧",
  command: "⌘",
};

// macOS shows modifiers in a fixed order regardless of how they're listed.
const MODIFIER_ORDER: Modifier[] = ["control", "option", "shift", "command"];

const KEY_SYMBOL: Record<string, string> = {
  return: "↵",
  enter: "↵",
  space: "␣",
  tab: "⇥",
  escape: "⎋",
  esc: "⎋",
  delete: "⌫",
  backspace: "⌫",
  forwarddelete: "⌦",
  left: "←",
  right: "→",
  up: "↑",
  down: "↓",
};

/** Render a shortcut the way macOS menus do, e.g. ⌘↵ or ⌘⇧4. */
export function formatShortcut(shortcut: Shortcut): string {
  const mods = MODIFIER_ORDER.filter((m) => shortcut.modifiers.includes(m)).map(
    (m) => MODIFIER_SYMBOL[m],
  );
  const key = KEY_SYMBOL[shortcut.key.toLowerCase()] ?? shortcut.key.toUpperCase();
  return mods.join("") + key;
}
