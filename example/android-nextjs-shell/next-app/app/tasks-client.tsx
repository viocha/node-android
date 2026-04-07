"use client"

import { type FormEvent, useEffect, useMemo, useRef, useState } from "react"
import {
  CheckCircle2,
  CircleDashed,
  LoaderCircle,
  PencilLine,
  PlayCircle,
  Plus,
  Trash2,
  X,
} from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Textarea } from "@/components/ui/textarea"
import type { Task, TaskPriority, TaskStatus, TaskSummary } from "@/lib/store"

type TasksResponse = {
  ok: boolean
  tasks: Task[]
  summary: TaskSummary
  message?: string
}

type EditDraft = {
  id: string
  title: string
  details: string
  priority: TaskPriority
  status: TaskStatus
}

type TasksClientProps = {
  initialTasks: Task[]
  initialSummary: TaskSummary
}

const statusCopy: Record<TaskStatus, string> = {
  backlog: "Backlog",
  in_progress: "In Progress",
  done: "Done",
}

const priorityCopy: Record<TaskPriority, string> = {
  low: "Low",
  medium: "Medium",
  high: "High",
}

async function fetchTasks(input: RequestInfo, init?: RequestInit) {
  const response = await fetch(input, {
    cache: "no-store",
    ...init,
  })
  const payload = (await response.json()) as TasksResponse

  if (!response.ok || !payload.ok) {
    throw new Error(payload.message || `Request failed: ${response.status}`)
  }

  return payload
}

function formatTimestamp(value: string) {
  return new Date(value).toLocaleString("zh-CN", {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  })
}

function nextStatus(status: TaskStatus): TaskStatus {
  if (status === "backlog") return "in_progress"
  if (status === "in_progress") return "done"
  return "backlog"
}

function actionLabel(status: TaskStatus) {
  if (status === "backlog") return "Start"
  if (status === "in_progress") return "Complete"
  return "Reopen"
}

function actionIcon(status: TaskStatus) {
  if (status === "backlog") return PlayCircle
  if (status === "in_progress") return CheckCircle2
  return CircleDashed
}

function SummaryTile({
  label,
  value,
  tone,
}: {
  label: string
  value: string
  tone: string
}) {
  return (
    <Card className="border-border/70 bg-white/85 shadow-sm">
      <CardContent className="px-4 py-4">
        <p className="text-[11px] uppercase tracking-[0.22em] text-muted-foreground">{label}</p>
        <p className={`mt-2 text-3xl font-semibold tracking-tight ${tone}`}>{value}</p>
      </CardContent>
    </Card>
  )
}

export default function TasksClient({
  initialTasks,
  initialSummary,
}: TasksClientProps) {
  const createDialogHistoryEntry = useRef(false)
  const closingCreateDialogFromPopstate = useRef(false)
  const [tasks, setTasks] = useState(initialTasks)
  const [summary, setSummary] = useState(initialSummary)
  const [title, setTitle] = useState("")
  const [details, setDetails] = useState("")
  const [priority, setPriority] = useState<TaskPriority>("medium")
  const [pendingAction, setPendingAction] = useState<string | null>(null)
  const [createDialogOpen, setCreateDialogOpen] = useState(false)
  const [editingTaskId, setEditingTaskId] = useState<string | null>(null)
  const [editDraft, setEditDraft] = useState<EditDraft | null>(null)
  const [message, setMessage] = useState("Everything stays on-device and is saved by the embedded backend.")

  const grouped = useMemo(() => {
    return {
      backlog: tasks.filter((task) => task.status === "backlog"),
      in_progress: tasks.filter((task) => task.status === "in_progress"),
      done: tasks.filter((task) => task.status === "done"),
    }
  }, [tasks])

  useEffect(() => {
    if (!createDialogOpen) return

    window.history.pushState({ nextShellDialog: "create-task" }, "")
    createDialogHistoryEntry.current = true

    const handlePopState = () => {
      if (!createDialogOpen) return
      closingCreateDialogFromPopstate.current = true
      setCreateDialogOpen(false)
    }

    window.addEventListener("popstate", handlePopState)
    return () => {
      window.removeEventListener("popstate", handlePopState)
    }
  }, [createDialogOpen])

  useEffect(() => {
    if (createDialogOpen) return
    if (!createDialogHistoryEntry.current) return

    if (closingCreateDialogFromPopstate.current) {
      closingCreateDialogFromPopstate.current = false
      createDialogHistoryEntry.current = false
      return
    }

    createDialogHistoryEntry.current = false
    window.history.back()
  }, [createDialogOpen])

  async function handleCreate(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setPendingAction("create")
    setMessage("Creating task...")

    try {
      const payload = await fetchTasks("/api/tasks", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ title, details, priority }),
      })

      setTasks(payload.tasks)
      setSummary(payload.summary)
      setTitle("")
      setDetails("")
      setPriority("medium")
      setCreateDialogOpen(false)
      setMessage("Task created.")
    } catch (error) {
      setMessage((error as Error).message)
    } finally {
      setPendingAction(null)
    }
  }

  async function handleAdvance(task: Task) {
    setPendingAction(task.id)
    setMessage(`Updating “${task.title}”...`)

    try {
      const payload = await fetchTasks("/api/tasks", {
        method: "PATCH",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          id: task.id,
          status: nextStatus(task.status),
        }),
      })

      setTasks(payload.tasks)
      setSummary(payload.summary)
      setMessage(`Updated “${task.title}”.`)
    } catch (error) {
      setMessage((error as Error).message)
    } finally {
      setPendingAction(null)
    }
  }

  function beginEdit(task: Task) {
    setEditingTaskId(task.id)
    setEditDraft({
      id: task.id,
      title: task.title,
      details: task.details,
      priority: task.priority,
      status: task.status,
    })
    setMessage(`Editing “${task.title}”.`)
  }

  function cancelEdit() {
    setEditingTaskId(null)
    setEditDraft(null)
    setMessage("Edit cancelled.")
  }

  async function handleSaveEdit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!editDraft) return

    setPendingAction(`edit:${editDraft.id}`)
    setMessage(`Saving “${editDraft.title}”...`)

    try {
      const payload = await fetchTasks("/api/tasks", {
        method: "PATCH",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(editDraft),
      })

      setTasks(payload.tasks)
      setSummary(payload.summary)
      setEditingTaskId(null)
      setEditDraft(null)
      setMessage("Task updated.")
    } catch (error) {
      setMessage((error as Error).message)
    } finally {
      setPendingAction(null)
    }
  }

  async function handleDelete(task: Task) {
    setPendingAction(`delete:${task.id}`)
    setMessage(`Deleting “${task.title}”...`)

    try {
      const payload = await fetchTasks("/api/tasks", {
        method: "DELETE",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ id: task.id }),
      })

      setTasks(payload.tasks)
      setSummary(payload.summary)
      if (editingTaskId === task.id) {
        setEditingTaskId(null)
        setEditDraft(null)
      }
      setMessage("Task deleted.")
    } catch (error) {
      setMessage((error as Error).message)
    } finally {
      setPendingAction(null)
    }
  }

  const createTaskForm = (
    <form className="space-y-4" onSubmit={handleCreate}>
      <div className="space-y-2">
        <label className="text-sm font-medium" htmlFor="task-title">
          Title
        </label>
        <Input
          id="task-title"
          value={title}
          onChange={(event) => setTitle(event.target.value)}
          placeholder="Ship Android Next.js shell"
        />
      </div>
      <div className="space-y-2">
        <label className="text-sm font-medium" htmlFor="task-details">
          Details
        </label>
        <Textarea
          id="task-details"
          rows={5}
          value={details}
          onChange={(event) => setDetails(event.target.value)}
          placeholder="Write the smallest next step that keeps momentum."
        />
      </div>
      <div className="space-y-2">
        <p className="text-sm font-medium">Priority</p>
        <div className="flex flex-wrap gap-2">
          {(["low", "medium", "high"] as TaskPriority[]).map((option) => (
            <Button
              key={option}
              type="button"
              variant={priority === option ? "default" : "outline"}
              onClick={() => setPriority(option)}
            >
              {priorityCopy[option]}
            </Button>
          ))}
        </div>
      </div>
      <div className="flex justify-end">
        <Button
          type="submit"
          size="lg"
          disabled={pendingAction === "create" || title.trim().length === 0}
        >
          {pendingAction === "create" ? <LoaderCircle className="animate-spin" /> : <Plus />}
          Create task
        </Button>
      </div>
    </form>
  )

  return (
    <div className="flex h-full min-h-0 flex-col gap-4">
      <Card className="shrink-0 border-border/70 bg-white/88 shadow-sm">
        <CardHeader>
          <CardTitle className="text-3xl tracking-[-0.06em]">FocusBoard</CardTitle>
        </CardHeader>
        <CardContent className="grid grid-cols-3 gap-3">
          <SummaryTile label="Open" value={String(summary.backlog)} tone="text-amber-700" />
          <SummaryTile label="Doing" value={String(summary.inProgress)} tone="text-sky-700" />
          <SummaryTile label="Done" value={String(summary.done)} tone="text-emerald-700" />
        </CardContent>
      </Card>

      <Card className="flex min-h-0 flex-1 flex-col overflow-hidden border-border/70 bg-white/88 shadow-sm">
        <CardHeader className="flex flex-row items-center justify-between gap-3">
          <CardTitle>Task board</CardTitle>
          <Dialog open={createDialogOpen} onOpenChange={setCreateDialogOpen}>
            <DialogTrigger asChild>
              <Button className="ml-auto">
                <Plus />
                Create task
              </Button>
            </DialogTrigger>
            <DialogContent className="sm:max-w-lg">
              <DialogHeader>
                <DialogTitle>New task</DialogTitle>
                <DialogDescription>
                  Add the next thing that matters, then move it forward with one tap.
                </DialogDescription>
              </DialogHeader>
              {createTaskForm}
            </DialogContent>
            </Dialog>
        </CardHeader>
        <CardContent className="flex min-h-0 flex-1 flex-col gap-4">
          <Tabs defaultValue="all" className="flex min-h-0 flex-1 flex-col gap-4">
            <TabsList className="shrink-0">
              <TabsTrigger value="all">All</TabsTrigger>
              <TabsTrigger value="backlog">Backlog</TabsTrigger>
              <TabsTrigger value="in_progress">In Progress</TabsTrigger>
              <TabsTrigger value="done">Done</TabsTrigger>
            </TabsList>

            {(["all", "backlog", "in_progress", "done"] as const).map((tab) => {
              const visibleTasks =
                tab === "all" ? tasks : grouped[tab]

              return (
                <TabsContent key={tab} value={tab} className="min-h-0 flex-1 overflow-hidden">
                  <div className="h-full space-y-3 overflow-y-auto pr-1">
                    {visibleTasks.length === 0 ? (
                      <div className="rounded-xl border border-dashed border-border/70 bg-muted/40 p-6 text-sm text-muted-foreground">
                        Nothing here yet.
                      </div>
                    ) : (
                      visibleTasks.map((task) => {
                        const ActionIcon = actionIcon(task.status)
                        const isEditing = editingTaskId === task.id && editDraft?.id === task.id
                        return (
                          <article
                            key={task.id}
                            className="rounded-2xl border border-border/70 bg-background/80 p-4"
                          >
                            <div className="flex flex-wrap items-start justify-between gap-3">
                              <div className="space-y-2">
                                <div className="flex flex-wrap items-center gap-2">
                                  <h3 className="text-base font-medium">{task.title}</h3>
                                  <Badge variant="outline">{statusCopy[task.status]}</Badge>
                                  <Badge variant="secondary">{priorityCopy[task.priority]}</Badge>
                                </div>
                                {task.details ? (
                                  <p className="max-w-2xl text-sm leading-6 text-muted-foreground">
                                    {task.details}
                                  </p>
                                ) : null}
                                <p className="text-xs text-muted-foreground">
                                  Updated {formatTimestamp(task.updatedAt)}
                                </p>
                              </div>
                              <div className="flex flex-wrap gap-2">
                                <Button
                                  variant={task.status === "done" ? "outline" : "default"}
                                  onClick={() => {
                                    void handleAdvance(task)
                                  }}
                                  disabled={pendingAction === task.id || pendingAction === `edit:${task.id}`}
                                >
                                  {pendingAction === task.id ? (
                                    <LoaderCircle className="animate-spin" />
                                  ) : (
                                    <ActionIcon />
                                  )}
                                  {actionLabel(task.status)}
                                </Button>
                                <Button
                                  variant="outline"
                                  onClick={() => beginEdit(task)}
                                  disabled={pendingAction === `delete:${task.id}`}
                                >
                                  <PencilLine />
                                  Edit
                                </Button>
                                <Button
                                  variant="outline"
                                  onClick={() => {
                                    void handleDelete(task)
                                  }}
                                  disabled={pendingAction === `delete:${task.id}` || pendingAction === `edit:${task.id}`}
                                >
                                  {pendingAction === `delete:${task.id}` ? (
                                    <LoaderCircle className="animate-spin" />
                                  ) : (
                                    <Trash2 />
                                  )}
                                  Delete
                                </Button>
                              </div>
                            </div>

                            {isEditing && editDraft ? (
                              <form className="mt-4 space-y-4 rounded-xl border border-border/70 bg-white/85 p-4" onSubmit={handleSaveEdit}>
                                <div className="space-y-2">
                                  <label className="text-sm font-medium" htmlFor={`edit-title-${task.id}`}>
                                    Title
                                  </label>
                                  <Input
                                    id={`edit-title-${task.id}`}
                                    value={editDraft.title}
                                    onChange={(event) =>
                                      setEditDraft({
                                        ...editDraft,
                                        title: event.target.value,
                                      })
                                    }
                                  />
                                </div>
                                <div className="space-y-2">
                                  <label className="text-sm font-medium" htmlFor={`edit-details-${task.id}`}>
                                    Details
                                  </label>
                                  <Textarea
                                    id={`edit-details-${task.id}`}
                                    rows={4}
                                    value={editDraft.details}
                                    onChange={(event) =>
                                      setEditDraft({
                                        ...editDraft,
                                        details: event.target.value,
                                      })
                                    }
                                  />
                                </div>
                                <div className="grid gap-4 md:grid-cols-2">
                                  <div className="space-y-2">
                                    <p className="text-sm font-medium">Priority</p>
                                    <div className="flex flex-wrap gap-2">
                                      {(["low", "medium", "high"] as TaskPriority[]).map((option) => (
                                        <Button
                                          key={option}
                                          type="button"
                                          variant={editDraft.priority === option ? "default" : "outline"}
                                          onClick={() =>
                                            setEditDraft({
                                              ...editDraft,
                                              priority: option,
                                            })
                                          }
                                        >
                                          {priorityCopy[option]}
                                        </Button>
                                      ))}
                                    </div>
                                  </div>
                                  <div className="space-y-2">
                                    <p className="text-sm font-medium">Status</p>
                                    <div className="flex flex-wrap gap-2">
                                      {(["backlog", "in_progress", "done"] as TaskStatus[]).map((option) => (
                                        <Button
                                          key={option}
                                          type="button"
                                          variant={editDraft.status === option ? "default" : "outline"}
                                          onClick={() =>
                                            setEditDraft({
                                              ...editDraft,
                                              status: option,
                                            })
                                          }
                                        >
                                          {statusCopy[option]}
                                        </Button>
                                      ))}
                                    </div>
                                  </div>
                                </div>
                                <div className="flex flex-wrap gap-2">
                                  <Button
                                    type="submit"
                                    disabled={pendingAction === `edit:${task.id}` || editDraft.title.trim().length === 0}
                                  >
                                    {pendingAction === `edit:${task.id}` ? (
                                      <LoaderCircle className="animate-spin" />
                                    ) : (
                                      <PencilLine />
                                    )}
                                    Save changes
                                  </Button>
                                  <Button type="button" variant="outline" onClick={cancelEdit}>
                                    <X />
                                    Cancel
                                  </Button>
                                </div>
                              </form>
                            ) : null}
                          </article>
                        )
                      })
                    )}
                  </div>
                </TabsContent>
              )
            })}
          </Tabs>
        </CardContent>
      </Card>
    </div>
  )
}
