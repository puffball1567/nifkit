## NIF line-info and comment suffix parsing/rendering from the public NIF
## specification.

import std/algorithm

type LineInfo* = object
  column*, line*: int64
  filename*, comment*: string

proc digit62(c: char): int64 =
  if c in {'0'..'9'}: int64(ord(c) - ord('0'))
  elif c in {'A'..'Z'}: int64(ord(c) - ord('A') + 10)
  elif c in {'a'..'z'}: int64(ord(c) - ord('a') + 36)
  else: -1

proc decodeHex(c: char): int =
  if c in {'0'..'9'}: ord(c) - ord('0')
  elif c in {'A'..'F'}: ord(c) - ord('A') + 10
  else: -1

proc readNifEscape*(source: string; pos: var int): char =
  if pos >= source.len or source[pos] != '\\':
    raise newException(ValueError, "expected NIF escape")
  inc pos
  if pos >= source.len:
    raise newException(ValueError, "truncated NIF escape")
  let a = source[pos]
  inc pos
  case a
  of 'n': '\n'
  of 't': '\t'
  of 'r': '\r'
  of '|': '\\'
  of '^': '"'
  of '0'..'9', 'A'..'F':
    if pos >= source.len:
      raise newException(ValueError, "truncated hexadecimal NIF escape")
    let b = source[pos]
    inc pos
    let hi = decodeHex(a)
    let lo = decodeHex(b)
    if hi < 0 or lo < 0:
      raise newException(ValueError, "invalid hexadecimal NIF escape")
    char((hi shl 4) or lo)
  else:
    raise newException(ValueError, "unsupported NIF escape")

proc isRawNifControl*(c: char): bool =
  c in {'(', ')', '[', ']', '{', '}', '~', '#', '\'', '"', '\\', ':', '@'}

proc unescapeNifData*(source: string; pos: var int; terminators: set[char]): string =
  while pos < source.len and source[pos] notin terminators:
    let c = source[pos]
    if c != '\\':
      if isRawNifControl(c):
        raise newException(ValueError, "unescaped NIF control character")
      let b = ord(c)
      if b < 32 and c notin {' ', '\t', '\r', '\n'}:
        raise newException(ValueError, "unescaped NIF control byte")
      inc pos
      result.add c
    else:
      result.add readNifEscape(source, pos)

proc escapeNifData*(value: string): string =
  const Hex = "0123456789ABCDEF"
  for c in value:
    let b = ord(c)
    if c == '"': result.add "\\^"
    elif c == '\\': result.add "\\|"
    elif b == 10: result.add "\\n"
    elif b == 9: result.add "\\t"
    elif b == 13: result.add "\\r"
    elif b <= 32 or c in {'(', ')', '[', ']', '{', '}', '~', '#', '\'', ':', '@'}:
      result.add '\\'
      result.add Hex[b shr 4]
      result.add Hex[b and 15]
    else:
      result.add c

proc parse62(source: string; pos: var int): int64 =
  var negative = false
  if pos < source.len and source[pos] == '~':
    negative = true
    inc pos
  var digits = 0
  while pos < source.len:
    let d = digit62(source[pos])
    if d < 0: break
    result = result * 62 + d
    inc pos
    inc digits
  if negative and digits == 0:
    raise newException(ValueError, "expected base62 digits after NIF line-info '~'")
  if negative: result = -result

proc encode62(value: int64): string =
  const Alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
  if value == 0: return "0"
  var n = if value < 0: -value else: value
  while n > 0:
    result.add Alphabet[int(n mod 62)]
    n = n div 62
  result.reverse()
  if value < 0: result = "~" & result

proc parseLineInfo*(source: string; pos: var int; parent: LineInfo): LineInfo =
  if pos >= source.len or source[pos] notin {'@', '~'}:
    raise newException(ValueError, "expected NIF line-info suffix")
  if source[pos] == '@': inc pos
  let columnDiff = parse62(source, pos)
  var lineDiff = 0'i64
  if pos < source.len and source[pos] == ',':
    inc pos
    lineDiff = parse62(source, pos)
    if pos < source.len and source[pos] == ',':
      inc pos
      result.filename = unescapeNifData(source, pos, {'#', ' ', '\t', '\r', '\n', ')'})
  result.column = parent.column + columnDiff
  result.line = parent.line + lineDiff
  if result.filename.len == 0: result.filename = parent.filename
  if pos < source.len and source[pos] == '#':
    inc pos
    result.comment = unescapeNifData(source, pos, {'#'})
    if pos >= source.len: raise newException(ValueError, "unterminated NIF line-info comment")
    inc pos

proc renderLineInfo*(value, parent: LineInfo): string =
  let columnDiff = value.column - parent.column
  let lineDiff = value.line - parent.line
  if value.comment.len > 0 and columnDiff == 0 and lineDiff == 0 and
      value.filename == parent.filename:
    return "#" & escapeNifData(value.comment) & "#"
  result = "@" & encode62(columnDiff) & "," & encode62(lineDiff)
  if value.filename.len > 0 and value.filename != parent.filename:
    result.add "," & escapeNifData(value.filename)
  if value.comment.len > 0:
    result.add "#" & escapeNifData(value.comment) & "#"
