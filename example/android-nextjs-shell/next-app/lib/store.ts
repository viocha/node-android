import crypto from "node:crypto"
import { mkdir, readFile, writeFile } from "node:fs/promises"
import path from "node:path"

export type TaskStatus = "backlog" | "in_progress" | "done"
export type TaskPriority = "low" | "medium" | "high"

export type Task = {
  id: string
  title: string
  details: string
  status: TaskStatus
  priority: TaskPriority
  createdAt: string
  updatedAt: string
}

export type TaskSummary = {
  total: number
  backlog: number
  inProgress: number
  done: number
}

const dataDir = path.join(process.cwd(), "runtime-data")
const tasksFile = path.join(dataDir, "tasks.json")

async function ensureDataDir() {
  await mkdir(dataDir, { recursive: true })
}

function isEnoent(error: unknown) {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    (error as { code?: string }).code === "ENOENT"
  )
}

export async function readTasks(): Promise<Task[]> {
  await ensureDataDir()

  try {
    const source = await readFile(tasksFile, "utf8")
    const parsed = JSON.parse(source) as unknown
    return Array.isArray(parsed) ? (parsed as Task[]) : []
  } catch (error) {
    if (isEnoent(error)) {
      return []
    }
    throw error
  }
}

async function writeTasks(tasks: Task[]) {
  await ensureDataDir()
  await writeFile(tasksFile, JSON.stringify(tasks, null, 2), "utf8")
}

export async function createTask(input: {
  title: string
  details: string
  priority: TaskPriority
}): Promise<Task[]> {
  const tasks = await readTasks()
  const now = new Date().toISOString()
  const nextTask: Task = {
    id: crypto.randomUUID(),
    title: input.title.trim(),
    details: input.details.trim(),
    priority: input.priority,
    status: "backlog",
    createdAt: now,
    updatedAt: now,
  }

  const updated = [nextTask, ...tasks].slice(0, 64)
  await writeTasks(updated)
  return updated
}

export async function updateTask(input: {
  id: string
  title?: string
  details?: string
  priority?: TaskPriority
  status?: TaskStatus
}): Promise<Task[]> {
  const tasks = await readTasks()
  let found = false
  const updated = tasks.map((task) => {
    if (task.id !== input.id) return task
    found = true

    return {
      ...task,
      title: input.title !== undefined ? input.title.trim() : task.title,
      details: input.details !== undefined ? input.details.trim() : task.details,
      priority: input.priority ?? task.priority,
      status: input.status ?? task.status,
      updatedAt: new Date().toISOString(),
    }
  })

  if (!found) {
    throw new Error("task not found")
  }

  await writeTasks(updated)
  return updated
}

export async function deleteTask(id: string): Promise<Task[]> {
  const tasks = await readTasks()
  const updated = tasks.filter((task) => task.id !== id)

  if (updated.length === tasks.length) {
    throw new Error("task not found")
  }

  await writeTasks(updated)
  return updated
}

export function summarizeTasks(tasks: Task[]): TaskSummary {
  return {
    total: tasks.length,
    backlog: tasks.filter((task) => task.status === "backlog").length,
    inProgress: tasks.filter((task) => task.status === "in_progress").length,
    done: tasks.filter((task) => task.status === "done").length,
  }
}
