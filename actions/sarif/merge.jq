# Merges the runs of several SARIF files of one tool into a single run, because code scanning
# accepts one run per tool and category. Input: a list of SARIF documents.
map(.runs // []) | add // []
| if length == 0 then empty
  else
    . as $runs
    | {
        "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
        version: "2.1.0",
        runs: [
          $runs[0]
          | .results = ([$runs[].results // []] | add)
          | .tool.driver.rules = ([$runs[].tool.driver.rules // []] | add | unique_by(.id))
        ]
      }
  end
