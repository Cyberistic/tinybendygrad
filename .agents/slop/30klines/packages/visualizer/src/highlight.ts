/**
 * Python highlighting for the coverage browser and the lesson player.
 *
 * speed-highlight's core is a tokenizer, not a renderer — `tokenizeWith` takes
 * the grammar as an argument, so no loader and no dynamic import means the
 * bundle is one file and the page can inline it.
 *
 * It is split by LINE here, on purpose: a token can span newlines (a docstring,
 * a triple-quoted string), and a gutter-based view needs balanced tags per row.
 * Splitting inside the token is the only way to get both.
 */
import { tokenizeWith } from "@speed-highlight/core/tokenize"
import py from "@speed-highlight/core/languages/py.js"

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")

/** One HTML string per source line, each safe to set as a row's innerHTML. */
export function highlightLines(src: string): string[] {
  const lines: string[] = [""]
  tokenizeWith(src, py, (text: string, type?: string) => {
    const parts = text.split("\n")
    for (let i = 0; i < parts.length; i++) {
      if (i > 0) lines.push("")
      const seg = parts[i]
      if (!seg) continue
      lines[lines.length - 1] += type ? `<span class="shj-syn-${type}">${esc(seg)}</span>` : esc(seg)
    }
  })
  return lines
}

export { highlightLines as highlightPython }
