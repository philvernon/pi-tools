import { execFileSync } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function(pi: ExtensionAPI) {
  const rename = (_event: unknown, ctx: any) => {
    if (!process.env.TMUX) return;

    execFileSync("tmux", [
      "rename-session",
      `pi-${ctx.sessionManager.getSessionId()}`,
    ]);
  };

  pi.on("session_start", rename);
  pi.on("session_switch", rename);
}
