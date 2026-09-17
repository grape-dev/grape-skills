#!/usr/bin/env node
/**
 * fetch_checks.js — 动态拉取最新通用规范检查点 JSON（skill-linter 规则集）
 *
 * 来源: developer-skill/skills-group-contribution · tools/skills_checker/common_skillslinter.json
 * 策略：先尝试 raw URL，失败(403)则回退到 gitcode API v5（base64 解码）
 *
 * 用法:
 *   node fetch_checks.js                       # 拉取默认地址，输出 JSON 到 stdout
 *   node fetch_checks.js <url>                 # 拉取指定地址（自定义 URL 不走 API 回退）
 *   node fetch_checks.js -o /tmp/checks.json   # 拉取并保存到文件（断点续跑/复查用）
 *   node fetch_checks.js --help                # 显示用法
 *
 * 退出码: 0=成功 1=失败
 */
const https = require("https");
const http = require("http");
const fs = require("fs");

const RAW_URL =
  "https://raw.gitcode.com/developer-skill/skills-group-contribution/raw/members-contribution/tools/skills_checker/common_skillslinter.json";
const API_URL =
  "https://gitcode.com/api/v5/repos/developer-skill/skills-group-contribution/contents/tools/skills_checker/common_skillslinter.json?ref=members-contribution";

function fetch(url) {
  return new Promise((resolve, reject) => {
    const mod = url.startsWith("https") ? https : http;
    const req = mod.get(url, { timeout: 20000 }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        return fetch(res.headers.location).then(resolve, reject);
      }
      if (res.statusCode !== 200) {
        return reject(new Error(`HTTP ${res.statusCode}`));
      }
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => resolve(Buffer.concat(chunks).toString("utf-8")));
    });
    req.on("error", reject);
    req.on("timeout", () => req.destroy(new Error("timeout")));
  });
}

async function tryFetchJSON(rawUrl, apiUrl) {
  // 1) 尝试 raw URL
  try {
    process.stderr.write(`[common-skill-creator] 尝试 raw URL: ${rawUrl}\n`);
    const raw = await fetch(rawUrl);
    JSON.parse(raw); // validate
    process.stderr.write(`[common-skill-creator] raw URL 成功\n`);
    return raw;
  } catch (e1) {
    process.stderr.write(
      `[common-skill-creator] raw URL 失败(${e1.message})，回退到 API v5\n`
    );
  }
  // 2) 回退到 API v5 (base64)
  const apiRaw = await fetch(apiUrl);
  const apiJson = JSON.parse(apiRaw);
  if (apiJson.encoding === "base64" && apiJson.content) {
    const decoded = Buffer.from(apiJson.content, "base64").toString("utf-8");
    JSON.parse(decoded); // validate
    process.stderr.write(`[common-skill-creator] API v5 成功\n`);
    return decoded;
  }
  throw new Error("API v5 返回缺少 base64 content");
}

async function main() {
  const args = process.argv.slice(2);
  if (args.includes("--help") || args.includes("-h")) {
    process.stdout.write(`用法:
  node fetch_checks.js                       # 拉取默认检查点，输出 JSON 到 stdout
  node fetch_checks.js <url>                 # 拉取指定地址（不走 API 回退）
  node fetch_checks.js -o /tmp/checks.json   # 拉取并保存到文件
  node fetch_checks.js --help                # 显示本帮助

退出码: 0=成功 1=失败
`);
    process.exit(0);
  }

  let rawUrl = RAW_URL;
  let apiUrl = API_URL;
  let outFile = null;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "-o" && args[i + 1]) {
      outFile = args[++i];
    } else if (!args[i].startsWith("-")) {
      rawUrl = args[i];
      apiUrl = null; // 自定义 URL 时不走 API fallback
    }
  }

  try {
    const raw = apiUrl
      ? await tryFetchJSON(rawUrl, apiUrl)
      : await fetch(rawUrl);

    const json = JSON.parse(raw);
    if (!json.groups || !Array.isArray(json.groups)) {
      throw new Error("JSON 缺少 groups 字段");
    }
    const total = json.groups.reduce(
      (s, g) => s + (g.items ? g.items.length : 0),
      0
    );
    process.stderr.write(
      `[common-skill-creator] 拉取成功: ${json.groups.length} 组, ${total} 项检查\n`
    );

    const output = JSON.stringify(json, null, 2);
    if (outFile) {
      fs.writeFileSync(outFile, output, "utf-8");
      process.stderr.write(`[common-skill-creator] 已保存到: ${outFile}\n`);
    } else {
      process.stdout.write(output);
    }
    process.exit(0);
  } catch (err) {
    process.stderr.write(`[common-skill-creator] 拉取失败: ${err.message}\n`);
    process.exit(1);
  }
}

main();