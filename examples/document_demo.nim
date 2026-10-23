import nifkit/document

let doc = parseNif("(record title \"before\" count 1)")
let record = doc[0]
record[1].text = "after"
for node in doc.walk():
  if node.kind == nfInt:
    node.intValue = node.intValue + 1
record.add doc.newString("added")
doAssert doc.renderNif() == "(record title \"after\" count 2 \"added\")"
let loaded = parseBifTree(doc.renderBif())
doAssert loaded.renderNif() == doc.renderNif()
echo loaded.renderNif()
