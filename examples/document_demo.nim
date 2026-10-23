import nifkit

let document = parseNif("(record title \"before\" count 1)")
let record = document[0]
record[1].text = "after"
for node in document.walk():
  if node.kind == nfInt:
    node.intValue = node.intValue + 1
record.add document.newString("added")
doAssert document.renderNif() == "(record title \"after\" count 2 \"added\")"
let loaded = parseBifTree(document.renderBif())
doAssert loaded.renderNif() == document.renderNif()
echo loaded.renderNif()
