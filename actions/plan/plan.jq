# Merges the configuration layers, validates them against the defaults and decides what one event
# runs. Input: null. Arguments: $defaults, $file, $inline (objects), $fileName, $eventName, $ref,
# $refName, $cron, $draft, $stagesInput, $dryRun (strings), $changed (array of paths or null).

def stage_names: ["dependencies", "check", "security", "snapshot", "release", "docs", "benchmark"];

def freeform($rel): ($rel == ["env"]) or ($rel == ["schedule", "crons"]);

def is_overrides($rel): ($rel | length) == 3 and $rel[0] == "policy" and $rel[2] == "overrides";

def problems($d; $root; $path; $rel):
  . as $o
  | if is_overrides($rel) then
      if ($o | type) != "object" then "\($path | join(".")): expected an object, got \($o | type)"
      else
        (if ($o | has("policy")) then "\($path | join(".")): overrides cannot change the policy" else empty end),
        (if ($o | has("version")) then "\($path | join(".")): overrides cannot change the version" else empty end),
        ($o | del(.policy, .version) | to_entries[] | . as $e
         | if ($root | has($e.key)) then ($e.value | problems($root[$e.key]; $root; $path + [$e.key]; [$e.key]))
           else "\(($path + [$e.key]) | join(".")): unknown option" end)
      end
    elif freeform($rel) then
      if ($o | type) != "object" then "\($path | join(".")): expected an object, got \($o | type)" else empty end
    elif ($d | type) == "object" then
      if ($o | type) != "object" then "\($path | join(".")): expected an object, got \($o | type)"
      else ($o | to_entries[] | . as $e
            | if ($d | has($e.key)) then ($e.value | problems($d[$e.key]; $root; $path + [$e.key]; $rel + [$e.key]))
              else "\(($path + [$e.key]) | join(".")): unknown option" end)
      end
    elif ($o | type) == ($d | type) then empty
    elif ($d | type) == "string" and ($o | type) == "number" then empty
    else "\($path | join(".")): expected \($d | type), got \($o | type)" end;

def coerce($d):
  if type == "object" and ($d | type) == "object" then
    with_entries(.key as $k | .value |= coerce($d | if has($k) then .[$k] else null end))
  elif type == "number" and ($d | type) == "string" then tostring
  else . end;

def glob_regex:
  gsub("(?<c>[.+^$(){}|\\[\\]\\\\])"; "\\\(.c)")
  | gsub("\\*\\*/"; "\u0001")
  | gsub("\\*\\*"; "\u0002")
  | gsub("\\*"; "[^/]*")
  | gsub("\\?"; "[^/]")
  | gsub("\u0001"; "(.*/)?")
  | gsub("\u0002"; ".*")
  | "^" + . + "$";

def event_of($base):
  if $eventName == "pull_request" then "pull-request"
  elif $eventName == "merge_group" then "merge-group"
  elif $eventName == "schedule" then "schedule"
  elif $eventName == "workflow_dispatch" or $eventName == "workflow_call" then "workflow-dispatch"
  elif $eventName == "push" and ($ref | startswith("refs/tags/")) then "tag"
  elif $eventName == "push" and $refName == $base.branches.develop then "push-develop"
  elif $eventName == "push" and $refName == $base.branches.main then "push-main"
  elif $eventName == "push" then "push-other"
  else null end;

def released_version($config):
  $refName
  | ltrimstr($config.release.tag.prefix)
  | if $config.release.tag["allow-v"] then ltrimstr("v") else . end;

def os_matrix:
  to_entries
  | map(.key as $index | .value
        | if type == "string" then {name: ., "runs-on": .}
          else {name: (.name // (.["runs-on"] | tostring)), "runs-on": .["runs-on"]} end
        | . + {primary: ($index == 0)});

($defaults) as $d
| ($file // {}) as $f
| ($inline // {}) as $i
| ([($f | problems($d; $d; []; []) | "\($fileName): " + .)]
   + [($i | problems($d; $d; []; []) | "config input: " + .)]) as $errors
| if ($errors | length) > 0 then {errors: $errors}
  else
    ($d * $f * $i) as $base
    | event_of($base) as $event
    | if $base.version != 1 then {errors: ["version: only version 1 is supported"]}
      elif $event == null then {errors: ["the event '\($eventName)' is not supported"]}
      else
        ($base.policy[$event]) as $policy
        | (($base * $policy.overrides) | coerce($d)) as $merged
        | (if ($stagesInput | length) > 0 then ($stagesInput | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0)))
           elif $event == "schedule" and ($merged.schedule.crons | has($cron)) then $merged.schedule.crons[$cron]
           else $policy.stages end) as $wanted
        | ($wanted - stage_names) as $unknown
        | if ($unknown | length) > 0 then {errors: ["unknown stage: \($unknown | join(", "))"]}
          else
            ($merged.paths.ignore | map(glob_regex)) as $ignored
            | (["pull-request", "push-develop", "push-main", "push-other", "merge-group"] | index($event) != null) as $filtered
            | ($changed != null and ($changed | length) > 0
               and ([$changed[] | . as $path | any($ignored[]; . as $re | $path | test($re))] | all)) as $onlyIgnored
            | ($draft == "true" and ($merged["pull-request"].drafts | not)) as $skippedDraft
            | (if $skippedDraft then []
               elif $filtered and $onlyIgnored and ($stagesInput | length) == 0 then ($wanted | map(select(. == "docs")))
               else $wanted end) as $stages
            | (if $event == "tag" then released_version($merged) else "" end) as $version
            | (if (($event | startswith("push-")) and ($merged.gradle["cache-write-branches"] | index($refName) != null))
               then "read-write" else "read-only" end) as $cacheMode
            | ($merged
               | if $dryRun == "true" then .release["dry-run"] = true else . end
               | if $event == "tag" and (.release["version-env"] | length) > 0
                 then .env[.release["version-env"]] = $version else . end
               | .run = {
                   event: $event,
                   version: $version,
                   "cache-mode": $cacheMode,
                   "ref-name": $refName,
                   "catalog-changed": ($changed == null
                     or ([.dependencies.catalog] + .dependencies.triggers | any(. as $path | $changed | index($path) != null)))
                 }) as $config
            | {
                config: $config,
                stages: (stage_names | map({key: ., value: (. as $name | $stages | index($name) != null)}) | from_entries),
                matrix: ($policy.os | os_matrix),
                event: $event,
                version: $version,
                reason: (if $skippedDraft then "the pull request is a draft"
                         elif $filtered and $onlyIgnored and ($stagesInput | length) == 0 then "only ignored paths changed"
                         else "" end)
              }
          end
      end
  end
