import * as React from "react"
import { ChevronRight, File as FileIcon, Folder as FolderIcon, FolderOpen } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { cn } from "@/lib/utils"

/**
 * File tree, as shadcn documents it: a folder is a Collapsible whose trigger is
 * a Button, a file is a Button, and the tree owns expansion and selection.
 *
 * Built here rather than pulled from a registry because the docs define it as
 * composition over Collapsible + Button, and those two are already installed —
 * a third copy of the pattern would be a fourth place for the chevron to point
 * the wrong way.
 */
export type FileNode = {
  name: string
  path: string
  type: "folder" | "file"
  children?: FileNode[]
  /** painted at the right edge: what the other side has, if anything */
  badge?: React.ReactNode
}

export function FileTree({
  nodes,
  selected,
  onSelect,
  defaultOpen = true,
  className,
}: {
  nodes: FileNode[]
  selected?: string
  onSelect?: (path: string) => void
  defaultOpen?: boolean
  className?: string
}) {
  const [expanded, setExpanded] = React.useState<Set<string>>(() => {
    const all = new Set<string>()
    if (!defaultOpen) return all
    const walk = (list: FileNode[]) =>
      list.forEach((n) => {
        if (n.type === "folder") {
          all.add(n.path)
          walk(n.children ?? [])
        }
      })
    walk(nodes)
    return all
  })

  const toggle = (path: string) =>
    setExpanded((prev) => {
      const next = new Set(prev)
      next.has(path) ? next.delete(path) : next.add(path)
      return next
    })

  return (
    <div className={cn("flex flex-col text-[10.5px]", className)} role="tree">
      {nodes.map((node) => (
        <TreeNode
          key={node.path}
          node={node}
          depth={0}
          expanded={expanded}
          toggle={toggle}
          selected={selected}
          onSelect={onSelect}
        />
      ))}
    </div>
  )
}

function TreeNode({
  node,
  depth,
  expanded,
  toggle,
  selected,
  onSelect,
}: {
  node: FileNode
  depth: number
  expanded: Set<string>
  toggle: (path: string) => void
  selected?: string
  onSelect?: (path: string) => void
}) {
  const pad = { paddingLeft: 6 + depth * 12 }

  if (node.type === "folder") {
    const open = expanded.has(node.path)
    return (
      <Collapsible open={open} onOpenChange={() => toggle(node.path)}>
        <CollapsibleTrigger
          render={
            <Button
              variant="ghost"
              size="sm"
              className="h-6 w-full justify-start rounded-none px-1 font-mono text-[10.5px] text-muted hover:text-ink"
              style={pad}
            />
          }
        >
          <ChevronRight className={cn("size-3 shrink-0 transition-transform", open && "rotate-90")} />
          {open ? <FolderOpen className="size-3 shrink-0" /> : <FolderIcon className="size-3 shrink-0" />}
          <span className="truncate">{node.name}</span>
        </CollapsibleTrigger>
        <CollapsibleContent>
          {node.children?.map((child) => (
            <TreeNode
              key={child.path}
              node={child}
              depth={depth + 1}
              expanded={expanded}
              toggle={toggle}
              selected={selected}
              onSelect={onSelect}
            />
          ))}
        </CollapsibleContent>
      </Collapsible>
    )
  }

  const active = selected === node.path
  return (
    <Button
      variant="ghost"
      size="sm"
      onClick={() => onSelect?.(node.path)}
      className={cn(
        "h-6 w-full justify-start gap-1.5 rounded-none px-1 font-mono text-[10.5px] font-normal",
        active ? "bg-paper2 text-ink shadow-[inset_2px_0_0_0_var(--accent)]" : "text-muted hover:text-ink",
      )}
      style={pad}
    >
      <FileIcon className="size-3 shrink-0 opacity-50" />
      <span className="truncate">{node.name}</span>
      {node.badge ? <span className="ml-auto pr-1 text-[9px] font-semibold tracking-wide text-faint">{node.badge}</span> : null}
    </Button>
  )
}
