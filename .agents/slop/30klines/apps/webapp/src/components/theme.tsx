import { createContext, useContext, useEffect, useState } from "react"

/**
 * Light/dark, as a class on <html>.
 *
 * The tokens are CSS variables under `:root` and `.dark`, so the flip is one
 * class and every utility follows — no component knows a colour. The initial
 * value is read before paint by an inline script in the document head, so the
 * page never flashes the wrong theme.
 */
export type Theme = "light" | "dark"

const KEY = "30k:theme"

const ThemeContext = createContext<{ theme: Theme; toggle: () => void }>({
  theme: "light",
  toggle: () => {},
})

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const [theme, setTheme] = useState<Theme>(() => {
    if (typeof document === "undefined") return "light"
    return document.documentElement.classList.contains("dark") ? "dark" : "light"
  })

  useEffect(() => {
    document.documentElement.classList.toggle("dark", theme === "dark")
    document.documentElement.style.colorScheme = theme
    try {
      localStorage.setItem(KEY, theme)
    } catch {
      // private mode: the class still applied, only the preference is lost
    }
  }, [theme])

  return (
    <ThemeContext.Provider value={{ theme, toggle: () => setTheme((t) => (t === "dark" ? "light" : "dark")) }}>
      {children}
    </ThemeContext.Provider>
  )
}

export const useTheme = () => useContext(ThemeContext)

/** Runs before paint; keep in sync with the effect above. */
export const themeScript = `(function(){try{var t=localStorage.getItem("${KEY}");var d=t?t==="dark":matchMedia("(prefers-color-scheme:dark)").matches;if(d)document.documentElement.classList.add("dark");document.documentElement.style.colorScheme=d?"dark":"light"}catch(e){}})()`
