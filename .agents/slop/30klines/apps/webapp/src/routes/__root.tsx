import { createRootRoute, HeadContent, Link, Outlet, Scripts } from "@tanstack/react-router"
import { Moon, Sun } from "lucide-react"
import { SidebarInset, SidebarProvider, SidebarTrigger } from "@/components/ui/sidebar"
import { TooltipProvider } from "@/components/ui/tooltip"
import { AppSidebar } from "@/components/app-sidebar"
import { ThemeProvider, themeScript, useTheme } from "@/components/theme"
import appCss from "../index.css?url"

export const Route = createRootRoute({
  head: () => ({
    meta: [
      { charSet: "utf-8" },
      { name: "viewport", content: "width=device-width, initial-scale=1" },
      { title: "30klinesofcode" },
    ],
    links: [{ rel: "stylesheet", href: appCss }],
    // before paint, so the first frame is the right theme
    scripts: [{ children: themeScript }],
  }),
  shellComponent: RootShell,
  component: RootComponent,
})

function RootShell({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <head>
        <HeadContent />
      </head>
      <body>
        <ThemeProvider>
          <TooltipProvider>{children}</TooltipProvider>
        </ThemeProvider>
        <Scripts />
      </body>
    </html>
  )
}

function ThemeToggle() {
  const { theme, toggle } = useTheme()
  return (
    <button
      onClick={toggle}
      aria-label={theme === "dark" ? "switch to light" : "switch to dark"}
      className="ml-auto flex h-7 w-7 items-center justify-center border border-rule text-muted hover:border-rule2 hover:text-ink"
    >
      {theme === "dark" ? <Sun size={13} /> : <Moon size={13} />}
    </button>
  )
}

function RootComponent() {
  return (
    <SidebarProvider>
      <AppSidebar />
      <SidebarInset>
        <header className="flex h-11 shrink-0 items-center gap-3 border-b border-rule px-3">
          <SidebarTrigger className="-ml-1" />
          <span className="text-[11px] text-faint">tinygrad, line by line</span>
          <Link
            to="/compare"
            className="text-[11px] text-muted hover:text-ink"
            activeProps={{ className: "text-[11px] text-ink" }}
          >
            compare →
          </Link>
          <ThemeToggle />
        </header>
        <Outlet />
      </SidebarInset>
    </SidebarProvider>
  )
}
