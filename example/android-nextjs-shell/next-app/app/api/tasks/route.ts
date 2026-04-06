import { NextResponse } from "next/server"

import {
  createTask,
  deleteTask,
  readTasks,
  summarizeTasks,
  updateTask,
  type TaskPriority,
  type TaskStatus,
} from "@/lib/store"

export const dynamic = "force-dynamic"

export async function GET() {
  const tasks = await readTasks()

  return NextResponse.json({
    ok: true,
    tasks,
    summary: summarizeTasks(tasks),
  })
}

export async function POST(request: Request) {
  const payload = (await request.json().catch(() => ({}))) as {
    title?: unknown
    details?: unknown
    priority?: unknown
  }

  const title = String(payload.title || "").trim()
  const details = String(payload.details || "").trim()
  const priority =
    payload.priority === "low" || payload.priority === "high" ? payload.priority : "medium"

  if (!title) {
    return NextResponse.json(
      {
        ok: false,
        message: "title is required",
      },
      { status: 400 }
    )
  }

  const tasks = await createTask({
    title,
    details,
    priority: priority as TaskPriority,
  })

  return NextResponse.json({
    ok: true,
    tasks,
    summary: summarizeTasks(tasks),
  })
}

export async function PATCH(request: Request) {
  const payload = (await request.json().catch(() => ({}))) as {
    id?: unknown
    title?: unknown
    details?: unknown
    priority?: unknown
    status?: unknown
  }

  const id = String(payload.id || "").trim()
  if (!id) {
    return NextResponse.json(
      {
        ok: false,
        message: "id is required",
      },
      { status: 400 }
    )
  }

  const status =
    payload.status === "backlog" || payload.status === "in_progress" || payload.status === "done"
      ? (payload.status as TaskStatus)
      : undefined
  const priority =
    payload.priority === "low" || payload.priority === "medium" || payload.priority === "high"
      ? (payload.priority as TaskPriority)
      : undefined
  const title = payload.title === undefined ? undefined : String(payload.title)
  const details = payload.details === undefined ? undefined : String(payload.details)

  const tasks = await updateTask({
    id,
    status,
    priority,
    title,
    details,
  })

  return NextResponse.json({
    ok: true,
    tasks,
    summary: summarizeTasks(tasks),
  })
}

export async function DELETE(request: Request) {
  const payload = (await request.json().catch(() => ({}))) as {
    id?: unknown
  }

  const id = String(payload.id || "").trim()
  if (!id) {
    return NextResponse.json(
      {
        ok: false,
        message: "id is required",
      },
      { status: 400 }
    )
  }

  try {
    const tasks = await deleteTask(id)
    return NextResponse.json({
      ok: true,
      tasks,
      summary: summarizeTasks(tasks),
    })
  } catch (error) {
    return NextResponse.json(
      {
        ok: false,
        message: error instanceof Error ? error.message : "delete failed",
      },
      { status: 404 }
    )
  }
}
