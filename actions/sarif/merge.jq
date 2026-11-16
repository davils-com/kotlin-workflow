# Merges the runs of several SARIF files of one tool into a single run, because code scanning
# accepts one run per tool and category. Input: a list of SARIF documents.
#
# Code scanning refuses a result without a location, so a result that names no file is filed
# under $fallback when one is given.
def located:
  if $fallback == "" then .
  elif ((.locations // []) | length) > 0 then .
  else .locations = [{physicalLocation: {artifactLocation: {uri: $fallback}}}]
  end;

map(.runs // []) | add // []
| if length == 0 then empty
  else
    . as $runs
    | {
        "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
        version: "2.1.0",
        runs: [
          $runs[0]
          | .results = ([$runs[].results // []] | add | map(located))
          | .tool.driver.rules = ([$runs[].tool.driver.rules // []] | add | unique_by(.id))
        ]
      }
  end
