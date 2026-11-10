import * as React from "react"
import { ChevronRightIcon, FileIcon, FolderIcon } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { cn } from "@/lib/utils"

/**
 * File Tree — the AI SDK Elements export surface, built on shadcn's Collapsible
 * and Button as the migration guide asks: FileTree / FileTreeFolder /
 * FileTreeFile / FileTreeIcon / FileTreeName / FileTreeActions, same names and
 * props, only the rendering changed.
 *
 * One documented deviation: this project's primitives are Radix, not Base UI,
 * so the trigger composes with `asChild` rather than `render={<Button/>}`.
 * Radix ignores `render` silently, which is how an earlier version produced a
 * bare, wrapping trigger instead of a button row.
 */
type Ctx = {
  selected?: string
  onSelect?: (path: string) => void
  expanded: Set<string>
  toggle: (path: string) => void
}

const FileTreeContext = React.createContext<Ctx>({ expanded: new Set(), toggle: () => {} })

export function FileTree({
  children,
  selected,
  onSelect,
  defaultOpen = true,
  className,
}: {
  children: React.ReactNode
  selected?: string
  onSelect?: (path: string) => void
  defaultOpen?: boolean
  className?: string
}) {
  const [expanded, setExpanded] = React.useState<Set<string>>(() => new Set())

  const toggle = React.useCallback((path: string) => {
    setExpanded((prev) => {
      const next = new Set(prev)
      next.has(path) ? next.delete(path) : next.add(path)
      return next
    })
  }, [])

  return (
    <FileTreeContext.Provider value={{ selected, onSelect, expanded, toggle }}>
      <div className={cn("flex w-full flex-col", className)} data-open-by-default={defaultOpen}>
        {children}
      </div>
    </FileTreeContext.Provider>
  )
}

export function FileTreeFolder({
  name,
  path,
  children,
  defaultOpen = true,
}: {
  name: string
  path: string
  children: React.ReactNode
  defaultOpen?: boolean
}) {
  const { expanded, toggle } = React.useContext(FileTreeContext)
  const open = expanded.size === 0 ? defaultOpen : expanded.has(path)

  return (
    <Collapsible
      open={open}
      onOpenChange={() => toggle(path)}
      className="group/folder"
    >
      <CollapsibleTrigger asChild>
        <Button
          variant="ghost"
          size="sm"
          className="w-full justify-start font-normal aria-expanded:bg-transparent aria-expanded:hover:bg-paper2"
        >
          <FileTreeIcon>
            <ChevronRightIcon className="transition-transform group-data-[state=open]/folder:rotate-90" />
          </FileTreeIcon>
          <FolderIcon />
          <FileTreeName>{name}</FileTreeName>
        </Button>
      </CollapsibleTrigger>
      <CollapsibleContent>
        <div className="ml-4 flex flex-col">{children}</div>
      </CollapsibleContent>
    </Collapsible>
  )
}

export function FileTreeFile({
  name,
  path,
  actions,
}: {
  name: string
  path: string
  actions?: React.ReactNode
}) {
  const { selected, onSelect } = React.useContext(FileTreeContext)
  const active = selected === path

  // Actions sit beside the Button, not inside it: a button inside a button is
  // invalid markup and swallows the inner click.
  return (
    <div className={cn("flex items-center", active && "bg-accent text-accent-foreground")}>
      <Button
        variant="ghost"
        size="sm"
        className={cn("min-w-0 flex-1 justify-start overflow-hidden font-normal", active && "bg-accent text-accent-foreground hover:bg-accent")}
        aria-current={active ? "true" : undefined}
        onClick={() => onSelect?.(path)}
      >
        <FileIcon />
        <FileTreeName>{name}</FileTreeName>
      </Button>
      {actions ? <div className="pr-2 text-[9px] font-semibold tracking-wide">{actions}</div> : null}
    </div>
  )
}

export function FileTreeIcon({ children }: { children: React.ReactNode }) {
  return <span className="flex size-4 shrink-0 items-center justify-center [&_svg]:size-4">{children}</span>
}

export function FileTreeName({ children }: { children: React.ReactNode }) {
  return <span className="truncate">{children}</span>
}

export function FileTreeActions({ children }: { children: React.ReactNode }) {
  return <span className="ml-auto flex items-center gap-1">{children}</span>
}
