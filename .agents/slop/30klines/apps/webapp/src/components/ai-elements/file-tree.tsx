import * as React from "react"
import { ChevronRightIcon, FileIcon, FolderIcon } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"

/**
 * File Tree, pasted from the shadcn AI Elements page.
 *
 * The docs are explicit that there is no registry item for this one: the
 * installation is `shadcn add collapsible button` (both are registry files in
 * `components/ui/`) and then the code below. So this file is the published
 * snippet, with exactly two deltas:
 *
 *   1. `FileTree` takes `nodes`/`selected`/`onSelect` instead of the demo's
 *      hardcoded array — the snippet ships a demo, and something has to lift it.
 *   2. `badge` renders after the name. It is the point of the compare page:
 *      which side is missing.
 *
 * No classes were invented. `bg-muted` is the one substitution, for
 * `bg-paper2`, because this project's token set has `muted` as a text colour
 * and no separate muted surface.
 */
type FileNode =
  | { type: "file"; name: string; path: string; badge?: React.ReactNode }
  | { type: "folder"; name: string; path: string; children: FileNode[] }

function FileTreeNode({
  node,
  selected,
  onSelect,
}: {
  node: FileNode
  selected?: string
  onSelect?: (path: string) => void
}) {
  switch (node.type) {
    case "folder":
      return (
        <Collapsible defaultOpen>
          <CollapsibleTrigger
            render={
              <Button
                variant="ghost"
                size="sm"
                className="w-full justify-start font-normal aria-expanded:bg-transparent aria-expanded:hover:bg-paper2"
              />
            }
          >
            <ChevronRightIcon className="transition-transform group-data-panel-open/button:rotate-90" />
            <FolderIcon />
            {node.name}
          </CollapsibleTrigger>
          <CollapsibleContent>
            <div className="ml-4 flex flex-col">
              {node.children.map((child) => (
                <FileTreeNode key={child.path} node={child} selected={selected} onSelect={onSelect} />
              ))}
            </div>
          </CollapsibleContent>
        </Collapsible>
      )
    case "file":
      return (
        <Button
          variant="ghost"
          size="sm"
          className={`w-full justify-start font-normal ${
            selected === node.path ? "bg-accent text-accent-foreground" : ""
          }`}
          aria-current={selected === node.path ? "true" : undefined}
          onClick={() => onSelect?.(node.path)}
        >
          <FileIcon />
          {node.name}
          {node.badge ? <span className="ml-auto text-[9px] font-semibold tracking-wide">{node.badge}</span> : null}
        </Button>
      )
    default: {
      const unreachable: never = node
      return unreachable
    }
  }
}

export function FileTree({
  nodes,
  selected,
  onSelect,
  className,
}: {
  nodes: FileNode[]
  selected?: string
  onSelect?: (path: string) => void
  className?: string
}) {
  return (
    <div className={`flex w-full flex-col ${className ?? ""}`}>
      {nodes.map((node) => (
        <FileTreeNode key={node.path} node={node} selected={selected} onSelect={onSelect} />
      ))}
    </div>
  )
}

export type { FileNode }
