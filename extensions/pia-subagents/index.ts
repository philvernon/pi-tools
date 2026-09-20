import { resolve } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const parameters = Type.Object({
  task: Type.String({ description: "Task for the detached Pi agent" }),
  cwd: Type.Optional(Type.String({ description: "Working directory, relative to the current project" })),
  provider: Type.Optional(Type.String({ description: "Pi provider name" })),
  model: Type.Optional(Type.String({ description: "Pi model ID or provider/model pattern" })),
  thinking: Type.Optional(Type.String({ description: "Pi thinking level" })),
  name: Type.Optional(Type.String({ description: "Pi session display name" })),
});

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "pia_subagent",
    label: "Pia Subagent",
    description: "Start a detached Pi subagent through pia and return its tmux session ID.",
    parameters,
    async execute(_toolCallId, params, signal, _onUpdate, ctx) {
      const cwd = resolve(ctx.cwd, params.cwd ?? ".");
      const args = ["--detach"];

      if (params.provider) args.push("--provider", params.provider);
      if (params.model) args.push("--model", params.model);
      if (params.thinking) args.push("--thinking", params.thinking);
      if (params.name) args.push("--name", params.name);
      args.push(params.task);

      const result = await pi.exec("pia", args, {
        cwd,
        signal,
        timeout: 10_000,
      });

      if (result.code !== 0) {
        throw new Error(result.stderr.trim() || `pia exited with code ${result.code}`);
      }

      const sessionId = result.stdout.trim().split(/\s+/).filter(Boolean).at(-1);
      if (!sessionId) throw new Error("pia did not return a tmux session ID");

      return {
        content: [
          {
            type: "text",
            text: `Started detached Pi subagent in ${cwd}\ntmux session: ${sessionId}`,
          },
        ],
        details: { sessionId, cwd, provider: params.provider, model: params.model },
      };
    },
  });
}
