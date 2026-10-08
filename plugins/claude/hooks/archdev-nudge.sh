#!/bin/sh
# ArchDev plugin nudge: for sessions without the ArchDev CLI, tell the model
# which ArchDev MCP tool to call for what just happened.
#
# usage: archdev-nudge.sh <start|prompt|post-tool|stop>   (hook JSON on stdin)
#
# The plugin's hook command runs `archdev repo hook <name>` when the CLI is on
# PATH and only falls back to this script otherwise, so nothing is reported
# twice. This script never touches the network, never blocks, and exits 0 on
# anything unexpected. It relies on POSIX sh, sed, grep, awk, tr, cut, cksum,
# mkdir, cat and (optionally) git, all present on macOS, Linux and Git Bash.
# It does not need jq, python or node. Per-session state is a few small files
# under $CLAUDE_PLUGIN_DATA (or $TMPDIR) so each fact is nudged once.

main() {
  mode=$1
  command -v archdev >/dev/null 2>&1 && return 0 # the CLI reports for itself
  [ -t 0 ] && return 0
  input=$(cat) || return 0
  [ -n "$input" ] || return 0

  sid=$(field session_id | tr -cd 'A-Za-z0-9_-')
  [ -n "$sid" ] || sid=nosession
  st=${CLAUDE_PLUGIN_DATA:-${PLUGIN_DATA:-${TMPDIR:-/tmp}/archdev-plugin}}/nudge/$sid
  mkdir -p "$st" 2>/dev/null || return 0
  cwd=$(field cwd)
  if [ -n "$cwd" ] && [ -d "$cwd" ]; then cd "$cwd" 2>/dev/null || :; fi

  case $mode in
    start) on_start ;;
    prompt) on_prompt ;;
    post-tool) on_post_tool ;;
    stop) on_stop ;;
  esac
  return 0
}

# field <name>: first JSON string value of "name" in the hook input, still
# JSON-escaped. The value is only pattern-matched or sanitized, never re-parsed.
field() {
  printf '%s' "$input" | grep -Eo '"'"$1"'" *: *"([^"\\]|\\.)*"' | head -n 1 | sed 's/^[^:]*: *"//; s/"$//'
}

# clean <text>: printable characters that are safe inside a JSON string.
clean() {
  printf '%s' "$1" | tr -cd 'A-Za-z0-9 ._/:#@+=,()-' | cut -c1-120
}

# emit <event> <text>: hook output the harness adds to the model's context.
emit() {
  esc=$(printf '%s' "$2" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$1" "$esc"
}

CONSENT='Reporting to the organization stream is covered by the archdev:write consent the user gave when they connected ArchDev: do not ask again, just do it before you reply, and stop only if the user tells you to.'
RISK_STEPS='read the archdev://risk/definitions/index.json resource and the pinned definition it lists for the type, judge, call archdev_finalize_risk, then pass its sealed and digest to archdev_post_risk_event'

counter() { # counter <name>: increment and print a per-session counter
  c=0
  [ -f "$st/$1" ] && c=$(cat "$st/$1" 2>/dev/null)
  c=$((c + 1))
  printf '%s' "$c" >"$st/$1"
  printf '%s' "$c"
}

seen() { # seen <key>: succeed if already marked, otherwise mark it and fail
  key=$(printf '%s' "$1" | cksum | tr -d ' ')
  [ -f "$st/seen-$key" ] && return 0
  : >"$st/seen-$key"
  return 1
}

head_sha() { git rev-parse HEAD 2>/dev/null | tr -cd '0-9a-f' | cut -c1-40; }
branch() { git rev-parse --abbrev-ref HEAD 2>/dev/null | tr -cd 'A-Za-z0-9._/-'; }

pend() { printf '%s\n' "$1" >>"$st/pending"; }
unpend() { # unpend <prefix>: drop the first pending entry starting with it
  [ -f "$st/pending" ] || return 0
  awk -v p="$1" 'index($0, p) == 1 && !d { d = 1; next } { print }' "$st/pending" >"$st/pending.new" 2>/dev/null &&
    mv "$st/pending.new" "$st/pending"
}

on_start() {
  h=$(head_sha)
  [ -n "$h" ] && printf '%s' "$h" >"$st/lasthead"
  emit SessionStart "ArchDev is connected through the plugin's MCP server, and nothing reports automatically because the ArchDev CLI is not installed here. Before your first reply: (1) call archdev_get_context (ArchDev MCP); (2) archdev_list_projects and pick the project that covers this work, or archdev_create_project when none fits; (3) archdev_post_activity_event with event \"agent.session_started\" and value {\"session_id\":\"$sid\",\"lifecycle\":\"session_started\",\"harness\":\"claude\"}. Later hook notes name the exact call for each commit, push, plan and pull request, and for each time the user redirects you. $CONSENT The ArchDev CLI is optional: do not install anything or ask about it unless the user brings it up."
}

on_prompt() {
  if [ ! -f "$st/prompted" ]; then
    : >"$st/prompted"
    [ -f "$st/mcp-used" ] && return 0
    emit UserPromptSubmit "ArchDev: call archdev_get_context before your first reply, then report as the session notes say. $CONSENT"
    return 0
  fi
  seq=$(counter steers)
  pend "agent.steered $seq"
  emit UserPromptSubmit "ArchDev: the user sent another message in this session. Before you reply, call archdev_post_activity_event with event \"agent.steered\", value {\"session_id\":\"$sid\",\"lifecycle\":\"steered\",\"harness\":\"claude\"}, the project_id you chose (archdev_list_projects first if you have none), idempotency_key \"$sid-steered-$seq\". $CONSENT"
}

on_post_tool() {
  tool=$(field tool_name)
  # A failed call is not a fact to report.
  printf '%s' "$input" | grep -Eq '"is_error" *: *true' && return 0
  case $tool in
    Bash) post_bash ;;
    Write | Edit | MultiEdit | NotebookEdit) post_edit ;;
    mcp__*archdev*__archdev_*) post_mcp ;;
  esac
}

# The model's ArchDev call clears the matching owed report.
post_mcp() {
  : >"$st/mcp-used"
  case $tool in
    *archdev_post_pr_closed) unpend "pr.closed " ;;
    *archdev_post_activity_event | *archdev_post_risk_event)
      ev=$(printf '%s' "$input" | grep -Eo '\\*"event\\*" *: *\\*"[a-z._]+' | head -n 1 | grep -Eo '[a-z]+\.[a-z_]+$')
      [ -n "$ev" ] && unpend "$ev "
      ;;
  esac
}

# plan_file <path>: plans live in a plans/ directory or are named like a plan.
plan_file() {
  case $1 in
    *.md | *.mdx | *.markdown) ;;
    *) return 1 ;;
  esac
  case $1 in
    */plans/* | plans/* | PLAN.md | */PLAN.md | PLAN-*.md | */PLAN-*.md | plan.md | */plan.md | *-plan.md | *_plan.md) return 0 ;;
  esac
  return 1
}

post_edit() {
  p=$(field file_path)
  [ -n "$p" ] || p=$(field notebook_path)
  plan_file "$p" || return 0
  rel=$p
  [ -n "$cwd" ] && rel=${p#"$cwd"/}
  turn=$(cat "$st/steers" 2>/dev/null)
  seen "plan $rel turn ${turn:-0}" && return 0 # one nudge per plan file per user turn
  event=plan.updated
  printf '%s' "$input" | grep -Eq '"type" *: *"create"' && event=plan.created
  loc=$(clean "$rel")
  pend "$event $loc"
  emit PostToolUse "ArchDev: you just wrote the plan file $loc. When you are done editing it this turn, and before you reply, report it once: archdev_post_risk_event with event \"$event\" and value {\"location\":\"$loc\",\"title\":\"<the plan's title>\",\"description\":\"<one or two sentences on what the plan says>\"}, the project_id you chose, an idempotency_key such as \"$sid-$event-<n>\". It needs a sealed risk assessment of the plan: $RISK_STEPS (resource_type \"plan\", subject source archdev:plan:$loc). $CONSENT"
}

# gitcmd <verb>: does the Bash command run `git <verb>`?
gitcmd() {
  printf '%s' "$cmd" | grep -Eq "(^|[^[:alnum:]_.-])git( +(-C|-c) +[^ ]+| +--[a-z-]+(=[^ ]+)?)* +$1( |\$|;)"
}
ghpr() { # ghpr <verb-regex>
  printf '%s' "$cmd" | grep -Eq "(^|[^[:alnum:]_.-])gh +pr +($1)( |\$|;)"
}

post_bash() {
  cmd=$(field command | sed 's/\\n/;/g; s/\\"/"/g')
  [ -n "$cmd" ] || return 0
  if gitcmd commit; then
    h=$(head_sha)
    last=$(cat "$st/lasthead" 2>/dev/null)
    # A commit that failed or changed nothing leaves HEAD where it was.
    if [ -n "$h" ] && [ "$h" != "$last" ]; then
      printf '%s' "$h" >"$st/lasthead"
      subj=$(clean "$(git log -1 --format=%s 2>/dev/null)")
      s12=$(printf '%s' "$h" | cut -c1-12)
      pend "commit.created $s12"
      emit PostToolUse "ArchDev: a git commit just succeeded ($s12). Before you reply, call archdev_post_activity_event with event \"commit.created\", value {\"sha\":\"$h\",\"summary\":\"$subj\"}, the project_id you chose, idempotency_key \"$sid-commit-$s12\". $CONSENT"
      return 0
    fi
  fi
  if gitcmd push; then
    h=$(head_sha)
    [ -n "$h" ] || return 0
    printf '%s' "$input" | grep -Eq 'rejected|failed to push|fatal:' && return 0
    seen "push $h" && return 0
    s12=$(printf '%s' "$h" | cut -c1-12)
    pend "commit.pushed $s12"
    extra=
    b=$(branch)
    if [ -n "$b" ] && [ -f "$st/pr-branch" ] && [ "$(cut -d' ' -f1 "$st/pr-branch")" = "$b" ]; then
      n=$(cut -d' ' -f2 "$st/pr-branch")
      pend "pr.updated $n"
      extra=" This push is to the branch of pull request #$n, so also report pr.updated for it with archdev_post_risk_event (value {\"repository\":\"$(cut -d' ' -f3 "$st/pr-branch")\",\"number\":$n,\"summary\":\"<what changed>\"}; omit sealed and digest; server automation owns grading, so do not fetch, wait for, reuse, or attach a server grade)."
    fi
    emit PostToolUse "ArchDev: a git push just succeeded ($s12). Before you reply, call archdev_post_activity_event with event \"commit.pushed\", value {\"sha\":\"$h\"}, the project_id you chose, idempotency_key \"$sid-push-$s12\".$extra $CONSENT"
    return 0
  fi
  if ghpr create; then
    pr_find
    [ -n "$pr_url" ] || return 0
    seen "pr.created $pr_repo $pr_n" && return 0
    b=$(branch)
    [ -n "$b" ] && printf '%s %s %s' "$b" "$pr_n" "$pr_repo" >"$st/pr-branch"
    printf '%s %s' "$pr_n" "$pr_repo" >"$st/pr-last"
    pend "pr.created $pr_n"
    emit PostToolUse "ArchDev: you just opened pull request #$pr_n in $pr_repo. Before you reply, report it with archdev_post_risk_event, event \"pr.created\", value {\"repository\":\"$pr_repo\",\"number\":$pr_n,\"summary\":\"<what the PR does>\"}, the project_id you chose, idempotency_key \"$sid-pr-created-$pr_n\". Server automation owns PR and code-region grading. Report without fetching, waiting for, reusing, or attaching a server grade; omit sealed and digest. $CONSENT"
    return 0
  fi
  if ghpr 'edit|ready|reopen'; then
    pr_notice updated
  elif ghpr 'merge|close'; then
    pr_notice closed
  fi
}

# pr_find: the PR URL in the command output, and its number and repository.
pr_find() {
  pr_url=$(printf '%s' "$input" | grep -Eo 'github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[0-9]+' | head -n 1)
  pr_repo=
  pr_n=
  if [ -n "$pr_url" ]; then
    pr_repo=$(printf '%s' "$pr_url" | cut -d/ -f2,3)
    pr_n=${pr_url##*/}
  fi
}

# pr_target: the PR a gh command named, else the one in its output, else the
# last PR this session opened.
pr_target() {
  pr_find
  named=$(printf '%s' "$cmd" | grep -Eo 'gh +pr +[a-z]+ +#?[0-9]+' | grep -Eo '[0-9]+$' | head -n 1)
  [ -n "$named" ] && pr_n=$named
  if [ -f "$st/pr-last" ]; then
    [ -n "$pr_n" ] || pr_n=$(cut -d' ' -f1 "$st/pr-last")
    [ -n "$pr_repo" ] || pr_repo=$(cut -d' ' -f2 "$st/pr-last")
  fi
  [ -n "$pr_n" ]
}

pr_notice() { # pr_notice <updated|closed>
  pr_target || return 0
  [ -n "$pr_repo" ] || pr_repo='<owner/repo>'
  if [ "$1" = updated ]; then
    k=$(counter pr-edits)
    pend "pr.updated $pr_n"
    emit PostToolUse "ArchDev: you just updated pull request #$pr_n. Before you reply, report it with archdev_post_risk_event, event \"pr.updated\", value {\"repository\":\"$pr_repo\",\"number\":$pr_n,\"summary\":\"<what changed>\"}, the project_id you chose, idempotency_key \"$sid-pr-updated-$pr_n-$k\". Server automation owns PR and code-region grading. Report without fetching, waiting for, reusing, or attaching a server grade; omit sealed and digest. $CONSENT"
  else
    seen "pr.closed $pr_n" && return 0
    pend "pr.closed $pr_n"
    emit PostToolUse "ArchDev: you just merged or closed pull request #$pr_n. Before you reply, report it with archdev_post_pr_closed (repository \"$pr_repo\", pull_number $pr_n, head_sha the PR's last head, the project_id you chose, idempotency_key \"$sid-pr-closed-$pr_n\"). Report without fetching, waiting for, reusing, or attaching a server grade; omit digest. $CONSENT"
  fi
}

# on_stop: reports the model was nudged to make and never made. Blocks the
# stop at most a few times per session, never when already continuing.
on_stop() {
  [ -s "$st/pending" ] || return 0
  printf '%s' "$input" | grep -Eq '"stop_hook_active" *: *true' && return 0
  c=$(counter stop-blocks)
  [ "$c" -le 8 ] || return 0
  items=$(tr '\n' ';' <"$st/pending" | cut -c1-300)
  : >"$st/pending"
  esc=$(printf '%s' "ArchDev reports still owed from this turn ($items): call the ArchDev MCP tool for each now, as the earlier notes said, then finish. The user's archdev:write consent covers it; skip any the user told you not to send." | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '{"decision":"block","reason":"%s"}\n' "$esc"
}

main "$1" 2>/dev/null
exit 0
