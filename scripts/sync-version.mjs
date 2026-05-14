#!/usr/bin/env node
/**
 * sync-version.mjs — Regenerate system-prompts/ for a given Claude Code
 *                    version, using the same gray-matter@4.0.3 library
 *                    that tweakcc itself uses.
 *
 * USAGE
 * -----
 *     node scripts/sync-version.mjs 2.1.140                    # most common
 *     node scripts/sync-version.mjs                            # prompts interactively
 *     node scripts/sync-version.mjs 2.1.140 --dry-run          # preview without writing
 *     node scripts/sync-version.mjs 2.1.140 --download         # always fetch (skip local clone)
 *     node scripts/sync-version.mjs 2.1.140 --tweakcc-dir P    # override local clone path
 *     node scripts/sync-version.mjs 2.1.140 --target P         # override output dir
 *     node scripts/sync-version.mjs 2.1.140 --no-clear         # don't wipe existing .md
 *
 * WHAT IT DOES
 * ------------
 * Reads data/prompts/prompts-{version}.json from a local tweakcc clone
 * (default: G:/Cathedral/repos_external/tweakcc) or downloads it from
 * tweakcc's GitHub repo. Reconstructs each prompt's body by interleaving
 * the JSON's `pieces` array with human-readable variable names from
 * `identifierMap`, then writes one .md file per prompt to system-prompts/.
 *
 * The .md format and gray-matter call use the same arguments as tweakcc's
 * generateMarkdownFromPrompt() in src/systemPromptSync.ts, so output is
 * byte-identical to what `npx tweakcc-fixed --apply` would extract from a
 * freshly installed Claude Code binary at the same version.
 *
 * After running, run `python scripts/apply-unnerfs.py` to re-apply un-nerfs
 * on top of the fresh stock text.
 *
 * EXIT CODES
 * ----------
 *     0  — wrote all files (or in --dry-run, finished without error)
 *     1  — network, JSON, or filesystem error preventing extraction
 *     2  — invalid invocation
 */

import * as fs from "node:fs/promises";
import * as path from "node:path";
import * as readline from "node:readline/promises";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

import matter from "gray-matter";

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const DEFAULT_TWEAKCC_DIR = "G:/Cathedral/repos_external/tweakcc";

const DOWNLOAD_URL =
  "https://raw.githubusercontent.com/Piebald-AI/tweakcc/" +
  "refs/heads/main/data/prompts/prompts-{version}.json";

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(SCRIPT_DIR, "..");
const DEFAULT_TARGET = path.join(REPO_ROOT, "system-prompts");

// ---------------------------------------------------------------------------
// Prompt reconstruction (mirrors tweakcc's systemPromptSync.ts verbatim)
// ---------------------------------------------------------------------------

/**
 * Re-stitch a prompt body from its tokenized pieces. After each piece (except
 * possibly the last), `identifiers[i]` indexes into `identifierMap` to give
 * the human-readable variable name that goes between the pieces. The `${`
 * and `}` wrapping a placeholder are already split into the surrounding
 * pieces by tweakcc's extractor.
 *
 * Verbatim copy of tweakcc's reconstructContentFromPieces.
 */
function reconstructContentFromPieces(pieces, identifiers, identifierMap) {
  let result = "";
  for (let i = 0; i < pieces.length; i++) {
    result += pieces[i];
    if (i < identifiers.length) {
      const labelIndex = identifiers[i];
      const humanName =
        identifierMap[String(labelIndex)] || `UNKNOWN_${labelIndex}`;
      result += humanName;
    }
  }
  return result;
}

/**
 * Build the .md file content for a single prompt entry.
 *
 * Mirrors tweakcc's generateMarkdownFromPrompt: same frontmatter keys, same
 * variables-deduplication via Set, same matter.stringify call with HTML
 * comment delimiters.
 */
function generateMarkdownFromPrompt(prompt) {
  const content = reconstructContentFromPieces(
    prompt.pieces,
    prompt.identifiers,
    prompt.identifierMap,
  );

  // Unique variables in first-seen order — same as
  // [...new Set(Object.values(prompt.identifierMap))] in tweakcc.
  const variables =
    Object.keys(prompt.identifierMap).length > 0
      ? [...new Set(Object.values(prompt.identifierMap))]
      : undefined;

  const frontmatterData = {
    name: prompt.name,
    description: prompt.description,
    ccVersion: prompt.version,
  };
  if (variables && variables.length > 0) {
    frontmatterData.variables = variables;
  }

  return matter.stringify(content, frontmatterData, {
    delimiters: ["<!--", "-->"],
  });
}

// ---------------------------------------------------------------------------
// Source loading
// ---------------------------------------------------------------------------

async function loadStringsFile(version, tweakccDir, { forceDownload }) {
  if (!forceDownload) {
    const local = path.join(
      tweakccDir,
      "data",
      "prompts",
      `prompts-${version}.json`,
    );
    try {
      const text = await fs.readFile(local, "utf-8");
      console.error(`reading from local clone: ${local}`);
      return JSON.parse(text);
    } catch (err) {
      if (err.code !== "ENOENT") throw err;
      console.error(
        `local file not found at ${local}; falling back to download`,
      );
    }
  }

  const url = DOWNLOAD_URL.replace("{version}", version);
  console.error(`downloading from ${url}`);

  const resp = await fetch(url, {
    headers: { "User-Agent": "sync-version.mjs" },
  });
  if (!resp.ok) {
    if (resp.status === 404) {
      throw new SystemExit(
        `error: prompts-${version}.json not found on tweakcc GitHub.\n` +
          `  Either the version string is wrong, or tweakcc hasn't published ` +
          `prompts for that version yet (sometimes lags a few hours behind ` +
          `a Claude Code release).`,
      );
    }
    throw new SystemExit(
      `error: HTTP ${resp.status} ${resp.statusText} fetching ${url}`,
    );
  }
  return await resp.json();
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

class SystemExit extends Error {
  constructor(message, code = 1) {
    super(message);
    this.code = code;
  }
}

function printHelp() {
  console.log(`usage: node sync-version.mjs [options] [version]

Regenerate system-prompts/ from tweakcc's prompts JSON for a given
Claude Code version.

positional:
  version              Claude Code version, e.g. 2.1.140. If omitted, prompts
                       interactively.

options:
  --tweakcc-dir PATH   Local tweakcc clone path
                       (default: ${DEFAULT_TWEAKCC_DIR})
  --target PATH        Output directory
                       (default: ${DEFAULT_TARGET})
  --download           Skip the local clone check; always fetch from GitHub.
  --dry-run            Don't write anything; report what would change.
  --no-clear           Don't delete existing files in --target before writing.
  -h, --help           Show this help message and exit.

After running, run scripts/apply-unnerfs.py to re-apply un-nerfs.`);
}

function validateVersion(v) {
  if (!/^\d+\.\d+\.\d+$/.test(v)) {
    throw new SystemExit(
      `error: '${v}' doesn't look like a Claude Code version (expected X.Y.Z)`,
      2,
    );
  }
  return v;
}

async function promptForVersion() {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stderr,
  });
  try {
    const v = (await rl.question("Claude Code version (e.g. 2.1.140): ")).trim();
    if (!v) throw new SystemExit("no version provided; aborting", 2);
    return v;
  } finally {
    rl.close();
  }
}

async function main(argv) {
  let parsed;
  try {
    parsed = parseArgs({
      args: argv,
      allowPositionals: true,
      options: {
        "tweakcc-dir": { type: "string", default: DEFAULT_TWEAKCC_DIR },
        target: { type: "string", default: DEFAULT_TARGET },
        download: { type: "boolean", default: false },
        "dry-run": { type: "boolean", default: false },
        "no-clear": { type: "boolean", default: false },
        help: { type: "boolean", short: "h", default: false },
      },
    });
  } catch (err) {
    console.error(`error: ${err.message}`);
    printHelp();
    return 2;
  }

  if (parsed.values.help) {
    printHelp();
    return 0;
  }

  const versionArg = parsed.positionals[0] ?? (await promptForVersion());
  const version = validateVersion(versionArg);
  const target = path.resolve(parsed.values.target);
  const tweakccDir = path.resolve(parsed.values["tweakcc-dir"]);

  const data = await loadStringsFile(version, tweakccDir, {
    forceDownload: parsed.values.download,
  });

  if (data.version !== version) {
    console.error(
      `warning: JSON file's top-level version is '${data.version}' but ` +
        `we asked for '${version}'. Continuing anyway.`,
    );
  }

  const prompts = data.prompts ?? [];
  if (prompts.length === 0) {
    throw new SystemExit("error: JSON file has no 'prompts' array");
  }

  if (parsed.values["dry-run"]) {
    console.error(`[dry-run] would clear and rewrite ${target}`);
    let existing = [];
    try {
      const entries = await fs.readdir(target);
      existing = entries.filter((n) => n.endsWith(".md")).sort();
    } catch (err) {
      if (err.code !== "ENOENT") throw err;
    }
    const incoming = prompts.map((p) => `${p.id}.md`).sort();
    const existingSet = new Set(existing);
    const incomingSet = new Set(incoming);
    const added = incoming.filter((n) => !existingSet.has(n));
    const removed = existing.filter((n) => !incomingSet.has(n));
    const kept = existing.filter((n) => incomingSet.has(n));
    console.error(`  new files: ${added.length}`);
    for (const f of added.slice(0, 50)) console.error(`    + ${f}`);
    console.error(`  removed files: ${removed.length}`);
    for (const f of removed.slice(0, 50)) console.error(`    - ${f}`);
    console.error(`  updated/rewritten files: ${kept.length}`);
    console.error(
      `[dry-run] would write ${prompts.length} files total for v${version}`,
    );
    return 0;
  }

  // Clear-and-rewrite. Wipe stale .md files only; leave the directory itself
  // and any non-.md siblings alone.
  if (!parsed.values["no-clear"]) {
    try {
      const entries = await fs.readdir(target);
      for (const name of entries) {
        if (name.endsWith(".md")) {
          await fs.unlink(path.join(target, name));
        }
      }
    } catch (err) {
      if (err.code !== "ENOENT") throw err;
      await fs.mkdir(target, { recursive: true });
    }
  } else {
    await fs.mkdir(target, { recursive: true });
  }

  let written = 0;
  for (const prompt of prompts) {
    const md = generateMarkdownFromPrompt(prompt);
    const out = path.join(target, `${prompt.id}.md`);
    // Write as bytes (no encoding transform) to keep LF line endings on every
    // platform — matches tweakcc's output on Windows.
    await fs.writeFile(out, md, { encoding: "utf-8" });
    written++;
  }

  console.error(
    `wrote ${written} files to ${target} (Claude Code v${version})`,
  );
  console.error(`next: python scripts/apply-unnerfs.py`);
  return 0;
}

// Use process.exitCode rather than process.exit() so the event loop drains
// naturally — pending sockets (e.g. the failed fetch) get to close cleanly
// instead of triggering a libuv assertion on Windows.
try {
  process.exitCode = await main(process.argv.slice(2));
} catch (err) {
  if (err instanceof SystemExit) {
    console.error(err.message);
    process.exitCode = err.code;
  } else {
    console.error("unexpected error:");
    console.error(err);
    process.exitCode = 1;
  }
}
