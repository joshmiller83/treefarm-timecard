/**
 * Text writes that keep the element's text node. Assigning textContent replaces the node
 * (a removal and an insertion), which re-lays out the text from scratch and re-checks every
 * structural selector around it; changing the node's data only re-shapes the text. DayClock
 * writes a dozen clocks a frame while the page scrolls, so this matters.
 */
export function setText(el: Node | null | undefined, text: string): void {
  if (!el) return;
  const t = el.firstChild;
  if (t && t.nodeType === 3 && !t.nextSibling) {
    if ((t as Text).data !== text) (t as Text).data = text;
  } else if (el.textContent !== text) el.textContent = text;
}
