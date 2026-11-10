/**
 * Python and Bend highlighting for the compare view.
 *
 * speed-highlight's core is a tokenizer, not a renderer — `tokenizeWith` takes
 * the grammar as an argument, so one bundle serves both languages with no
 * loader and no dynamic import.
 *
 * It is split by LINE on purpose: a token can span newlines (a docstring, a
 * triple-quoted string, a Bend block comment run), and a gutter-based view
 * needs balanced tags per row. Splitting inside the token is the only way to
 * get both.
 */
import { tokenizeWith } from "@speed-highlight/core/tokenize"
import py from "@speed-highlight/core/languages/py.js"

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")

/**
 * Bend has no grammar in the package. This is a small one: enough to read the
 * port, not a parser — keywords, comments, strings, chars, numbers and
 * constructors. Everything else stays plain, which is the honest failure mode
 * for a language this young.
 */
export const bend = [
  { match: /#.*/g, type: "cmnt" },
  { match: /"[^"\n]*"/g, type: "str" },
  { match: /'(\\.|[^'\\])'/g, type: "str" },
  { match: /\b\d+n?\b/g, type: "num" },
  {
    match: /\b(def|type|law|open|return|bend|fold|match|case|if|else|elif|when|with|let|use|import|as|for|in|and|or|not)\b/g,
    type: "kwd",
  },
  { match: /\b(true|false|None|Some|Bool|Nat|String|U32|U64|I32|F32|List|Tree|Array|Map)\b/g, type: "type" },
  { match: /\b[A-Z][A-Za-z0-9_]*\b/g, type: "class" },
  { match: /@[a-z]+/g, type: "section" },
  { match: /->|=>|[=+\-*/<>!&|]+/g, type: "oper" },
]

export type Lang = "py" | "bend"

/** One HTML string per source line, each safe to set as a row's innerHTML. */
export function highlightLines(src: string, lang: Lang = "py"): string[] {
  const grammar = lang === "bend" ? bend : py
  const lines: string[] = [""]
  tokenizeWith(src, grammar, (text: string, type?: string) => {
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
