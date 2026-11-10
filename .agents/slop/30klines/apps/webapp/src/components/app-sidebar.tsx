import { Link, useParams } from "@tanstack/react-router"
import {
  Sidebar,
  SidebarContent,
  SidebarGroup,
  SidebarGroupLabel,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
} from "@/components/ui/sidebar"
import course from "@/data/course.json"

type Lesson = { id: string; stage: string; title: string }

const lessons = course.lessons as Lesson[]
const stages = course.stages as { id: string; name: string; budget: number }[]

export function AppSidebar() {
  const params = useParams({ strict: false }) as { id?: string }

  return (
    <Sidebar collapsible="offcanvas" className="border-r border-rule">
      <SidebarHeader className="border-b border-rule px-3 py-3">
        <div className="text-[12px] font-semibold tracking-tight">30klinesofcode</div>
        <div className="text-[10px] text-faint">
          {lessons.length} lessons · 26,106 lines
        </div>
      </SidebarHeader>
      <SidebarContent>
        {stages.map((stage) => {
          const own = lessons.filter((l) => l.stage === stage.id).sort((a, b) => a.id.localeCompare(b.id))
          return (
            <SidebarGroup key={stage.id}>
              <SidebarGroupLabel className="text-[9.5px] uppercase tracking-[.14em] text-faint">
                <span className="mr-2 tabular-nums">{stage.id}</span>
                {stage.name}
              </SidebarGroupLabel>
              <SidebarMenu>
                {own.length === 0 ? (
                  <SidebarMenuItem>
                    <span className="px-2 py-1 text-[10.5px] text-faint/70">not written yet</span>
                  </SidebarMenuItem>
                ) : (
                  own.map((lesson) => (
                    <SidebarMenuItem key={lesson.id}>
                      <SidebarMenuButton
                        asChild
                        isActive={params.id === lesson.id}
                        className="h-8 text-[11px] data-[active=true]:bg-paper2 data-[active=true]:text-ink"
                      >
                        <Link to="/lesson/$id" params={{ id: lesson.id }}>
                          <span className="w-8 shrink-0 tabular-nums text-faint">{lesson.id}</span>
                          <span className="truncate">{lesson.title}</span>
                        </Link>
                      </SidebarMenuButton>
                    </SidebarMenuItem>
                  ))
                )}
              </SidebarMenu>
            </SidebarGroup>
          )
        })}
      </SidebarContent>
    </Sidebar>
  )
}
