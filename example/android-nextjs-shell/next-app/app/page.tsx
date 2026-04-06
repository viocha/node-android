import TasksClient from "./tasks-client"
import { readTasks, summarizeTasks } from "@/lib/store"

export const dynamic = "force-dynamic"

export default async function Home() {
  const tasks = await readTasks()
  const summary = summarizeTasks(tasks)

  return (
    <main className="min-h-screen bg-[radial-gradient(circle_at_top_left,rgba(255,181,120,0.18),transparent_24%),radial-gradient(circle_at_top_right,rgba(255,228,204,0.66),transparent_30%),linear-gradient(180deg,#fbf7f1_0%,#f4ede3_55%,#efe5da_100%)] px-4 pb-10 pt-5 sm:px-6 lg:px-8 lg:pt-8">
      <div className="mx-auto flex w-full max-w-6xl flex-col gap-4">
        <TasksClient initialTasks={tasks} initialSummary={summary} />
      </div>
    </main>
  )
}
