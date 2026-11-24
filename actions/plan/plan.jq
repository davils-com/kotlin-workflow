# Merges the configuration layers, validates them against the defaults and decides what one event
# runs. Input: null. Arguments: $defaults, $file, $inline (objects), $fileName, $eventName, $ref,
# $refName, $cron, $draft, $stagesInput, $dryRun (strings), $changed (array of paths or null).

def stage_names: ["dependencies", "check", "security", "snapshot", "release", "docs", "benchmark"];

def native_platforms: ["linux", "windows", "macos"] | map(. as $os | ["x86_64", "aarch64"] | map($os + "-" + .)) | add;

def native_stage_names: ["check", "snapshot", "release"];

# The runners of the native stage are a list of objects the defaults cannot describe, so they are
# checked here, after every layer is merged.
def native_problems:
  .native as $n
  | ($n.runners | to_entries[] | .key as $index | .value as $runner | "native.runners[\($index)]" as $at
     | if ($runner | type) != "object" then "\($at): expected an object, got \($runner | type)"
       else
         ($runner | keys[] | select(. != "platform" and . != "runs-on" and . != "jdk") | "\($at).\(.): unknown option"),
         (if ($runner | has("jdk")) then
            ($runner.jdk) as $jdk
            | if ($jdk | type) != "object" then "\($at).jdk: expected an object, got \($jdk | type)"
              else
                ($jdk | keys[] | select(. != "distribution" and . != "version") | "\($at).jdk.\(.): unknown option"),
                ($jdk | to_entries[] | select(.key == "distribution" or .key == "version")
                 | select((.value | type) != "string" and (.value | type) != "number")
                 | "\($at).jdk.\(.key): expected string, got \(.value | type)")
              end
          else empty end),
         (if ($runner.platform | type) != "string" then "\($at).platform: expected a platform such as windows-x86_64"
          elif (native_platforms | index($runner.platform)) == null then "\($at).platform: '\($runner.platform)' is not one of \(native_platforms | join(", "))"
          else empty end),
         (($runner["runs-on"]) as $labels
          | if ($labels | type) == "string" and ($labels | length) > 0 then empty
            elif ($labels | type) == "array" and ($labels | length) > 0 and all($labels[]; type == "string") then empty
            else "\($at).runs-on: expected a runner label or a list of labels" end)
       end),
    ([$n.runners[] | objects | .platform | strings] | group_by(.) | map(select(length > 1) | .[0])[]
     | "native.runners: the platform \(.) is listed twice"),
    ($n.stages[] | . as $stage | select(native_stage_names | index($stage) == null)
     | "native.stages: '\($stage)' is not one of \(native_stage_names | join(", "))"),
    (if ($n.runners | length) > 0 and ($n["stage-task"] | length) == 0 then "native.stage-task: empty, but native.runners lists runners" else empty end),
    (if ($n.runners | length) > 0 and ($n["stage-directory"] | length) == 0 then "native.stage-directory: empty, but native.runners lists runners" else empty end);

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
        | [$merged | native_problems] as $nativeErrors
        | if ($unknown | length) > 0 then {errors: ["unknown stage: \($unknown | join(", "))"]}
          elif ($nativeErrors | length) > 0 then {errors: $nativeErrors}
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
            | (if ($merged.native.runners | length) > 0 then $merged.native.stages else [] end) as $nativeStages
            | any($nativeStages[]; . as $name | $stages | index($name) != null) as $native
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
                   "native-stages": $nativeStages,
                   "catalog-changed": ($changed == null
                     or ([.dependencies.catalog] + .dependencies.triggers | any(. as $path | $changed | index($path) != null)))
                 }) as $config
            | {
                config: $config,
                stages: (stage_names | map({key: ., value: (. as $name | $stages | index($name) != null)}) | from_entries),
                matrix: ($policy.os | os_matrix),
                natives: (if $native then [$merged.native.runners[].platform] else [] end),
                event: $event,
                version: $version,
                reason: (if $skippedDraft then "the pull request is a draft"
                         elif $filtered and $onlyIgnored and ($stagesInput | length) == 0 then "only ignored paths changed"
                         else "" end)
              }
          end
      end
  end
