import { writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { SessionManager, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

interface PiaResult {
  state: "complete" | "failed";
  exitCode: number;
  output: string;
  error?: string;
  runDir?: string;
  outputLog?: string;
}

interface ChildSession {
  id: string;
  file: string;
  parentFile?: string;
}

const parameters = Type.Object({
  task: Type.String({ description: "Task for the Pi agent" }),
  cwd: Type.Optional(Type.String({ description: "Working directory, relative to the current project" })),
  provider: Type.Optional(Type.String({ description: "Pi provider name" })),
  model: Type.Optional(Type.String({ description: "Pi model ID or provider/model pattern" })),
  thinking: Type.Optional(Type.String({ description: "Pi thinking level" })),
  name: Type.Optional(Type.String({ description: "Pi session display name" })),
  wait: Type.Optional(
    Type.Boolean({
      description: "Wait for the Pi agent to finish and return its final response instead of returning a tmux handle",
      default: false,
    }),
  ),
});

function parsePiaResult(stdout: string): PiaResult {
  let value: unknown;
  try {
    value = JSON.parse(stdout.trim());
  } catch {
    throw new Error("pia returned invalid JSON");
  }

  if (!value || typeof value !== "object") throw new Error("pia returned an invalid result");

  const result = value as Partial<PiaResult>;
  if (result.state !== "complete" && result.state !== "failed") {
    throw new Error("pia returned a result without a valid state");
  }
  if (typeof result.exitCode !== "number" || typeof result.output !== "string") {
    throw new Error("pia returned an incomplete result");
  }
  return result as PiaResult;
}

function getWorkerError(stderr: string): string | undefined {
  const lines = stderr.split("\n").filter((line) => line && !line.startsWith("pia-run-dir="));
  return lines.length > 0 ? lines.join("\n") : undefined;
}

async function createChildSession(cwd: string, ctx: ExtensionContext): Promise<ChildSession> {
  const parentFile = ctx.sessionManager.getSessionFile();
  const sessionDir = ctx.sessionManager.getSessionDir() || undefined;
  const child = SessionManager.create(cwd, sessionDir, { parentSession: parentFile });
  const file = child.getSessionFile();
  const header = child.getHeader();
  if (!file || !header) throw new Error("Pi did not create a child session");

  await writeFile(file, `${JSON.stringify(header)}\n`, { encoding: "utf8", mode: 0o600, flag: "wx" });
  return { id: child.getSessionId(), file, parentFile };
}

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "pia_subagent",
    label: "Pia Subagent",
    description:
      "Start a Pi subagent through pia. By default return its tmux session ID immediately; with wait=true, return its final response.",
    parameters,
    async execute(_toolCallId, params, signal, _onUpdate, ctx) {
      const cwd = resolve(ctx.cwd, params.cwd ?? ".");
      const wait = params.wait === true;
      const childSession = await createChildSession(cwd, ctx);
      const args = wait ? ["--detach", "--wait", "--mode", "json", "--print"] : ["--detach"];
      args.push("--session", childSession.file);

      if (params.provider) args.push("--provider", params.provider);
      if (params.model) args.push("--model", params.model);
      if (params.thinking) args.push("--thinking", params.thinking);
      if (params.name) args.push("--name", params.name);
      args.push("--", params.task);

      const result = await pi.exec("pia", args, {
        cwd,
        signal,
        timeout: wait ? undefined : 10_000,
      });

      if (result.killed) {
        throw new Error(signal?.aborted ? "pia subagent was aborted" : "pia subagent was terminated");
      }

      if (wait) {
        let piaResult: PiaResult;
        try {
          piaResult = parsePiaResult(result.stdout);
        } catch (error) {
          throw new Error(
            getWorkerError(result.stderr) || (error instanceof Error ? error.message : String(error)),
          );
        }

        if (result.code !== 0 || piaResult.state !== "complete") {
          throw new Error(piaResult.error || getWorkerError(result.stderr) || `pia exited with code ${result.code}`);
        }

        return {
          content: [{ type: "text", text: piaResult.output || "(no output)" }],
          details: {
            wait: true,
            cwd,
            output: piaResult.output,
            runDir: piaResult.runDir,
            outputLog: piaResult.outputLog,
            sessionId: childSession.id,
            sessionFile: childSession.file,
            parentSession: childSession.parentFile,
            provider: params.provider,
            model: params.model,
            thinking: params.thinking,
          },
        };
      }

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
        details: {
          wait: false,
          sessionId,
          piSessionId: childSession.id,
          sessionFile: childSession.file,
          parentSession: childSession.parentFile,
          cwd,
          provider: params.provider,
          model: params.model,
          thinking: params.thinking,
        },
      };
    },
  });
}
