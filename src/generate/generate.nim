import std/[os, strformat, strscans, strutils, terminal]
import ".."/[cli, helpers]

proc writeError(description, path: string) =
  let descriptionPrefix = description & ":"
  if colorStdout:
    stdout.styledWriteLine(fgRed, descriptionPrefix)
  else:
    stdout.writeLine(descriptionPrefix)
  stdout.writeLine(path)
  stdout.write "\n"

proc conceptIntroduction(conf: Conf, slug: string): string =
  let path = conf.trackDir / "concepts" / slug / "introduction.md"
  if fileExists(path):
    let content = readFile(path)
    var idx = 0
    if scanp(content, idx, "#", +' ', +(~'\n')):
      result = content.substr(idx).strip
    else:
      result = content.strip
  else:
    writeError(&"Referenced '{slug}' concept does not have an 'introduction.md' file", path)

proc generateIntroduction(conf: Conf, templateFilePath: Path): string =
  let content = readFile(templateFilePath)
  
  var idx = 0
  while idx < content.len:
    var conceptSlug = ""
    if scanp(content, idx, "%{concept:", +{'a'..'z', '-'} -> conceptSlug.add($_), '}'):
      result.add(conceptIntroduction(conf, conceptSlug))
    else:
      result.add(content[idx])
      inc idx

proc generate*(conf: Conf) =
  let trackDir = Path(conf.trackDir)

  let conceptExercisesDir = trackDir / "exercises" / "concept"
  if dirExists(conceptExercisesDir):
    for conceptExerciseDir in getSortedSubdirs(conceptExercisesDir):
      let introductionTemplateFilePath = conceptExerciseDir / ".docs" / "introduction.md.tpl"
      if fileExists(introductionTemplateFilePath):
        let introduction = generateIntroduction(conf, introductionTemplateFilePath)
        let introductionFilePath = conceptExerciseDir / ".docs" / "introduction.md"
        writeFile(introductionFilePath, introduction)
