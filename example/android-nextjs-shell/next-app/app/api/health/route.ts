import { NextResponse } from "next/server"

export const dynamic = "force-dynamic"

export async function GET() {
  return NextResponse.json({
    ok: true,
    route: "/api/health",
    node: process.version,
    arch: process.arch,
    platform: process.platform,
    now: new Date().toISOString(),
    uptime: process.uptime(),
    cwd: process.cwd(),
  })
}
