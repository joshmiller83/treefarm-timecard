import { describe, expect, it } from 'vitest';
import { setText } from './text.ts';

/** A minimal element: a list of child nodes and textContent, as the DOM does it. */
function el(children: Array<{ nodeType: number; data?: string }>) {
  const e = {
    children,
    get firstChild() {
      const c = e.children[0];
      return c ? { ...c, get nextSibling() { return e.children[1] ?? null; }, get data(): string { return c.data ?? ''; }, set data(v: string) { c.data = v; } } : null;
    },
    get textContent() {
      return e.children.map((c) => c.data ?? '').join('');
    },
    set textContent(v: string) {
      e.children = [{ nodeType: 3, data: v }];
    },
  };
  return e;
}

describe('setText', () => {
  it('keeps the text node and changes its data', () => {
    const e = el([{ nodeType: 3, data: '2:14' }]);
    const node = e.children[0];
    setText(e as unknown as Node, '2:16');
    expect(e.textContent).toBe('2:16');
    expect(e.children[0]).toBe(node);
  });

  it('falls back to textContent for an empty or mixed element', () => {
    const empty = el([]);
    setText(empty as unknown as Node, 'On break');
    expect(empty.textContent).toBe('On break');
    const mixed = el([{ nodeType: 1 }, { nodeType: 3, data: 'b' }]);
    setText(mixed as unknown as Node, 'c');
    expect(mixed.children).toEqual([{ nodeType: 3, data: 'c' }]);
  });

  it('ignores a missing element', () => {
    expect(() => setText(null, 'x')).not.toThrow();
  });
});
