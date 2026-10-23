## Editable, language-neutral NIF/BIF documents.
## Nodes are stable handles into an owning document, not recursive owning refs.
## Detaching a node keeps it alive until its document is released.
import std/[math, strutils, options]
import ./[bif_decoder, nif_encoder, codec_limits, line_info]
import ./private/[bif_tokens, bif_builder]

export line_info.LineInfo

type
  NifNodeKind* = enum
    nfEmpty, nfChar, nfString, nfInt, nfUInt, nfFloat,
    nfSymbol, nfSymbolDef, nfIdentifier, nfCompound

  NodeData = object
    kind: NifNodeKind
    parent: int # -1: document root; -2: detached
    text: string
    signed: int64
    unsigned: uint64
    real: float64
    byteValue: char
    children: seq[int]
    hasInfo: bool
    info: LineInfo

  NifDocument* = ref object
    nodes: seq[NodeData]
    rootIds: seq[int]
    revision: int

  NifNode* = object
    document: NifDocument
    id: int

proc malformed(message: string) {.noreturn.} =
  raiseCodecError(nkeMalformedInput, message)

proc checked(document: NifDocument) =
  if document == nil: malformed("NIF document is nil")

proc checked(node: NifNode): NifDocument =
  node.document.checked()
  if node.id < 0 or node.id >= node.document.nodes.len:
    malformed("invalid NIF node handle")
  node.document

proc requireKind(node: NifNode; kinds: set[NifNodeKind]): NifDocument =
  result = node.checked()
  if result.nodes[node.id].kind notin kinds:
    raiseCodecError(nkeTypeMismatch, "operation is not valid for " & $result.nodes[node.id].kind)

proc checkIndex(index, length: int; insertion = false) =
  if index < 0 or index > length or (not insertion and index == length):
    malformed("NIF node index is out of bounds")

proc checkTag(value: string) =
  if value.len == 0 or
      (value[0] == '.' and (value.len == 1 or not isIdentStartByte(value[1]))):
    malformed("invalid NIF tag name")

proc checkSymbol(value: string) =
  if value.find('.') <= 0: malformed("NIF symbol needs a name and a dot separator")

proc checkInfo(value: LineInfo) =
  if value.column < 0 or value.column > 1023 or
      value.line < 0 or value.line > int64(uint32.high):
    malformed("line information exceeds the supported BIF layout")

proc handle(document: NifDocument; id: int): NifNode =
  NifNode(document: document, id: id)

proc appendNode(document: NifDocument; data: sink NodeData): NifNode =
  document.checked()
  result = document.handle(document.nodes.len)
  document.nodes.add data

proc newNifDocument*(): NifDocument = NifDocument()

proc newEmpty*(document: NifDocument): NifNode =
  document.appendNode(NodeData(kind: nfEmpty, parent: -2))
proc newChar*(document: NifDocument; value: char): NifNode =
  document.appendNode(NodeData(kind: nfChar, parent: -2, byteValue: value))
proc newString*(document: NifDocument; value: string): NifNode =
  document.appendNode(NodeData(kind: nfString, parent: -2, text: value))
proc newInt*(document: NifDocument; value: int64): NifNode =
  document.appendNode(NodeData(kind: nfInt, parent: -2, signed: value))
proc newUInt*(document: NifDocument; value: uint64): NifNode =
  document.appendNode(NodeData(kind: nfUInt, parent: -2, unsigned: value))
proc newFloat*(document: NifDocument; value: float64): NifNode =
  document.appendNode(NodeData(kind: nfFloat, parent: -2, real: value))
proc newIdentifier*(document: NifDocument; value: string): NifNode =
  if value.len == 0: malformed("NIF identifier cannot be empty")
  document.appendNode(NodeData(kind: nfIdentifier, parent: -2, text: value))
proc newSymbol*(document: NifDocument; value: string): NifNode =
  checkSymbol(value)
  document.appendNode(NodeData(kind: nfSymbol, parent: -2, text: value))
proc newSymbolDef*(document: NifDocument; value: string): NifNode =
  checkSymbol(value)
  document.appendNode(NodeData(kind: nfSymbolDef, parent: -2, text: value))
proc newCompound*(document: NifDocument; tag: string): NifNode =
  checkTag(tag)
  document.appendNode(NodeData(kind: nfCompound, parent: -2, text: tag))

proc kind*(node: NifNode): NifNodeKind = node.checked().nodes[node.id].kind
proc len*(document: NifDocument): int =
  document.checked()
  document.rootIds.len
proc len*(node: NifNode): int = node.checked().nodes[node.id].children.len

proc parent*(node: NifNode): Option[NifNode] =
  let document = node.checked()
  let id = document.nodes[node.id].parent
  if id >= 0: some(document.handle(id)) else: none(NifNode)

proc `[]`*(document: NifDocument; index: int): NifNode =
  document.checked()
  checkIndex(index, document.rootIds.len)
  document.handle(document.rootIds[index])
proc `[]`*(node: NifNode; index: int): NifNode =
  let document = node.requireKind({nfCompound})
  checkIndex(index, document.nodes[node.id].children.len)
  document.handle(document.nodes[node.id].children[index])

proc tag*(node: NifNode): string = node.requireKind({nfCompound}).nodes[node.id].text
proc `tag=`*(node: NifNode; value: string) =
  let document = node.requireKind({nfCompound})
  checkTag(value)
  document.nodes[node.id].text = value
proc text*(node: NifNode): string =
  node.requireKind({nfString, nfIdentifier, nfSymbol, nfSymbolDef}).nodes[node.id].text
proc `text=`*(node: NifNode; value: string) =
  let document = node.requireKind({nfString, nfIdentifier, nfSymbol, nfSymbolDef})
  case document.nodes[node.id].kind
  of nfIdentifier:
    if value.len == 0: malformed("NIF identifier cannot be empty")
  of nfSymbol, nfSymbolDef: checkSymbol(value)
  else: discard
  document.nodes[node.id].text = value
proc intValue*(node: NifNode): int64 = node.requireKind({nfInt}).nodes[node.id].signed
proc `intValue=`*(node: NifNode; value: int64) =
  node.requireKind({nfInt}).nodes[node.id].signed = value
proc uintValue*(node: NifNode): uint64 = node.requireKind({nfUInt}).nodes[node.id].unsigned
proc `uintValue=`*(node: NifNode; value: uint64) =
  node.requireKind({nfUInt}).nodes[node.id].unsigned = value
proc floatValue*(node: NifNode): float64 = node.requireKind({nfFloat}).nodes[node.id].real
proc `floatValue=`*(node: NifNode; value: float64) =
  node.requireKind({nfFloat}).nodes[node.id].real = value
proc charValue*(node: NifNode): char = node.requireKind({nfChar}).nodes[node.id].byteValue
proc `charValue=`*(node: NifNode; value: char) =
  node.requireKind({nfChar}).nodes[node.id].byteValue = value

proc hasLineInfo*(node: NifNode): bool = node.checked().nodes[node.id].hasInfo
proc lineInfo*(node: NifNode): LineInfo =
  ## Returns effective absolute position; comments belong only to their node.
  let document = node.checked()
  var id = node.id
  while id >= 0:
    if document.nodes[id].hasInfo:
      result = document.nodes[id].info
      if id != node.id: result.comment.setLen(0)
      return
    id = document.nodes[id].parent
proc `lineInfo=`*(node: NifNode; value: LineInfo) =
  let document = node.checked()
  checkInfo(value)
  document.nodes[node.id].info = value
  document.nodes[node.id].hasInfo = true
proc clearLineInfo*(node: NifNode) =
  let document = node.checked()
  document.nodes[node.id].info = LineInfo()
  document.nodes[node.id].hasInfo = false

proc checkAttachment(document: NifDocument; parent: int; child: NifNode) =
  document.checked()
  discard child.checked()
  if child.document != document: malformed("clone a node before attaching it to another document")
  if document.nodes[child.id].parent != -2: malformed("detach an attached node before moving it")
  var ancestor = parent
  while ancestor >= 0:
    if ancestor == child.id:
      raiseCodecError(nkeCyclicReference, "NIF tree edits cannot create cycles")
    ancestor = document.nodes[ancestor].parent

proc insert*(document: NifDocument; index: int; child: NifNode) =
  document.checked()
  checkIndex(index, document.rootIds.len, true)
  document.checkAttachment(-1, child)
  document.rootIds.insert(child.id, index)
  document.nodes[child.id].parent = -1
  inc document.revision
proc insert*(node: NifNode; index: int; child: NifNode) =
  let document = node.requireKind({nfCompound})
  checkIndex(index, document.nodes[node.id].children.len, true)
  document.checkAttachment(node.id, child)
  document.nodes[node.id].children.insert(child.id, index)
  document.nodes[child.id].parent = node.id
  inc document.revision
proc add*(document: NifDocument; child: NifNode) = document.insert(document.len, child)
proc add*(node: NifNode; child: NifNode) = node.insert(node.len, child)

proc remove*(document: NifDocument; index: int): NifNode =
  result = document[index]
  document.rootIds.delete(index)
  document.nodes[result.id].parent = -2
  inc document.revision
proc remove*(node: NifNode; index: int): NifNode =
  result = node[index]
  let document = node.document
  document.nodes[node.id].children.delete(index)
  document.nodes[result.id].parent = -2
  inc document.revision
proc detach*(node: NifNode) =
  let document = node.checked()
  let parent = document.nodes[node.id].parent
  if parent == -1:
    discard document.remove(document.rootIds.find(node.id))
  elif parent >= 0:
    discard document.handle(parent).remove(document.nodes[parent].children.find(node.id))

proc `[]=`*(document: NifDocument; index: int; replacement: NifNode) =
  let previous = document[index]
  if previous == replacement: return
  document.checkAttachment(-1, replacement)
  document.nodes[previous.id].parent = -2
  document.rootIds[index] = replacement.id
  document.nodes[replacement.id].parent = -1
  inc document.revision
proc `[]=`*(node: NifNode; index: int; replacement: NifNode) =
  let previous = node[index]
  if previous == replacement: return
  let document = node.document
  document.checkAttachment(node.id, replacement)
  document.nodes[previous.id].parent = -2
  document.nodes[node.id].children[index] = replacement.id
  document.nodes[replacement.id].parent = node.id
  inc document.revision

iterator items*(document: NifDocument): NifNode =
  document.checked()
  let revision = document.revision
  var index = 0
  while index < document.rootIds.len:
    yield document.handle(document.rootIds[index])
    if revision != document.revision: malformed("NIF structure changed during iteration")
    inc index
iterator items*(node: NifNode): NifNode =
  let document = node.requireKind({nfCompound})
  let revision = document.revision
  # Reacquire the arena entry after each yield: creating a detached node may
  # relocate nodes without changing this compound's child list.
  var index = 0
  while index < document.nodes[node.id].children.len:
    yield document.handle(document.nodes[node.id].children[index])
    if revision != document.revision: malformed("NIF structure changed during iteration")
    inc index

iterator walkFrom(document: NifDocument; roots: openArray[int]): NifNode =
  document.checked()
  let revision = document.revision
  var stack: seq[int]
  for index in countdown(roots.high, 0): stack.add roots[index]
  while stack.len > 0:
    let id = stack.pop()
    yield document.handle(id)
    if revision != document.revision: malformed("NIF structure changed during traversal")
    for index in countdown(document.nodes[id].children.high, 0):
      stack.add document.nodes[id].children[index]

iterator walk*(document: NifDocument): NifNode =
  ## Preorder traversal. Scalar edits are allowed; structural edits are rejected.
  document.checked()
  for node in walkFrom(document, document.rootIds): yield node

iterator walk*(node: NifNode): NifNode =
  ## Visits the node itself and all descendants in preorder.
  let document = node.checked()
  for child in walkFrom(document, [node.id]): yield child

proc cloneSubtree*(document: NifDocument; source: NifNode): NifNode =
  ## Copies a subtree, including explicit suffix metadata, as a detached node.
  document.checked()
  let owner = source.checked()
  proc copyNode(id: int): NifNode =
    var data = owner.nodes[id]
    data.children = @[]
    data.parent = -2
    document.appendNode(move(data))
  result = copyNode(source.id)
  var stack = @[(source.id, result.id)]
  while stack.len > 0:
    let (oldId, newId) = stack.pop()
    let childIds = owner.nodes[oldId].children
    for child in childIds:
      let copied = copyNode(child)
      document.nodes[newId].children.add copied.id
      document.nodes[copied.id].parent = newId
      stack.add (child, copied.id)

proc treeFromTokens(tokens: BifDocument; limits: CodecLimits): NifDocument =
  result = newNifDocument()
  type Frame = tuple[id, finish: int]
  var frames: seq[Frame]
  var position = 0
  while position < tokens.tokens.len:
    while frames.len > 0 and position == frames[^1].finish: discard frames.pop()
    let boundary = if frames.len == 0: tokens.tokens.len else: frames[^1].finish
    if position >= boundary: malformed("BIF node crosses its parent boundary")
    let tokenKind = bif_tokens.kind(tokens.tokens[position])
    let wide = tokens.widePayload(position)
    if wide.next > boundary: malformed("BIF value crosses its parent boundary")
    var next = wide.next
    let suffix = tokens.takeLineInfo(next, LineInfo())
    if next > boundary: malformed("BIF suffix crosses its parent boundary")
    var data = NodeData(parent: if frames.len == 0: -1 else: frames[^1].id,
                        hasInfo: suffix.present,
                        info: if suffix.present: suffix.value else: LineInfo())
    var bodyEnd = next
    case tokenKind
    of KindDot: data.kind = nfEmpty
    of KindChar:
      if wide.value > 255: malformed("BIF character exceeds one byte")
      data.kind = nfChar
      data.byteValue = char(wide.value)
    of KindString, KindIdent, KindSymbol, KindSymbolDef:
      data.kind = case tokenKind
        of KindString: nfString
        of KindIdent: nfIdentifier
        of KindSymbol: nfSymbol
        else: nfSymbolDef
      data.text = tokens.textValue(wide.value, (tokenKind == KindSymbol or tokenKind == KindSymbolDef))
      if data.kind == nfIdentifier and data.text.len == 0: malformed("NIF identifier cannot be empty")
      if data.kind in {nfSymbol, nfSymbolDef}: checkSymbol(data.text)
      if data.text.len > limits.maxStringBytes:
        raiseCodecError(nkeStringLimit, "NIF node text exceeds configured limit", position)
    of KindInt:
      data.kind = nfInt
      let bits = min(64, 28 * (wide.next - position))
      if bits == 64: data.signed = cast[int64](wide.value)
      elif (wide.value and (1'u64 shl (bits - 1))) == 0: data.signed = int64(wide.value)
      else: data.signed = int64(wide.value) - (1'i64 shl bits)
    of KindUInt:
      data.kind = nfUInt
      data.unsigned = wide.value
    of KindFloat:
      data.kind = nfFloat
      data.real = cast[float64](wide.value)
    of KindTag:
      let tagId = wide.value and 0x1ff
      if tagId == 0 or tagId > uint64(tokens.tags.len): malformed("invalid BIF tag id")
      let jump = wide.value shr 9
      if jump > uint64(boundary - next): malformed("invalid BIF tag jump")
      bodyEnd = next + int(jump)
      data.kind = nfCompound
      data.text = tokens.tags[int(tagId) - 1]
      checkTag(data.text)
    else: malformed("unsupported BIF token kind")
    let depth = frames.len + ord(data.kind == nfCompound)
    if depth > limits.maxNestingDepth:
      raiseCodecError(nkeNestingTooDeep, "NIF tree exceeds configured depth", position)
    let siblings = if data.parent < 0: result.rootIds.len else: result.nodes[data.parent].children.len
    if siblings >= limits.maxContainerItems:
      raiseCodecError(nkeTokenLimit, "NIF children exceed configured container limit", position)
    if result.nodes.len >= limits.maxTokens:
      raiseCodecError(nkeTokenLimit, "NIF node count exceeds configured limit", position)
    let node = result.appendNode(move(data))
    if frames.len == 0: result.rootIds.add node.id
    else: result.nodes[frames[^1].id].children.add node.id
    if tokenKind == KindTag and bodyEnd > next:
      frames.add (node.id, bodyEnd)
    position = next
  while frames.len > 0 and position == frames[^1].finish: discard frames.pop()
  if frames.len > 0: malformed("unterminated BIF node")

proc parseNif*(source: string; limits = defaultCodecLimits()): NifDocument =
  ## Parses NIF directly, without serializing an intermediate BIF payload.
  treeFromTokens(parseNifTokens(source, limits), limits)

proc parseBifTree*(source: string; limits = defaultCodecLimits()): NifDocument =
  ## The existing parseBif API continues to return the low-level BifDocument.
  treeFromTokens(parseBif(source, limits), limits)

proc tokenDocument(document: NifDocument; limits: CodecLimits;
                   textOutput: bool): BifDocument =
  document.checked()
  validLimits(limits)
  if document.rootIds.len > limits.maxContainerItems:
    raiseCodecError(nkeTokenLimit, "NIF roots exceed configured container limit")
  type Task = tuple[id, depth, head, bodyStart, sourceId: int, closing: bool]
  var tasks: seq[Task]
  for index in countdown(document.rootIds.high, 0):
    tasks.add (document.rootIds[index], 0, 0, 0, -1, false)
  var builder = TokenBuilder(limits: limits, pos: -1)
  while tasks.len > 0:
    let task = tasks.pop()
    if task.closing:
      let jump = builder.doc.tokens.len - task.bodyStart
      let tagId = uint64(builder.doc.tokens[task.head] shr 4) and 0x1ff
      builder.doc.tokens[task.head] =
        (uint32(tagId or (uint64(jump and 0x7ffff) shl 9)) shl 4) or KindTag
      if jump > 524287:
        let high = uint64(jump shr 19)
        if high > Mask28: malformed("BIF tag jump exceeds version 5 limit")
        if builder.doc.tokens.len >= limits.maxTokens:
          raiseCodecError(nkeTokenLimit, "NIF token count exceeds configured limit")
        builder.doc.tokens.insert((uint32(high) shl 4) or KindExtended, task.head + 1)
      continue
    let data = document.nodes[task.id]
    if task.depth + ord(data.kind == nfCompound) > limits.maxNestingDepth:
      raiseCodecError(nkeNestingTooDeep, "NIF tree exceeds configured depth")
    if data.children.len > limits.maxContainerItems:
      raiseCodecError(nkeTokenLimit, "NIF children exceed configured container limit")
    if data.kind in {nfString, nfIdentifier, nfSymbol, nfSymbolDef, nfCompound} and
        data.text.len > limits.maxStringBytes:
      raiseCodecError(nkeStringLimit, "NIF node text exceeds configured limit")
    let head = builder.doc.tokens.len
    case data.kind
    of nfEmpty: builder.emit(KindDot, 0)
    of nfChar: builder.emit(KindChar, uint64(ord(data.byteValue)))
    of nfString: builder.emitText(KindString, data.text)
    of nfIdentifier: builder.emitText(KindIdent, data.text)
    of nfSymbol: builder.emitText(KindSymbol, data.text, true)
    of nfSymbolDef: builder.emitText(KindSymbolDef, data.text, true)
    of nfInt: builder.emitSigned(data.signed)
    of nfUInt: builder.emit(KindUInt, data.unsigned)
    of nfFloat:
      if textOutput and classify(data.real) in {fcNan, fcInf, fcNegInf}:
        raiseCodecError(nkeNonFiniteFloat, "non-finite BIF floats have no NIF text literal")
      builder.emit(KindFloat, cast[uint64](data.real))
    of nfCompound:
      let tagId = builder.poolId(builder.doc.tags, builder.tags, data.text)
      if tagId > 511: malformed("NIF has more than 511 BIF tags")
      builder.emit(KindTag, uint64(tagId))
    let parentInfo = if task.sourceId < 0: LineInfo() else: document.nodes[task.sourceId].info
    let info = if data.hasInfo: data.info else: parentInfo
    if textOutput and data.hasInfo and info.filename.len == 0 and parentInfo.filename.len > 0:
      malformed("NIF text cannot reset an inherited filename to empty")
    if data.hasInfo: builder.emitLineInfo(info)
    if data.kind == nfCompound:
      tasks.add (task.id, task.depth, head, builder.doc.tokens.len, task.sourceId, true)
      for index in countdown(data.children.high, 0):
        tasks.add (data.children[index], task.depth + 1, 0, 0,
                   if data.hasInfo: task.id else: task.sourceId, false)
  result = move(builder.doc)

proc renderBif*(document: NifDocument; limits = defaultCodecLimits()): string =
  ## Rebuilds pools, tag jumps and the global index from the reachable tree.
  try:
    result = encodeBifDocument(tokenDocument(document, limits, false), limits)
  except NifKitError: raise
  except BifError: raiseCodecError(nkeMalformedInput, getCurrentExceptionMsg())

proc renderNif*(document: NifDocument; limits = defaultCodecLimits()): string =
  ## Canonical output preserves semantic nodes and suffixes, not whitespace.
  try:
    result = renderBifDocument(tokenDocument(document, limits, true), limits)
  except NifKitError: raise
  except BifError: raiseCodecError(nkeMalformedInput, getCurrentExceptionMsg())

proc validateDocument*(document: NifDocument; limits = defaultCodecLimits()) =
  ## Validates BIF representability and the selected output/resource limits.
  discard document.renderBif(limits)

proc validateNif*(source: string; limits = defaultCodecLimits()) =
  ## Checks NIF syntax and parse budgets without a returned tree or output bytes.
  discard parseNif(source, limits)
