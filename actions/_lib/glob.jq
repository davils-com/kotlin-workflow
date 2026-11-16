# Turns a glob into an anchored regular expression: ** crosses directories, * and ? do not.
def glob_regex:
  gsub("(?<c>[.+^$(){}|\\[\\]\\\\])"; "\\\(.c)")
  | gsub("\\*\\*/"; "\u0001")
  | gsub("\\*\\*"; "\u0002")
  | gsub("\\*"; "[^/]*")
  | gsub("\\?"; "[^/]")
  | gsub("\u0001"; "(.*/)?")
  | gsub("\u0002"; ".*")
  | "^" + . + "$";
